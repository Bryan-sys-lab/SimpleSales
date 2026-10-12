/**
 * Keycloak account management, from the server that holds the credentials.
 *
 * WHY THE BACKEND, NOT THE APP
 * Creating the owner's online account is the one step in onboarding that needs
 * an administrative credential. Shipped in an APK it is not a credential, it
 * is a published one — anyone can unzip the app, read it, and create an
 * account for somebody else's email. So the admin client lives here, and the
 * only thing that crosses the network to the phone is a token minted *after*
 * the email was verified.
 *
 * WHY THE ACCOUNT STARTS DISABLED
 * An account created for an email the caller does not own would otherwise sit
 * there, enabled, with a password the backend generated and nobody knows. The
 * user is created `enabled: false` with `emailVerified: false` and is only
 * switched on by `activateUser`, which runs after a code sent to that address
 * has been presented. A guessed PIN therefore buys the caller a disabled row
 * in the identity server and nothing else.
 */

import { randomBytes } from 'node:crypto';

export type KeycloakHttpResponse = {
  status: number;
  location?: string;
  body: unknown;
};

export type KeycloakHttp = (
  url: string,
  init: {
    method: string;
    headers: Record<string, string>;
    body?: string;
  },
) => Promise<KeycloakHttpResponse>;

export type KeycloakUser = {
  id: string;
  created: boolean;
};

export type KeycloakAdminOptions = {
  /** Origin of the Keycloak server, e.g. `https://id.example.com`. */
  baseUrl: string;
  realm: string;
  clientId: string;
  clientSecret: string;
  /** Override for the token endpoint; derived from baseUrl + realm by default. */
  tokenUrl?: string;
  http?: KeycloakHttp;
};

/** 192 bits, URL-safe: satisfies any password policy the realm may later grow,
 * and never leaves this process in either direction. */
function generatedPassword(): string {
  return randomBytes(24).toString('base64url');
}

export function createKeycloakAdminClient(options: KeycloakAdminOptions) {
  const http =
    options.http ??
    (async (url, init) => {
      const response = await fetch(url, init as RequestInit);
      const text = await response.text();
      let body: unknown = null;
      try {
        body = text ? JSON.parse(text) : null;
      } catch {
        body = text;
      }
      return {
        status: response.status,
        location: response.headers.get('location') ?? undefined,
        body,
      };
    });

  const adminBase = `${options.baseUrl.replace(/\/$/, '')}/admin/realms/${options.realm}`;
  const tokenUrl =
    options.tokenUrl ??
    `${options.baseUrl.replace(/\/$/, '')}/realms/${options.realm}/protocol/openid-connect/token`;

  async function adminToken(): Promise<string> {
    const response = await http(tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: options.clientId,
        client_secret: options.clientSecret,
      }).toString(),
    });
    const accessToken = (response.body as { access_token?: unknown } | null)?.access_token;
    if (response.status < 200 || response.status >= 300 || typeof accessToken !== 'string') {
      throw new Error(`Keycloak admin token refused (${response.status})`);
    }
    return accessToken;
  }

  function authHeaders(token: string): Record<string, string> {
    return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  }

  return {
    /** False when the realm credentials are absent, so callers can say
     * "linking is not configured" rather than failing halfway through. */
    get configured(): boolean {
      return Boolean(options.baseUrl && options.realm && options.clientId && options.clientSecret);
    },

    /**
     * The account for an email address, created if it does not exist.
     *
     * Idempotent by design: the owner who taps Verify a second time, on a
     * second device, gets the same account back rather than a 409.
     */
    async ensureUser(email: string): Promise<KeycloakUser> {
      const token = await adminToken();
      const created = await http(adminBase + '/users', {
        method: 'POST',
        headers: authHeaders(token),
        body: JSON.stringify({
          username: email,
          email,
          // See the file header: dark until the emailed code is presented.
          enabled: false,
          emailVerified: false,
          requiredActions: ['VERIFY_EMAIL'],
          credentials: [{ type: 'password', value: generatedPassword(), temporary: false }],
        }),
      });

      if (created.status === 409) {
        const existing = await http(
          `${adminBase}/users?username=${encodeURIComponent(email)}&exact=true`,
          { method: 'GET', headers: authHeaders(token) },
        );
        const users = existing.body as Array<{ id?: unknown }> | null;
        const id = users?.[0]?.id;
        if (typeof id !== 'string' || !id) {
          throw new Error('Keycloak reports the user exists but will not return it');
        }
        return { id, created: false };
      }

      if (created.status < 200 || created.status >= 300) {
        throw new Error(`Keycloak refused to create the user (${created.status})`);
      }

      // Keycloak answers 201 with the new id in Location, and no body.
      const location = created.location ?? '';
      const id = location.split('/').pop() ?? '';
      if (!id) throw new Error('Keycloak created the user without returning its id');
      return { id, created: true };
    },

    /** Turns the account on, which is the moment verification means anything. */
    async activateUser(userId: string): Promise<void> {
      const token = await adminToken();
      const response = await http(`${adminBase}/users/${encodeURIComponent(userId)}`, {
        method: 'PUT',
        headers: authHeaders(token),
        body: JSON.stringify({ enabled: true, emailVerified: true, requiredActions: [] }),
      });
      if (response.status < 200 || response.status >= 300) {
        throw new Error(`Keycloak refused to verify the email (${response.status})`);
      }
    },
  };
}

/**
 * Reads the realm admin configuration out of the environment.
 *
 * `OIDC_ISSUER_URL` is a realm URL (`https://id.example.com/realms/duka`), so
 * the server origin and the realm name are both derivable from it — an
 * operator who has already pointed the JWT verifier at their realm should not
 * have to configure the same server twice.
 */
export function keycloakAdminOptionsFromEnv(env: NodeJS.ProcessEnv): KeycloakAdminOptions | null {
  const clientId = env.KEYCLOAK_ADMIN_CLIENT_ID;
  const clientSecret = env.KEYCLOAK_ADMIN_CLIENT_SECRET;
  const issuer = (env.OIDC_ISSUER_URL ?? '').replace(/\/$/, '');
  const explicitRealm = env.KEYCLOAK_REALM;
  const explicitBase = env.KEYCLOAK_BASE_URL;

  let realm = explicitRealm ?? '';
  let baseUrl = explicitBase ?? '';
  if (!realm || !baseUrl) {
    const match = issuer.match(/^(https?:\/\/[^/]+)\/realms\/([^/]+)$/);
    if (match) {
      if (!baseUrl) baseUrl = match[1];
      if (!realm) realm = match[2];
    }
  }

  if (!realm || !baseUrl || !clientId || !clientSecret) return null;
  return {
    baseUrl,
    realm,
    clientId,
    clientSecret,
    ...(env.KEYCLOAK_TOKEN_URL ? { tokenUrl: env.KEYCLOAK_TOKEN_URL } : {}),
  };
}
