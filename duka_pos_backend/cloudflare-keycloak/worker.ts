import { DurableObject } from 'cloudflare:workers';

type KeycloakEnv = {
  KEYCLOAK_CONTAINER: DurableObjectNamespace<KeycloakContainer>;
  KC_DB_URL: string; KC_DB_USERNAME: string; KC_DB_PASSWORD: string; KC_HOSTNAME: string;
  KEYCLOAK_ADMIN: string; KEYCLOAK_ADMIN_PASSWORD: string;
};

export class KeycloakContainer extends DurableObject<KeycloakEnv> {
  private starting?: Promise<void>;

  async fetch(request: Request): Promise<Response> {
    this.starting ??= this.startAndWaitForHealth().finally(() => { this.starting = undefined; });
    await this.starting;
    const url = new URL(request.url); url.protocol = 'http:'; url.host = 'container';
    const forwarded = new Request(url, request); forwarded.headers.delete('host');
    return this.ctx.container!.getTcpPort(8080).fetch(forwarded);
  }

  private async startAndWaitForHealth(): Promise<void> {
    const container = this.ctx.container!;
    if (!container.running) container.start({
      image: container.images.base, instance: 'standard-1', enableInternet: true,
      env: {
        KC_DB: 'postgres', KC_HEALTH_ENABLED: 'true', KC_METRICS_ENABLED: 'true', KC_HTTP_ENABLED: 'true',
        KC_HTTP_PORT: '8080', KC_PROXY_HEADERS: 'xforwarded', KC_DB_URL: this.env.KC_DB_URL,
        KC_DB_USERNAME: this.env.KC_DB_USERNAME, KC_DB_PASSWORD: this.env.KC_DB_PASSWORD,
        KC_HOSTNAME: this.env.KC_HOSTNAME, KEYCLOAK_ADMIN: this.env.KEYCLOAK_ADMIN,
        KEYCLOAK_ADMIN_PASSWORD: this.env.KEYCLOAK_ADMIN_PASSWORD,
      },
    });
    await container.setInactivityTimeout(30 * 60 * 1000);
    const port = container.getTcpPort(8080);
    for (let attempt = 0; attempt < 150; attempt += 1) {
      try { const response = await port.fetch('http://container/health/ready', { signal: AbortSignal.timeout(1000) }); await response.body?.cancel(); if (response.ok) return; } catch {}
      await scheduler.wait(500);
    }
    throw new Error('Keycloak container did not become ready on port 8080');
  }
}

export default { fetch(request: Request, env: KeycloakEnv): Promise<Response> { return env.KEYCLOAK_CONTAINER.getByName('shared-keycloak').fetch(request); } };
