import { DurableObject } from 'cloudflare:workers';

type BackendEnv = {
  BACKEND_CONTAINER: DurableObjectNamespace<BackendContainer>;
  DATABASE_URL: string; OIDC_ISSUER_URL: string; OIDC_AUDIENCE: string; OIDC_JWKS_URI: string;
  FRONTEND_URL?: string; PUBLIC_API_URL: string; PAYHERO_AUTH_TOKEN: string; PAYHERO_ACCOUNT_ID: string;
  MPESA_CALLBACK_KEY: string; SYSTEM_ADMIN_SUBJECTS: string; R2_ENDPOINT: string; R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string; R2_BUCKET_NAME: string; R2_PUBLIC_URL: string;
  TAX_ENTITY_ENCRYPTION_KEY: string; TAX_REPORTING_ACTIVATED: string; RISITI_BASE_URL: string; RISITI_API_KEY: string;
  APP_VERSION_NAME: string; APP_VERSION_CODE: string; APP_DOWNLOAD_URL: string; APP_UPDATE_REQUIRED: string;
  APP_RELEASE_NOTES: string; APP_RELEASE_REPOSITORY?: string;
};

export class BackendContainer extends DurableObject<BackendEnv> {
  private starting?: Promise<void>;

  async fetch(request: Request): Promise<Response> {
    this.starting ??= this.startAndWaitForHealth().finally(() => { this.starting = undefined; });
    await this.starting;
    const url = new URL(request.url); url.protocol = 'http:'; url.host = 'container';
    const forwarded = new Request(url, request); forwarded.headers.delete('host');
    return this.ctx.container!.getTcpPort(3000).fetch(forwarded);
  }

  private async startAndWaitForHealth(): Promise<void> {
    const container = this.ctx.container!;
    if (!container.running) container.start({
      image: container.images.base, instance: 'standard-1', enableInternet: true,
      env: {
        NODE_ENV: 'production', PORT: '3000', DATABASE_URL: this.env.DATABASE_URL,
        OIDC_ISSUER_URL: this.env.OIDC_ISSUER_URL, OIDC_AUDIENCE: this.env.OIDC_AUDIENCE,
        OIDC_JWKS_URI: this.env.OIDC_JWKS_URI, ...(this.env.FRONTEND_URL ? { FRONTEND_URL: this.env.FRONTEND_URL } : {}),
        PUBLIC_API_URL: this.env.PUBLIC_API_URL, PAYHERO_AUTH_TOKEN: this.env.PAYHERO_AUTH_TOKEN,
        PAYHERO_ACCOUNT_ID: this.env.PAYHERO_ACCOUNT_ID, MPESA_CALLBACK_KEY: this.env.MPESA_CALLBACK_KEY,
        SYSTEM_ADMIN_SUBJECTS: this.env.SYSTEM_ADMIN_SUBJECTS, R2_ENDPOINT: this.env.R2_ENDPOINT,
        R2_ACCESS_KEY_ID: this.env.R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY: this.env.R2_SECRET_ACCESS_KEY,
        R2_BUCKET_NAME: this.env.R2_BUCKET_NAME, R2_PUBLIC_URL: this.env.R2_PUBLIC_URL,
        TAX_ENTITY_ENCRYPTION_KEY: this.env.TAX_ENTITY_ENCRYPTION_KEY,
        TAX_REPORTING_ACTIVATED: this.env.TAX_REPORTING_ACTIVATED, RISITI_BASE_URL: this.env.RISITI_BASE_URL,
        RISITI_API_KEY: this.env.RISITI_API_KEY, APP_VERSION_NAME: this.env.APP_VERSION_NAME,
        APP_VERSION_CODE: this.env.APP_VERSION_CODE, APP_DOWNLOAD_URL: this.env.APP_DOWNLOAD_URL,
        APP_UPDATE_REQUIRED: this.env.APP_UPDATE_REQUIRED, APP_RELEASE_NOTES: this.env.APP_RELEASE_NOTES,
        ...(this.env.APP_RELEASE_REPOSITORY ? { APP_RELEASE_REPOSITORY: this.env.APP_RELEASE_REPOSITORY } : {}),
      },
    });
    await container.setInactivityTimeout(10 * 60 * 1000);
    const port = container.getTcpPort(3000);
    for (let attempt = 0; attempt < 100; attempt += 1) {
      try { const response = await port.fetch('http://container/health', { signal: AbortSignal.timeout(1000) }); await response.body?.cancel(); if (response.ok) return; } catch {}
      await scheduler.wait(200);
    }
    throw new Error('Backend container did not become healthy on port 3000');
  }
}

export default { fetch(request: Request, env: BackendEnv): Promise<Response> { return env.BACKEND_CONTAINER.getByName('backend').fetch(request); } };
