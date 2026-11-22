abstract final class SupportContact {
  static const String primaryNumber =
      String.fromEnvironment('WHATSAPP_CONTACT_NUMBER');
  static const String secondaryNumber =
      String.fromEnvironment('WHATSAPP_SECONDARY_CONTACT_NUMBER');

  static Uri? whatsappUri({
    required String message,
    String? fallbackUrl,
    String? phoneNumber,
  }) {
    final String configuredNumber = phoneNumber ?? primaryNumber;
    final String digits = configuredNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8 && digits.length <= 15) {
      return Uri.https('wa.me', '/$digits', <String, String>{'text': message});
    }

    if (phoneNumber != null) return null;

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
