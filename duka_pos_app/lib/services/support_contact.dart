abstract final class SupportContact {
  static const String _configuredNumber =
      String.fromEnvironment('WHATSAPP_CONTACT_NUMBER');

  static Uri? whatsappUri({
    required String message,
    String? fallbackUrl,
  }) {
    final String digits = _configuredNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8 && digits.length <= 15) {
      return Uri.https('wa.me', '/$digits', <String, String>{'text': message});
    }

    final Uri? fallback =
        fallbackUrl == null ? null : Uri.tryParse(fallbackUrl);
    if (fallback == null ||
        fallback.scheme != 'https' ||
        fallback.host != 'wa.me' ||
        fallback.pathSegments.length != 1 ||
        !RegExp(r'^\d{8,15}$').hasMatch(fallback.pathSegments.single)) {
      return null;
    }
    final Map<String, String> parameters =
        Map<String, String>.from(fallback.queryParameters);
    parameters.putIfAbsent('text', () => message);
    return fallback.replace(queryParameters: parameters);
  }
}
