import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ErrorUtils {
  /// Convert technical errors to user-friendly messages
  static String userMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    // Database errors
    if (errorStr.contains('sqlite') || errorStr.contains('database')) {
      if (errorStr.contains('unique constraint')) {
        return 'This name already exists - try a different one';
      }
      if (errorStr.contains('not null')) {
        return 'Please fill in all required fields';
      }
      return 'Could not save - try again. If this keeps happening, contact support.';
    }

    // Network errors
    if (errorStr.contains('socketexception') ||
        errorStr.contains('connection')) {
      return 'No internet connection - check your network and try again';
    }

    if (errorStr.contains('timeout')) {
      return 'Connection timed out - try again when you have better signal';
    }

    // Auth errors
    if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
      return 'Session expired - please login again';
    }

    if (errorStr.contains('403') || errorStr.contains('forbidden')) {
      return 'You don\'t have permission to do this';
    }

    // Payment errors
    if (errorStr.contains('payhero') || errorStr.contains('mpesa')) {
      return 'Payment failed - customer may have cancelled or insufficient funds';
    }

    // Stock errors
    if (errorStr.contains('stock') || errorStr.contains('inventory')) {
      return 'Not enough stock to complete this sale';
    }

    // Generic fallback
    return 'Something went wrong - try again. Contact support if this keeps happening.';
  }

  /// Show error snackbar
  static void showError(BuildContext context, dynamic error) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(userMessage(error)),
        backgroundColor: DukaColors.danger,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  /// Show success message
  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: DukaColors.success,
      ),
    );
  }
}
