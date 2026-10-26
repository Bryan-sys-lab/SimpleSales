import 'package:flutter/material.dart';

/// Collects an optional destination without retaining the raw phone or email.
Future<String?> askReceiptRecipient(BuildContext context) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Receipt recipient'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.emailAddress,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Phone or email (optional)',
          hintText: 'Leave empty to share without saving a recipient',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  controller.dispose();
  return maskReceiptRecipient(value);
}

String? maskReceiptRecipient(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  if (value.contains('@')) {
    final parts = value.split('@');
    if (parts.length != 2 || parts[1].isEmpty) return '••••';
    final local = parts[0];
    return '${local.isEmpty ? '' : local.substring(0, 1)}••••@${parts[1]}';
  }
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 4) return '••••${digits.substring(digits.length - 4)}';
  return '••••';
}
