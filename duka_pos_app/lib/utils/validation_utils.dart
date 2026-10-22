// Field validation, and the two confirmations a form has to stop and ask about.
//
// Every message here is now an ICU string in `lib/l10n/app_en.arb`, and every
// method takes an [AppLocalizations] rather than reaching for a global. That is
// deliberate on both counts:
//
//   * A global lookup would be a lookup at the wrong moment. `TextFormField`'s
//     `validator` runs inside `Form.validate()`, which can happen during a
//     build-adjacent phase, and a `Localizations` read from a non-widget context
//     either asserts or — worse, with a cached instance — silently renders the
//     previous locale's text into a form the user is looking at.
//   * Word order is not English. "Sell price is required" and "Sell price must be
//     a valid number" have to be able to reorder, which is why the field NAME is
//     an ICU placeholder rather than spliced in with `'$fieldName is required'`.
//
// The regexes stay as they are on purpose: they are the shipped rules, and
// tightening a validation is a behaviour change, not a localization task.

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';

abstract final class ValidationUtils {
  const ValidationUtils._();

  static String? validateProductName(AppLocalizations l10n, String? value) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validationProductNameRequired;
    }
    if (value.trim().length < 2) {
      return l10n.validationProductNameTooShort;
    }
    return null;
  }

  static String? validatePrice(
    AppLocalizations l10n,
    String? value,
    String fieldName,
  ) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validationFieldRequired(fieldName);
    }
    final price = double.tryParse(value.replaceAll(',', ''));
    if (price == null) {
      return l10n.validationFieldNotANumber(fieldName);
    }
    if (price < 0) {
      return l10n.validationFieldNotNegative(fieldName);
    }
    return null;
  }

  static String? validateStock(AppLocalizations l10n, String? value) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validationStockRequired;
    }
    final stock = int.tryParse(value.replaceAll(',', ''));
    if (stock == null) {
      return l10n.validationStockNotWhole;
    }
    if (stock < 0) {
      return l10n.validationStockNotNegative;
    }
    return null;
  }

  /// Validates a PIN against the length the ROLE requires.
  ///
  /// The length is a parameter because the two roles have different PINs —
  /// four digits for staff, six for the owner — and a validator that hardcodes
  /// one of them is how an admin ends up unable to delete their own account.
  /// The default is the STAFF length, which is what a form collecting a new
  /// staff PIN needs; an owner form passes `PinRules.adminLength`.
  static String? validatePIN(
    AppLocalizations l10n,
    String? value, {
    int length = 4,
  }) {
    if (value == null || value.isEmpty) {
      return l10n.validationPinRequired;
    }
    if (!RegExp(r'^\d+$').hasMatch(value) || value.length != length) {
      return length == 6
          ? l10n.validationPinNotSixDigits
          : l10n.validationPinNotFourDigits;
    }
    return null;
  }

  static String? validateEmail(AppLocalizations l10n, String? value) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validationEmailRequired;
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return l10n.validationEmailInvalid;
    }
    return null;
  }

  static String? validatePassword(AppLocalizations l10n, String? value) {
    if (value == null || value.isEmpty) {
      return l10n.validationPasswordRequired;
    }
    if (value.length < 6) {
      return l10n.validationPasswordTooShort;
    }
    return null;
  }

  static String? validatePhone(AppLocalizations l10n, String? value) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validationPhoneRequired;
    }
    final phone = value.replaceAll(RegExp(r'[^\d]'), '');
    if (phone.length < 9 || phone.length > 12) {
      return l10n.validationPhoneInvalid;
    }
    return null;
  }

  static String? validateChannelId(AppLocalizations l10n, String? value) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validationChannelIdRequired;
    }
    final id = int.tryParse(value.trim());
    if (id == null) {
      return l10n.validationChannelIdNotANumber;
    }
    return null;
  }

  /// Asks whether to sell below cost.
  ///
  /// True when confirmed, false when declined OR dismissed. The two are collapsed
  /// here on purpose: this confirmation has no side effect before it resolves, so
  /// "backed out" and "said no" are the same honest answer, and returning null
  /// would push a third state onto every call site.
  static Future<bool> showPriceWarning(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.validationLowPriceTitle),
        content: Text(l10n.validationLowPriceMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            // The verb plus the consequence. "Continue" beside a loss warning is
            // the button somebody taps without reading the paragraph.
            child: Text(l10n.validationLowPriceConfirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Asks whether to create a product whose name is already taken.
  static Future<bool> checkDuplicateName(
    BuildContext context,
    String name,
    List<String> existingNames,
  ) async {
    if (!existingNames.contains(name.toLowerCase())) return true;

    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.validationDuplicateNameTitle),
        content: Text(l10n.validationDuplicateNameMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.validationDuplicateNameConfirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// A [ProductProblem] as a sentence the owner reads, in their language.
  ///
  /// [Product.validate] answers with a code because the model layer cannot
  /// reach `AppLocalizations`; this is where that code becomes text. Kept here
  /// rather than at each call site so the product editor, the imports screen
  /// and any future writer show the same words for the same broken rule.
  static String productProblem(
    AppLocalizations l10n,
    ProductProblem problem,
  ) {
    switch (problem) {
      case ProductProblem.name:
        return l10n.validationProductNameRequired;
      case ProductProblem.nameTooLong:
        return l10n.validationProductNameTooLong(Product.maxNameLength);
      case ProductProblem.categoryTooLong:
        return l10n.validationProductCategoryTooLong(Product.maxCategoryLength);
      case ProductProblem.costPrice:
        return l10n.validationProductCostPrice;
      case ProductProblem.sellPrice:
        return l10n.validationProductSellPrice;
      case ProductProblem.stockQty:
        return l10n.validationProductStock;
      case ProductProblem.reorderLevel:
        return l10n.validationProductReorderLevel;
      case ProductProblem.size:
        return l10n.validationProductSize(
            Product.minBottleMl, Product.maxBottleMl);
      case ProductProblem.halfPrice:
        return l10n.validationProductHalfPrice;
      case ProductProblem.quarterPrice:
        return l10n.validationProductQuarterPrice;
    }
  }
}
