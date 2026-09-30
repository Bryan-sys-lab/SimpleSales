/// Compile-time environment configuration.
///
/// Example release build:
/// ```bash
/// flutter build apk --release \
///   --dart-define=OIDC_ISSUER_URL=https://id.example.com/realms/duka \
///   --dart-define=OIDC_CLIENT_ID=duka-pos-mobile \
///   --dart-define=OIDC_REDIRECT_URL=dukapos://callback \
///   --dart-define=BACKEND_URL=https://your-api.com/api
/// ```
class Env {
  static const oidcIssuerUrl = String.fromEnvironment(
    'OIDC_ISSUER_URL',
    defaultValue: 'https://id.example.com/realms/duka',
  );
  static const oidcClientId = String.fromEnvironment(
    'OIDC_CLIENT_ID',
    defaultValue: 'duka-pos-mobile',
  );
  static const oidcRedirectUrl = String.fromEnvironment(
    'OIDC_REDIRECT_URL',
    defaultValue: 'dukapos://callback',
  );
  static const backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000/api',
  );
  static const sentryDsn =
      String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  static const githubRepo = String.fromEnvironment('GITHUB_REPO',
      defaultValue: 'your-username/duka-pos');

  static bool get oidcConfigured =>
      oidcIssuerUrl != 'https://id.example.com/realms/duka' &&
      oidcClientId.isNotEmpty;
  static bool get backendConfigured =>
      backendUrl != 'http://localhost:3000/api';
  static bool get sentryConfigured => sentryDsn.isNotEmpty;
  static bool get isConfigured => oidcConfigured && backendConfigured;

  static Map<String, bool> get status => {
        'oidc': oidcConfigured,
        'backend': backendConfigured,
        'sentry': sentryConfigured,
        'all': isConfigured,
      };
}
