import { Container } from '@cloudflare/containers';

type BackendEnv = {
  BACKEND_CONTAINER: DurableObjectNamespace<BackendContainer>;
  DATABASE_URL: string;
  OIDC_ISSUER_URL: string;
  OIDC_AUDIENCE: string;
  OIDC_JWKS_URI: string;
  FRONTEND_URL: string;
  PUBLIC_API_URL: string;
  PAYHERO_AUTH_TOKEN: string;
  PAYHERO_ACCOUNT_ID: string;
  MPESA_CALLBACK_KEY: string;
  SYSTEM_ADMIN_SUBJECTS: string;
  R2_ENDPOINT: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  R2_BUCKET_NAME: string;
  R2_PUBLIC_URL: string;
  TAX_ENTITY_ENCRYPTION_KEY: string;
  TAX_REPORTING_ACTIVATED: string;
  RISITI_BASE_URL: string;
  RISITI_API_KEY: string;
  APP_VERSION_NAME: string;
  APP_VERSION_CODE: string;
  APP_DOWNLOAD_URL: string;
  APP_UPDATE_REQUIRED: string;
  APP_RELEASE_NOTES: string;
};

export class BackendContainer extends Container<BackendEnv> {
  defaultPort = 3000;
  sleepAfter = '10m';
  enableInternet = true;

  envVars = {
    NODE_ENV: 'production',
    PORT: '3000',
  };

  constructor(ctx: DurableObjectState, env: BackendEnv) {
    super(ctx, env);
    this.envVars = {
      ...this.envVars,
      DATABASE_URL: env.DATABASE_URL,
      OIDC_ISSUER_URL: env.OIDC_ISSUER_URL,
      OIDC_AUDIENCE: env.OIDC_AUDIENCE,
      OIDC_JWKS_URI: env.OIDC_JWKS_URI,
      FRONTEND_URL: env.FRONTEND_URL,
      PUBLIC_API_URL: env.PUBLIC_API_URL,
      PAYHERO_AUTH_TOKEN: env.PAYHERO_AUTH_TOKEN,
      PAYHERO_ACCOUNT_ID: env.PAYHERO_ACCOUNT_ID,
      MPESA_CALLBACK_KEY: env.MPESA_CALLBACK_KEY,
      SYSTEM_ADMIN_SUBJECTS: env.SYSTEM_ADMIN_SUBJECTS,
      R2_ENDPOINT: env.R2_ENDPOINT,
      R2_ACCESS_KEY_ID: env.R2_ACCESS_KEY_ID,
      R2_SECRET_ACCESS_KEY: env.R2_SECRET_ACCESS_KEY,
      R2_BUCKET_NAME: env.R2_BUCKET_NAME,
      R2_PUBLIC_URL: env.R2_PUBLIC_URL,
      TAX_ENTITY_ENCRYPTION_KEY: env.TAX_ENTITY_ENCRYPTION_KEY,
      TAX_REPORTING_ACTIVATED: env.TAX_REPORTING_ACTIVATED,
      RISITI_BASE_URL: env.RISITI_BASE_URL,
      RISITI_API_KEY: env.RISITI_API_KEY,
      APP_VERSION_NAME: env.APP_VERSION_NAME,
      APP_VERSION_CODE: env.APP_VERSION_CODE,
      APP_DOWNLOAD_URL: env.APP_DOWNLOAD_URL,
      APP_UPDATE_REQUIRED: env.APP_UPDATE_REQUIRED,
      APP_RELEASE_NOTES: env.APP_RELEASE_NOTES,
    };
  }
}

export default {
  fetch(request: Request, env: BackendEnv): Promise<Response> {
    return env.BACKEND_CONTAINER.getByName('backend').fetch(request);
  },
};
