import { describe, expect, it } from 'vitest';
import { createKeycloakAdminClient, keycloakAdminOptionsFromEnv, type KeycloakHttp, type KeycloakHttpResponse } from '../lib/keycloak_admin.js';

/** A recorded exchange, so a test can assert what the realm was asked. */
function fakeHttp(responses: Array<Partial<KeycloakHttpResponse>>) {
  const calls: Array<{ url: string; init: { method: string; headers: Record<string, string>; body?: string } }> = [];
  let index = 0;
  const http: KeycloakHttp = async (url, init) => {
    calls.push({ url, init });
    const next = responses[Math.min(index, responses.length - 1)];
    index += 1;
    return { status: next.status ?? 200, location: next.location, body: next.body ?? null };
  };
  return { http, calls };
}

const tokenResponse = { status: 200, body: { access_token: 'admin-token' } };

function client(responses: Array<Partial<KeycloakHttpResponse>>) {
  const fake = fakeHttp([tokenResponse, ...responses]);
  const instance = createKeycloakAdminClient({
    baseUrl: 'https://id.example.test',
    realm: 'duka',
    clientId: 'duka-admin',
    clientSecret: 'secret',
    http: fake.http,
  });
  return { instance, calls: fake.calls };
}

describe('keycloak admin client', () => {
  it('says it is unconfigured without the realm credentials', () => {
    const { instance } = client([]);
    const bare = createKeycloakAdminClient({ baseUrl: '', realm: '', clientId: '', clientSecret: '' });
    expect(instance.configured).toBe(true);
    expect(bare.configured).toBe(false);
  });

  it('takes an admin token from the realm, not from a user login', async () => {
    const { instance, calls } = client([{ status: 201, location: 'https://id.example.test/admin/realms/duka/users/kc-1' }]);
    await instance.ensureUser('owner@example.com', '123456');
    expect(calls[0].url).toBe('https://id.example.test/realms/duka/protocol/openid-connect/token');
    expect(calls[0].init.body).toContain('grant_type=client_credentials');
    expect(calls[0].init.headers.Authorization).toBeUndefined();
  });

  it('creates the account dark: disabled, unverified, verify-email required', async () => {
    const { instance, calls } = client([{ status: 201, location: 'https://id.example.test/admin/realms/duka/users/kc-1' }]);
    await instance.ensureUser('owner@example.com', '123456');
    const payload = JSON.parse(calls[1].init.body!);
    expect(payload.username).toBe('owner@example.com');
    expect(payload.email).toBe('owner@example.com');
    expect(payload.enabled).toBe(false);
    expect(payload.emailVerified).toBe(false);
    expect(payload.requiredActions).toEqual(['VERIFY_EMAIL']);
    expect(payload.credentials).toHaveLength(1);
    // The password is the OWNER'S OWN admin PIN — the one secret they
    // already keep for the till. It is set here and never stored here:
    // Keycloak keeps a hash.
    expect(payload.credentials[0].value).toBe('123456');
    expect(payload.credentials[0].temporary).toBe(false);
  });

  it('reads the new user id out of Location, because Keycloak returns no body', async () => {
    const { instance } = client([{ status: 201, location: 'https://id.example.test/admin/realms/duka/users/kc-42' }]);
    const user = await instance.ensureUser('owner@example.com', '123456');
    expect(user).toEqual({ id: 'kc-42', created: true });
  });

  it('is idempotent: a second device gets the same account back', async () => {
    const { instance, calls } = client([
      { status: 409, body: { errorMessage: 'User exists' } },
      { status: 200, body: [{ id: 'kc-42' }] },
    ]);
    const user = await instance.ensureUser('owner@example.com', '123456');
    expect(user).toEqual({ id: 'kc-42', created: false });
    expect(calls[2].url).toContain('/users?username=owner%40example.com&exact=true');
  });

  it('fails loudly rather than inventing a user id', async () => {
    const { instance } = client([{ status: 201, location: undefined }]);
    await expect(instance.ensureUser('owner@example.com', '123456')).rejects.toThrow(/without returning its id/);
  });

  it('fails loudly when the realm will not hand back an existing user', async () => {
    const { instance } = client([
      { status: 409, body: { errorMessage: 'User exists' } },
      { status: 200, body: [] },
    ]);
    await expect(instance.ensureUser('owner@example.com', '123456')).rejects.toThrow(/will not return it/);
  });

  it('turns the account on only when the email is verified', async () => {
    const { instance, calls } = client([{ status: 204 }]);
    await instance.activateUser('kc-42');
    const payload = JSON.parse(calls[1].init.body!);
    expect(payload).toEqual({ enabled: true, emailVerified: true, requiredActions: [] });
    expect(calls[1].init.method).toBe('PUT');
    expect(calls[1].url).toBe('https://id.example.test/admin/realms/duka/users/kc-42');
  });

  it('reports a refused activation instead of claiming the shop is verified', async () => {
    const { instance } = client([{ status: 403, body: { error: 'insufficient permissions' } }]);
    await expect(instance.activateUser('kc-42')).rejects.toThrow(/refused to verify the email/);
  });
});

describe('realm configuration from the environment', () => {
  it('derives both the server origin and the realm from the issuer URL', () => {
    const options = keycloakAdminOptionsFromEnv({
      OIDC_ISSUER_URL: 'https://id.example.com/realms/duka',
      KEYCLOAK_ADMIN_CLIENT_ID: 'duka-admin',
      KEYCLOAK_ADMIN_CLIENT_SECRET: 'secret',
    });
    expect(options).toMatchObject({ baseUrl: 'https://id.example.com', realm: 'duka' });
  });

  it('honours explicit overrides', () => {
    const options = keycloakAdminOptionsFromEnv({
      OIDC_ISSUER_URL: 'https://id.example.com/realms/duka',
      KEYCLOAK_BASE_URL: 'https://keycloak.internal',
      KEYCLOAK_REALM: 'shops',
      KEYCLOAK_ADMIN_CLIENT_ID: 'duka-admin',
      KEYCLOAK_ADMIN_CLIENT_SECRET: 'secret',
    });
    expect(options).toMatchObject({ baseUrl: 'https://keycloak.internal', realm: 'shops' });
  });

  it('is absent without the admin credentials, so nobody links an app by accident', () => {
    expect(keycloakAdminOptionsFromEnv({ OIDC_ISSUER_URL: 'https://id.example.com/realms/duka' })).toBeNull();
    expect(keycloakAdminOptionsFromEnv({})).toBeNull();
  });
});
