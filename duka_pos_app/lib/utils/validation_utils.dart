import 'package:flutter/material.dart';

class ValidationUtils {
  /// Validate product form inputs
  static String? validateProductName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Product name is required';
    }
    if (value.trim().length < 2) {
      return 'Product name must be at least 2 characters';
    }
    return null;
  }

  static String? validatePrice(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    final price = double.tryParse(value.replaceAll(',', ''));
    if (price == null) {
      return '$fieldName must be a valid number';
    }
    if (price < 0) {
      return '$fieldName cannot be negative';
    }
    return null;
  }

  static String? validateStock(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Stock quantity is required';
    }
    final stock = int.tryParse(value.replaceAll(',', ''));
    if (stock == null) {
      return 'Stock must be a whole number';
    }
    if (stock < 0) {
      return 'Stock cannot be negative';
    }
    return null;
  }

  static String? validatePIN(String? value) {
    if (value == null || value.isEmpty) {
      return 'PIN is required';
    }
    if (!RegExp(r'^\d{4}$').hasMatch(value)) {
      return 'PIN must be exactly 4 digits';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final phone = value.replaceAll(RegExp(r'[^\d]'), '');
    if (phone.length < 9 || phone.length > 12) {
      return 'Enter a valid phone number (9-12 digits)';
    }
    return null;
  }

  static String? validateChannelId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Channel ID is required';
    }
    final id = int.tryParse(value.trim());
    if (id == null) {
      return 'Channel ID must be a number';
    }
    return null;
  }

  /// Show warning dialog for sell price below cost
  static Future<bool> showPriceWarning(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Warning: Low Price'),
        content: const Text(
            'Sell price is below cost price. This sale will result in a loss. Continue anyway?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Check for duplicate product name
  static Future<bool> checkDuplicateName(
    BuildContext context,
    String name,
    List<String> existingNames,
  ) async {
    if (existingNames.contains(name.toLowerCase())) {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Duplicate Product Name'),
          content: const Text(
              'A product with this name already exists. Create anyway?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      return result ?? false;
    }
    return true;
  }
}
