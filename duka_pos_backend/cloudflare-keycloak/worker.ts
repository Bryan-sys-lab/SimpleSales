import { Container } from '@cloudflare/containers';

type KeycloakEnv = {
  KEYCLOAK_CONTAINER: DurableObjectNamespace<KeycloakContainer>;
  KC_DB_URL: string;
  KC_DB_USERNAME: string;
  KC_DB_PASSWORD: string;
  KC_HOSTNAME: string;
  KEYCLOAK_ADMIN: string;
  KEYCLOAK_ADMIN_PASSWORD: string;
};

export class KeycloakContainer extends Container<KeycloakEnv> {
  defaultPort = 8080;
  sleepAfter = '30m';
  enableInternet = true;

  envVars = {
    KC_DB: 'postgres',
    KC_HEALTH_ENABLED: 'true',
    KC_METRICS_ENABLED: 'true',
    KC_HTTP_ENABLED: 'true',
    KC_HTTP_PORT: '8080',
    KC_PROXY_HEADERS: 'xforwarded',
  };

  constructor(ctx: DurableObjectState, env: KeycloakEnv) {
    super(ctx, env);
    this.envVars = {
      ...this.envVars,
      KC_DB_URL: env.KC_DB_URL,
      KC_DB_USERNAME: env.KC_DB_USERNAME,
      KC_DB_PASSWORD: env.KC_DB_PASSWORD,
      KC_HOSTNAME: env.KC_HOSTNAME,
      KEYCLOAK_ADMIN: env.KEYCLOAK_ADMIN,
      KEYCLOAK_ADMIN_PASSWORD: env.KEYCLOAK_ADMIN_PASSWORD,
    };
  }
}

export default {
  fetch(request: Request, env: KeycloakEnv): Promise<Response> {
    return env.KEYCLOAK_CONTAINER.getByName('shared-keycloak').fetch(request);
  },
};
