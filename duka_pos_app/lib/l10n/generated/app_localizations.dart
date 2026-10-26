import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_sw.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('sw')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'SimpleSales'**
  String get appName;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndo;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get actionRefresh;

  /// No description provided for @actionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionConfirm;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionPressBackAgainToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get actionPressBackAgainToExit;

  /// No description provided for @errorDuplicateName.
  ///
  /// In en, this message translates to:
  /// **'That name is already taken. Try a different one.'**
  String get errorDuplicateName;

  /// No description provided for @errorMissingField.
  ///
  /// In en, this message translates to:
  /// **'Fill in every required field.'**
  String get errorMissingField;

  /// No description provided for @errorWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save. Try again; if it keeps happening, contact support.'**
  String get errorWriteFailed;

  /// No description provided for @errorOffline.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Check the network and try again.'**
  String get errorOffline;

  /// No description provided for @errorTimedOut.
  ///
  /// In en, this message translates to:
  /// **'The connection timed out. Try again when the signal is better.'**
  String get errorTimedOut;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Sign in again.'**
  String get errorSessionExpired;

  /// No description provided for @errorNotPermitted.
  ///
  /// In en, this message translates to:
  /// **'Your role does not allow that. Ask the owner for access.'**
  String get errorNotPermitted;

  /// No description provided for @errorPaymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed. The customer may have cancelled, or funds were insufficient.'**
  String get errorPaymentFailed;

  /// No description provided for @errorInsufficientStock.
  ///
  /// In en, this message translates to:
  /// **'Not enough stock to complete this sale.'**
  String get errorInsufficientStock;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again; if it keeps happening, contact support.'**
  String get errorUnknown;

  /// No description provided for @validationProductNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Product name is required'**
  String get validationProductNameRequired;

  /// No description provided for @validationProductNameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Product name must be at least 2 characters'**
  String get validationProductNameTooShort;

  /// No description provided for @validationFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'{field} is required'**
  String validationFieldRequired(Object field);

  /// No description provided for @validationFieldNotANumber.
  ///
  /// In en, this message translates to:
  /// **'{field} must be a valid number'**
  String validationFieldNotANumber(Object field);

  /// No description provided for @validationFieldNotNegative.
  ///
  /// In en, this message translates to:
  /// **'{field} cannot be negative'**
  String validationFieldNotNegative(Object field);

  /// No description provided for @validationProductNameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Product name must be {max} characters or fewer'**
  String validationProductNameTooLong(Object max);

  /// No description provided for @validationProductCategoryTooLong.
  ///
  /// In en, this message translates to:
  /// **'Category must be {max} characters or fewer'**
  String validationProductCategoryTooLong(Object max);

  /// No description provided for @validationProductCostPrice.
  ///
  /// In en, this message translates to:
  /// **'Cost price must be a valid amount of 0 or more'**
  String get validationProductCostPrice;

  /// No description provided for @validationProductSellPrice.
  ///
  /// In en, this message translates to:
  /// **'Selling price must be a valid amount of 0 or more'**
  String get validationProductSellPrice;

  /// No description provided for @validationProductStock.
  ///
  /// In en, this message translates to:
  /// **'Stock quantity must be 0 or more'**
  String get validationProductStock;

  /// No description provided for @validationProductReorderLevel.
  ///
  /// In en, this message translates to:
  /// **'Reorder level must be 0 or more'**
  String get validationProductReorderLevel;

  /// No description provided for @validationProductSize.
  ///
  /// In en, this message translates to:
  /// **'Size must be between {min} and {max} ml (a 50-litre keg is 50000)'**
  String validationProductSize(Object max, Object min);

  /// No description provided for @validationProductHalfPrice.
  ///
  /// In en, this message translates to:
  /// **'Half price must be a valid amount of 0 or more'**
  String get validationProductHalfPrice;

  /// No description provided for @validationProductQuarterPrice.
  ///
  /// In en, this message translates to:
  /// **'Quarter price must be a valid amount of 0 or more'**
  String get validationProductQuarterPrice;

  /// No description provided for @validationStockRequired.
  ///
  /// In en, this message translates to:
  /// **'Stock quantity is required'**
  String get validationStockRequired;

  /// No description provided for @validationStockNotWhole.
  ///
  /// In en, this message translates to:
  /// **'Stock must be a whole number'**
  String get validationStockNotWhole;

  /// No description provided for @validationStockNotNegative.
  ///
  /// In en, this message translates to:
  /// **'Stock cannot be negative'**
  String get validationStockNotNegative;

  /// No description provided for @validationPinRequired.
  ///
  /// In en, this message translates to:
  /// **'PIN is required'**
  String get validationPinRequired;

  /// No description provided for @validationPinNotFourDigits.
  ///
  /// In en, this message translates to:
  /// **'PIN must be exactly 4 digits'**
  String get validationPinNotFourDigits;

  /// No description provided for @validationPinNotSixDigits.
  ///
  /// In en, this message translates to:
  /// **'PIN must be exactly 6 digits'**
  String get validationPinNotSixDigits;

  /// No description provided for @validationPinConfirmRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the PIN again'**
  String get validationPinConfirmRequired;

  /// No description provided for @validationPinMismatch.
  ///
  /// In en, this message translates to:
  /// **'PINs do not match'**
  String get validationPinMismatch;

  /// No description provided for @ownerSetupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Your name (shop admin)'**
  String get ownerSetupNameLabel;

  /// No description provided for @ownerSetupEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Owner email'**
  String get ownerSetupEmailLabel;

  /// No description provided for @ownerSetupPinLabel.
  ///
  /// In en, this message translates to:
  /// **'Set a 6-digit PIN'**
  String get ownerSetupPinLabel;

  /// No description provided for @ownerSetupPinConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get ownerSetupPinConfirmLabel;

  /// No description provided for @ownerSetupMissingDetails.
  ///
  /// In en, this message translates to:
  /// **'Enter your name, email, and shop name'**
  String get ownerSetupMissingDetails;

  /// No description provided for @ownerSetupInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get ownerSetupInvalidEmail;

  /// No description provided for @shopProfileLabel.
  ///
  /// In en, this message translates to:
  /// **'Business profile'**
  String get shopProfileLabel;

  /// No description provided for @shopProfileHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose this shop\'s profile once. You can change it later.'**
  String get shopProfileHelp;

  /// No description provided for @validationEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get validationEmailRequired;

  /// No description provided for @validationEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get validationEmailInvalid;

  /// No description provided for @validationPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get validationPasswordRequired;

  /// No description provided for @validationPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get validationPasswordTooShort;

  /// No description provided for @validationPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get validationPhoneRequired;

  /// No description provided for @validationPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number (9 to 12 digits)'**
  String get validationPhoneInvalid;

  /// No description provided for @validationChannelIdRequired.
  ///
  /// In en, this message translates to:
  /// **'Channel ID is required'**
  String get validationChannelIdRequired;

  /// No description provided for @validationChannelIdNotANumber.
  ///
  /// In en, this message translates to:
  /// **'Channel ID must be a number'**
  String get validationChannelIdNotANumber;

  /// No description provided for @validationLowPriceTitle.
  ///
  /// In en, this message translates to:
  /// **'Warning: low price'**
  String get validationLowPriceTitle;

  /// No description provided for @validationLowPriceMessage.
  ///
  /// In en, this message translates to:
  /// **'Sell price is below cost price. This sale will result in a loss. Continue anyway?'**
  String get validationLowPriceMessage;

  /// No description provided for @validationLowPriceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sell below cost'**
  String get validationLowPriceConfirm;

  /// No description provided for @validationDuplicateNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Duplicate product name'**
  String get validationDuplicateNameTitle;

  /// No description provided for @validationDuplicateNameMessage.
  ///
  /// In en, this message translates to:
  /// **'A product with this name already exists. Create anyway?'**
  String get validationDuplicateNameMessage;

  /// No description provided for @validationDuplicateNameConfirm.
  ///
  /// In en, this message translates to:
  /// **'Create it anyway'**
  String get validationDuplicateNameConfirm;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @poweredBy.
  ///
  /// In en, this message translates to:
  /// **'Powered by'**
  String get poweredBy;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @shiftScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Shift & reconciliation'**
  String get shiftScreenTitle;

  /// No description provided for @shiftLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load this till\'s shifts'**
  String get shiftLoadFailedTitle;

  /// No description provided for @shiftLoadFailedDetail.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been recorded against this screen. Try again.'**
  String get shiftLoadFailedDetail;

  /// No description provided for @shiftBannerRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get shiftBannerRefresh;

  /// No description provided for @shiftNoShiftSection.
  ///
  /// In en, this message translates to:
  /// **'Your shift'**
  String get shiftNoShiftSection;

  /// No description provided for @shiftNoShiftTitle.
  ///
  /// In en, this message translates to:
  /// **'No shift open'**
  String get shiftNoShiftTitle;

  /// No description provided for @shiftNoShiftMessage.
  ///
  /// In en, this message translates to:
  /// **'Open a shift to count the cash you start and end the day with. Without one there is nothing to reconcile against.'**
  String get shiftNoShiftMessage;

  /// No description provided for @shiftNoShiftAction.
  ///
  /// In en, this message translates to:
  /// **'Open shift'**
  String get shiftNoShiftAction;

  /// No description provided for @shiftNoShiftNoRoster.
  ///
  /// In en, this message translates to:
  /// **'Sign in as someone on the staff roster to open a shift.'**
  String get shiftNoShiftNoRoster;

  /// No description provided for @shiftOpenSection.
  ///
  /// In en, this message translates to:
  /// **'Open shift'**
  String get shiftOpenSection;

  /// No description provided for @shiftOpenChip.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get shiftOpenChip;

  /// No description provided for @shiftStartedAt.
  ///
  /// In en, this message translates to:
  /// **'Started {when}'**
  String shiftStartedAt(Object when);

  /// No description provided for @shiftExpectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Expected in the drawer'**
  String get shiftExpectedLabel;

  /// No description provided for @shiftOpeningFloat.
  ///
  /// In en, this message translates to:
  /// **'Opening float'**
  String get shiftOpeningFloat;

  /// No description provided for @shiftCountAction.
  ///
  /// In en, this message translates to:
  /// **'Count the till'**
  String get shiftCountAction;

  /// No description provided for @shiftCloseAction.
  ///
  /// In en, this message translates to:
  /// **'Close and reconcile'**
  String get shiftCloseAction;

  /// No description provided for @shiftOpenCardSpoken.
  ///
  /// In en, this message translates to:
  /// **'Shift open for {name}, started {when}. Expected in the drawer {expected}. The drawer is {variance}.'**
  String shiftOpenCardSpoken(
      Object expected, Object name, Object variance, Object when);

  /// No description provided for @shiftRosterDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add {name} to the staff list?'**
  String shiftRosterDialogTitle(Object name);

  /// No description provided for @shiftRosterDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} signs in as the shop owner, and the owner is not on the staff roster. A shift is recorded against a staff entry so sales can be counted against it, so {name} needs a roster entry of their own. No PIN is set, so this cannot be signed in to on its own.'**
  String shiftRosterDialogMessage(Object name);

  /// No description provided for @shiftRosterDialogConfirm.
  ///
  /// In en, this message translates to:
  /// **'Add me to the roster'**
  String get shiftRosterDialogConfirm;

  /// No description provided for @shiftRosterDialogDecline.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get shiftRosterDialogDecline;

  /// No description provided for @shiftCountedSnack.
  ///
  /// In en, this message translates to:
  /// **'Counted {amount} in the drawer.'**
  String shiftCountedSnack(Object amount);

  /// No description provided for @shiftClosedBalanced.
  ///
  /// In en, this message translates to:
  /// **'Shift closed. The drawer balanced exactly.'**
  String get shiftClosedBalanced;

  /// No description provided for @shiftClosedShort.
  ///
  /// In en, this message translates to:
  /// **'Shift closed. {amount} short of the expected figure.'**
  String shiftClosedShort(Object amount);

  /// No description provided for @shiftClosedOver.
  ///
  /// In en, this message translates to:
  /// **'Shift closed. {amount} over the expected figure.'**
  String shiftClosedOver(Object amount);

  /// No description provided for @varianceBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get varianceBalanced;

  /// No description provided for @varianceBalancedSpoken.
  ///
  /// In en, this message translates to:
  /// **'balanced exactly, no difference'**
  String get varianceBalancedSpoken;

  /// No description provided for @varianceShort.
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get varianceShort;

  /// No description provided for @varianceShortSpoken.
  ///
  /// In en, this message translates to:
  /// **'{amount} short of the expected figure'**
  String varianceShortSpoken(Object amount);

  /// No description provided for @varianceOver.
  ///
  /// In en, this message translates to:
  /// **'Over'**
  String get varianceOver;

  /// No description provided for @varianceOverSpoken.
  ///
  /// In en, this message translates to:
  /// **'{amount} over the expected figure'**
  String varianceOverSpoken(Object amount);

  /// No description provided for @varianceNotCounted.
  ///
  /// In en, this message translates to:
  /// **'Not counted'**
  String get varianceNotCounted;

  /// No description provided for @varianceNotCountedSpoken.
  ///
  /// In en, this message translates to:
  /// **'the drawer has not been counted yet'**
  String get varianceNotCountedSpoken;

  /// No description provided for @varianceDifferenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Difference'**
  String get varianceDifferenceLabel;

  /// No description provided for @varianceShortByLabel.
  ///
  /// In en, this message translates to:
  /// **'Short by'**
  String get varianceShortByLabel;

  /// No description provided for @varianceOverByLabel.
  ///
  /// In en, this message translates to:
  /// **'Over by'**
  String get varianceOverByLabel;

  /// No description provided for @varianceStripSpoken.
  ///
  /// In en, this message translates to:
  /// **'Difference between counted and expected: {variance}'**
  String varianceStripSpoken(Object variance);

  /// No description provided for @shiftFloatAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount (KSh)'**
  String get shiftFloatAmountLabel;

  /// No description provided for @shiftFloatInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a number, 0 or more.'**
  String get shiftFloatInvalid;

  /// No description provided for @shiftCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Count the till'**
  String get shiftCountTitle;

  /// No description provided for @shiftCountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How many of each note and coin is in the drawer.'**
  String get shiftCountSubtitle;

  /// No description provided for @shiftCountPileLabel.
  ///
  /// In en, this message translates to:
  /// **'How many'**
  String get shiftCountPileLabel;

  /// No description provided for @shiftCountTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Counted so far'**
  String get shiftCountTotalLabel;

  /// No description provided for @shiftCountTotalSpoken.
  ///
  /// In en, this message translates to:
  /// **'Counted so far {amount}'**
  String shiftCountTotalSpoken(Object amount);

  /// No description provided for @shiftCountSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the count. Try again.'**
  String get shiftCountSaveFailed;

  /// No description provided for @shiftCloseTitle.
  ///
  /// In en, this message translates to:
  /// **'Close shift'**
  String get shiftCloseTitle;

  /// No description provided for @shiftCloseCashRungUp.
  ///
  /// In en, this message translates to:
  /// **'Cash rung up this shift'**
  String get shiftCloseCashRungUp;

  /// No description provided for @shiftCloseCountedLabel.
  ///
  /// In en, this message translates to:
  /// **'Counted in the drawer'**
  String get shiftCloseCountedLabel;

  /// No description provided for @shiftCloseCountedHelp.
  ///
  /// In en, this message translates to:
  /// **'Pre-filled from your count. Correct it if it changed.'**
  String get shiftCloseCountedHelp;

  /// No description provided for @shiftCloseNextFloatLabel.
  ///
  /// In en, this message translates to:
  /// **'Float for the next shift'**
  String get shiftCloseNextFloatLabel;

  /// No description provided for @shiftCloseNextFloatHelp.
  ///
  /// In en, this message translates to:
  /// **'What stays in the drawer'**
  String get shiftCloseNextFloatHelp;

  /// No description provided for @shiftCloseKeepCounting.
  ///
  /// In en, this message translates to:
  /// **'Keep counting'**
  String get shiftCloseKeepCounting;

  /// No description provided for @shiftCloseCommit.
  ///
  /// In en, this message translates to:
  /// **'Close and reconcile'**
  String get shiftCloseCommit;

  /// No description provided for @expensePayOutAction.
  ///
  /// In en, this message translates to:
  /// **'Pay out'**
  String get expensePayOutAction;

  /// No description provided for @expensePayOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Pay out from till'**
  String get expensePayOutTitle;

  /// No description provided for @expensePayOutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record money taken from the drawer.'**
  String get expensePayOutSubtitle;

  /// No description provided for @expenseAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount (KSh)'**
  String get expenseAmountLabel;

  /// No description provided for @expenseCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get expenseCategoryLabel;

  /// No description provided for @expenseNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get expenseNoteLabel;

  /// No description provided for @expenseSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Record payout'**
  String get expenseSaveAction;

  /// No description provided for @expenseHistoryAction.
  ///
  /// In en, this message translates to:
  /// **'Expense history'**
  String get expenseHistoryAction;

  /// No description provided for @expenseHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenseHistoryTitle;

  /// No description provided for @expenseHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No payouts recorded yet.'**
  String get expenseHistoryEmpty;

  /// No description provided for @expenseManagerOnly.
  ///
  /// In en, this message translates to:
  /// **'Only the owner or manager can view expenses.'**
  String get expenseManagerOnly;

  /// No description provided for @expenseHistoryTotal.
  ///
  /// In en, this message translates to:
  /// **'Total paid out'**
  String get expenseHistoryTotal;

  /// No description provided for @tillMovementAction.
  ///
  /// In en, this message translates to:
  /// **'Cash in/drop'**
  String get tillMovementAction;

  /// No description provided for @tillMovementTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash in or drop'**
  String get tillMovementTitle;

  /// No description provided for @tillMovementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record cash entering or leaving this drawer.'**
  String get tillMovementSubtitle;

  /// No description provided for @tillMovementTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Movement'**
  String get tillMovementTypeLabel;

  /// No description provided for @tillCashInAction.
  ///
  /// In en, this message translates to:
  /// **'Cash in'**
  String get tillCashInAction;

  /// No description provided for @tillCashDropAction.
  ///
  /// In en, this message translates to:
  /// **'Cash drop'**
  String get tillCashDropAction;

  /// No description provided for @tillMovementSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Record movement'**
  String get tillMovementSaveAction;

  /// No description provided for @shiftCloseCommitting.
  ///
  /// In en, this message translates to:
  /// **'Closing'**
  String get shiftCloseCommitting;

  /// No description provided for @shiftCloseCountedMissing.
  ///
  /// In en, this message translates to:
  /// **'Enter what is actually in the drawer.'**
  String get shiftCloseCountedMissing;

  /// No description provided for @shiftCloseFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t close the shift. Try again.'**
  String get shiftCloseFailed;

  /// No description provided for @shiftHistoryShiftCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 shift} other{{count} shifts}}'**
  String shiftHistoryShiftCount(num count);

  /// No description provided for @shiftHistoryOpener.
  ///
  /// In en, this message translates to:
  /// **'Opened with {amount}'**
  String shiftHistoryOpener(Object amount);

  /// No description provided for @shiftHistoryHiddenOne.
  ///
  /// In en, this message translates to:
  /// **'and 1 earlier shift not shown'**
  String get shiftHistoryHiddenOne;

  /// No description provided for @shiftHistoryHiddenMany.
  ///
  /// In en, this message translates to:
  /// **'and {count} earlier shifts not shown'**
  String shiftHistoryHiddenMany(Object count);

  /// No description provided for @shiftHistoryUnknownCashier.
  ///
  /// In en, this message translates to:
  /// **'Unknown cashier'**
  String get shiftHistoryUnknownCashier;

  /// No description provided for @shiftReconciliationsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 count} other{{count} counts}}'**
  String shiftReconciliationsCount(num count);

  /// No description provided for @shiftReconciliationsAllBalanced.
  ///
  /// In en, this message translates to:
  /// **'Every count on record balanced'**
  String get shiftReconciliationsAllBalanced;

  /// No description provided for @shiftReconciliationsDidNotBalance.
  ///
  /// In en, this message translates to:
  /// **'Did not balance'**
  String get shiftReconciliationsDidNotBalance;

  /// No description provided for @shiftReconciliationsAllBalancedChip.
  ///
  /// In en, this message translates to:
  /// **'All balanced'**
  String get shiftReconciliationsAllBalancedChip;

  /// No description provided for @shiftReconciliationsOutOfCount.
  ///
  /// In en, this message translates to:
  /// **'{bad} of {total}'**
  String shiftReconciliationsOutOfCount(Object bad, Object total);

  /// No description provided for @shiftReconciliationsNoneYet.
  ///
  /// In en, this message translates to:
  /// **'No drawer has been counted and reconciled yet.'**
  String get shiftReconciliationsNoneYet;

  /// No description provided for @shiftReconciliationsCountedOf.
  ///
  /// In en, this message translates to:
  /// **'Counted {counted} of {expected} expected'**
  String shiftReconciliationsCountedOf(Object counted, Object expected);

  /// No description provided for @shiftCountSave.
  ///
  /// In en, this message translates to:
  /// **'Save count'**
  String get shiftCountSave;

  /// No description provided for @shiftCountSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving the count'**
  String get shiftCountSaving;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navDashboardShort.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navDashboardShort;

  /// No description provided for @navSell.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get navSell;

  /// No description provided for @navSellShort.
  ///
  /// In en, this message translates to:
  /// **'Till'**
  String get navSellShort;

  /// No description provided for @navInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get navInventory;

  /// No description provided for @navInventoryShort.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get navInventoryShort;

  /// No description provided for @navAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get navAnalytics;

  /// No description provided for @navAnalyticsShort.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navAnalyticsShort;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navSettingsShort.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get navSettingsShort;

  /// No description provided for @navMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// No description provided for @navMoreShort.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMoreShort;

  /// No description provided for @navSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get navSupport;

  /// No description provided for @navSupportShort.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get navSupportShort;

  /// No description provided for @shellRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get shellRoleOwner;

  /// No description provided for @shellAccountMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Account and sign out'**
  String get shellAccountMenuLabel;

  /// No description provided for @shellCreditMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Credit customers'**
  String get shellCreditMenuLabel;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @notificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs your attention right now.'**
  String get notificationsEmpty;

  /// No description provided for @notificationsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Notifications are unavailable right now.'**
  String get notificationsLoadFailed;

  /// No description provided for @businessToolsMarketplace.
  ///
  /// In en, this message translates to:
  /// **'Business tools marketplace'**
  String get businessToolsMarketplace;

  /// No description provided for @marketplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Business tools'**
  String get marketplaceTitle;

  /// No description provided for @marketplaceIntro.
  ///
  /// In en, this message translates to:
  /// **'Make your shop more powerful'**
  String get marketplaceIntro;

  /// No description provided for @marketplaceDescription.
  ///
  /// In en, this message translates to:
  /// **'Connect trusted tools for intelligence, reporting, people, money and customers. Your POS data stays yours.'**
  String get marketplaceDescription;

  /// No description provided for @marketplaceComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get marketplaceComingSoon;

  /// No description provided for @marketplaceStamp.
  ///
  /// In en, this message translates to:
  /// **'COMING SOON'**
  String get marketplaceStamp;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @shellSignOutTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get shellSignOutTooltip;

  /// No description provided for @shellSignedInAs.
  ///
  /// In en, this message translates to:
  /// **'{title}, signed in as {role}'**
  String shellSignedInAs(Object role, Object title);

  /// No description provided for @notFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get notFoundTitle;

  /// No description provided for @notFoundHeading.
  ///
  /// In en, this message translates to:
  /// **'That link does not go anywhere'**
  String get notFoundHeading;

  /// No description provided for @notFoundBody.
  ///
  /// In en, this message translates to:
  /// **'It may be from an older version of the app.'**
  String get notFoundBody;

  /// No description provided for @notFoundPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Requested path: {path}'**
  String notFoundPathLabel(Object path);

  /// No description provided for @notFoundAction.
  ///
  /// In en, this message translates to:
  /// **'Back to the till'**
  String get notFoundAction;

  /// No description provided for @databaseErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'This app could not open its data'**
  String get databaseErrorTitle;

  /// No description provided for @databaseErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been changed or deleted, but the app cannot read your inventory or sales right now.'**
  String get databaseErrorBody;

  /// No description provided for @databaseErrorAdvice.
  ///
  /// In en, this message translates to:
  /// **'This usually follows a crash or a low-storage event. If you have a recent backup file, reinstalling the app and restoring that backup from Settings is the safest way forward.'**
  String get databaseErrorAdvice;

  /// No description provided for @databaseErrorRetryAction.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get databaseErrorRetryAction;

  /// No description provided for @databaseErrorShareAction.
  ///
  /// In en, this message translates to:
  /// **'Copy diagnostics'**
  String get databaseErrorShareAction;

  /// No description provided for @databaseErrorSharedMessage.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics copied. Send them to support.'**
  String get databaseErrorSharedMessage;

  /// No description provided for @configurationErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'This build is not configured'**
  String get configurationErrorTitle;

  /// No description provided for @configurationErrorBody.
  ///
  /// In en, this message translates to:
  /// **'The app cannot reach your shop\'s server, so it cannot issue KRA receipts, take M-Pesa payments or sync.'**
  String get configurationErrorBody;

  /// No description provided for @configurationNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'This build has no server address, so KRA receipts, M-Pesa payments and syncing will not work. Selling, stock and reports work as usual, on this phone.'**
  String get configurationNoticeBody;

  /// No description provided for @configurationErrorAdvice.
  ///
  /// In en, this message translates to:
  /// **'This is a problem with how the app was built, not with your data. Your sales, stock and settings are safe on this phone.'**
  String get configurationErrorAdvice;

  /// No description provided for @configurationErrorDetail.
  ///
  /// In en, this message translates to:
  /// **'Technical detail: {detail}'**
  String configurationErrorDetail(Object detail);

  /// No description provided for @configurationErrorShareAction.
  ///
  /// In en, this message translates to:
  /// **'Copy the details'**
  String get configurationErrorShareAction;

  /// No description provided for @configurationErrorSharedMessage.
  ///
  /// In en, this message translates to:
  /// **'Details copied. Send them to whoever builds your app releases.'**
  String get configurationErrorSharedMessage;

  /// No description provided for @databaseErrorRetryFailed.
  ///
  /// In en, this message translates to:
  /// **'Still cannot open the data. Free some storage, then try again.'**
  String get databaseErrorRetryFailed;

  /// No description provided for @sellBrowseProductsAction.
  ///
  /// In en, this message translates to:
  /// **'Browse products'**
  String get sellBrowseProductsAction;

  /// No description provided for @sellCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Sale recorded'**
  String get sellCompleteTitle;

  /// No description provided for @sellCompleteFactPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get sellCompleteFactPaid;

  /// No description provided for @sellCompleteFactChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get sellCompleteFactChange;

  /// No description provided for @sellCompleteFactTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get sellCompleteFactTotal;

  /// No description provided for @sellCompletePaidCash.
  ///
  /// In en, this message translates to:
  /// **'Paid in cash'**
  String get sellCompletePaidCash;

  /// No description provided for @sellCompletePaidMpesa.
  ///
  /// In en, this message translates to:
  /// **'Paid by M-Pesa'**
  String get sellCompletePaidMpesa;

  /// No description provided for @sellCompletePaidCard.
  ///
  /// In en, this message translates to:
  /// **'Paid by card'**
  String get sellCompletePaidCard;

  /// No description provided for @sellCompletePaidBank.
  ///
  /// In en, this message translates to:
  /// **'Paid by bank transfer'**
  String get sellCompletePaidBank;

  /// No description provided for @sellCompletePaidMobileMoney.
  ///
  /// In en, this message translates to:
  /// **'Paid by mobile money'**
  String get sellCompletePaidMobileMoney;

  /// No description provided for @sellCompletePaidOtherGeneric.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get sellCompletePaidOtherGeneric;

  /// No description provided for @sellCompletePaidOther.
  ///
  /// In en, this message translates to:
  /// **'{method} · {amount}'**
  String sellCompletePaidOther(Object amount, Object method);

  /// No description provided for @sellCompleteNext.
  ///
  /// In en, this message translates to:
  /// **'Next sale'**
  String get sellCompleteNext;

  /// No description provided for @sellCompleteReceiptPending.
  ///
  /// In en, this message translates to:
  /// **'The receipt is still printing.'**
  String get sellCompleteReceiptPending;

  /// No description provided for @sellCartEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap products to add'**
  String get sellCartEmptyHint;

  /// No description provided for @sellCartEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Tap a product to add it, or scan its barcode. Nothing is charged until you press Charge.'**
  String get sellCartEmptyMessage;

  /// No description provided for @sellCartEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'The cart is empty'**
  String get sellCartEmptyTitle;

  /// No description provided for @sellCartTitle.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get sellCartTitle;

  /// No description provided for @sellTileStockCount.
  ///
  /// In en, this message translates to:
  /// **'{quantity} in stock'**
  String sellTileStockCount(Object quantity);

  /// No description provided for @sellTileNoVariants.
  ///
  /// In en, this message translates to:
  /// **'No variants yet'**
  String get sellTileNoVariants;

  /// No description provided for @sellTileFromPrice.
  ///
  /// In en, this message translates to:
  /// **'From {price}'**
  String sellTileFromPrice(Object price);

  /// No description provided for @sellTileSpokenProduct.
  ///
  /// In en, this message translates to:
  /// **'{name}, {price}, {stock}'**
  String sellTileSpokenProduct(Object name, Object price, Object stock);

  /// No description provided for @sellTileSpokenVariants.
  ///
  /// In en, this message translates to:
  /// **'{name}, from {price}, {variants}, {stock}'**
  String sellTileSpokenVariants(
      Object name, Object price, Object stock, Object variants);

  /// No description provided for @sellTileHintAddsToCart.
  ///
  /// In en, this message translates to:
  /// **'Adds it to the cart'**
  String get sellTileHintAddsToCart;

  /// No description provided for @sellTileHintChoosesVariant.
  ///
  /// In en, this message translates to:
  /// **'Opens the variants'**
  String get sellTileHintChoosesVariant;

  /// No description provided for @sellTileCartCount.
  ///
  /// In en, this message translates to:
  /// **'{count} in the cart'**
  String sellTileCartCount(Object count);

  /// No description provided for @sellCatalogueEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Add products in Inventory and they can be sold here straight away.'**
  String get sellCatalogueEmptyMessage;

  /// No description provided for @sellCatalogueEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No products yet'**
  String get sellCatalogueEmptyTitle;

  /// No description provided for @sellCatalogueLoadFailedDetail.
  ///
  /// In en, this message translates to:
  /// **'Selling needs the catalogue. Nothing has been charged.'**
  String get sellCatalogueLoadFailedDetail;

  /// No description provided for @sellCatalogueLoadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'The product catalogue could not be read.'**
  String get sellCatalogueLoadFailedMessage;

  /// No description provided for @sellCategorySpoken.
  ///
  /// In en, this message translates to:
  /// **'{category}, {count, plural, =1{1 product} other{{count} products}}'**
  String sellCategorySpoken(Object category, num count);

  /// No description provided for @sellChargingAmount.
  ///
  /// In en, this message translates to:
  /// **'Charging {amount}…'**
  String sellChargingAmount(Object amount);

  /// No description provided for @sellCheckAgainAction.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get sellCheckAgainAction;

  /// No description provided for @sellCheckAgainLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get sellCheckAgainLater;

  /// No description provided for @sellCheckingPayment.
  ///
  /// In en, this message translates to:
  /// **'Checking payment {reference}…'**
  String sellCheckingPayment(Object reference);

  /// No description provided for @sellCheckPhoneForStk.
  ///
  /// In en, this message translates to:
  /// **'Check phone {phone} for STK push'**
  String sellCheckPhoneForStk(Object phone);

  /// No description provided for @sellChooseServingTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose serving · {product}'**
  String sellChooseServingTitle(Object product);

  /// No description provided for @sellClearFilterAction.
  ///
  /// In en, this message translates to:
  /// **'Clear the filter'**
  String get sellClearFilterAction;

  /// No description provided for @sellClearSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear product search'**
  String get sellClearSearchTooltip;

  /// No description provided for @sellCustomerNameOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer Name (optional)'**
  String get sellCustomerNameOptionalLabel;

  /// No description provided for @sellDecreaseItem.
  ///
  /// In en, this message translates to:
  /// **'Decrease {item}'**
  String sellDecreaseItem(Object item);

  /// No description provided for @sellDecreaseQuantityOf.
  ///
  /// In en, this message translates to:
  /// **'Decrease quantity of {item}'**
  String sellDecreaseQuantityOf(Object item);

  /// No description provided for @sellIncreaseItem.
  ///
  /// In en, this message translates to:
  /// **'Increase {item}'**
  String sellIncreaseItem(Object item);

  /// No description provided for @sellIncreaseQuantityOf.
  ///
  /// In en, this message translates to:
  /// **'Increase quantity of {item}'**
  String sellIncreaseQuantityOf(Object item);

  /// No description provided for @sellMpesaPaymentSuccessful.
  ///
  /// In en, this message translates to:
  /// **'M-Pesa payment successful. Sale recorded.'**
  String get sellMpesaPaymentSuccessful;

  /// No description provided for @sellMpesaPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'M-Pesa Payment'**
  String get sellMpesaPaymentTitle;

  /// No description provided for @sellNoMatchFilter.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches this filter'**
  String get sellNoMatchFilter;

  /// No description provided for @sellNoMatchInCategory.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches \"{query}\" in {category}'**
  String sellNoMatchInCategory(Object category, Object query);

  /// No description provided for @sellNoMatchMessage.
  ///
  /// In en, this message translates to:
  /// **'Try a shorter name, or clear the filter to see everything in the catalogue.'**
  String get sellNoMatchMessage;

  /// No description provided for @sellNoMatchQuery.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches \"{query}\"'**
  String sellNoMatchQuery(Object query);

  /// No description provided for @sellNoVariantsYetTitle.
  ///
  /// In en, this message translates to:
  /// **'{product} has no variants yet'**
  String sellNoVariantsYetTitle(Object product);

  /// No description provided for @sellNothingInCategoryYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing in {category} yet'**
  String sellNothingInCategoryYet(Object category);

  /// No description provided for @sellOfflinePaymentAction.
  ///
  /// In en, this message translates to:
  /// **'Offline payment'**
  String get sellOfflinePaymentAction;

  /// No description provided for @sellOfflinePaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Record offline payment'**
  String get sellOfflinePaymentTitle;

  /// No description provided for @sellOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get sellOutOfStock;

  /// No description provided for @sellPayAction.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get sellPayAction;

  /// No description provided for @sellPayByMethod.
  ///
  /// In en, this message translates to:
  /// **'Pay by {method}'**
  String sellPayByMethod(Object method);

  /// No description provided for @sellPaymentMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get sellPaymentMethodLabel;

  /// No description provided for @sellPaymentReceivedSaleRecorded.
  ///
  /// In en, this message translates to:
  /// **'Payment {reference} was received. The sale is now recorded.'**
  String sellPaymentReceivedSaleRecorded(Object reference);

  /// No description provided for @sellPaymentUnconfirmedTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment still unconfirmed'**
  String get sellPaymentUnconfirmedTitle;

  /// No description provided for @sellPhoneNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get sellPhoneNumberLabel;

  /// No description provided for @sellProcessingMpesaTitle.
  ///
  /// In en, this message translates to:
  /// **'Processing M-Pesa Payment'**
  String get sellProcessingMpesaTitle;

  /// No description provided for @sellReceiptDidNotPrint.
  ///
  /// In en, this message translates to:
  /// **'The sale is recorded, but the receipt did not print.'**
  String get sellReceiptDidNotPrint;

  /// No description provided for @sellRecordSaleAction.
  ///
  /// In en, this message translates to:
  /// **'Record sale'**
  String get sellRecordSaleAction;

  /// No description provided for @sellReferenceDeclined.
  ///
  /// In en, this message translates to:
  /// **'Reference {reference} was declined. Safe to retry.'**
  String sellReferenceDeclined(Object reference);

  /// No description provided for @sellReferenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Reference (optional)'**
  String get sellReferenceLabel;

  /// No description provided for @sellReferenceValue.
  ///
  /// In en, this message translates to:
  /// **'Reference: {reference}'**
  String sellReferenceValue(Object reference);

  /// No description provided for @sellReloadCatalogueAction.
  ///
  /// In en, this message translates to:
  /// **'Reload the catalogue'**
  String get sellReloadCatalogueAction;

  /// No description provided for @sellRemoveItem.
  ///
  /// In en, this message translates to:
  /// **'Remove {item}'**
  String sellRemoveItem(Object item);

  /// No description provided for @sellRemoveLineFromCart.
  ///
  /// In en, this message translates to:
  /// **'Remove {item} from the cart'**
  String sellRemoveLineFromCart(Object item);

  /// No description provided for @sellSaleNotRecordedNothingCharged.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record the sale. Nothing was charged — try again.'**
  String get sellSaleNotRecordedNothingCharged;

  /// No description provided for @sellSaleTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Sale total: {amount}'**
  String sellSaleTotalLabel(Object amount);

  /// No description provided for @sellScanBarcode.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get sellScanBarcode;

  /// No description provided for @sellScanCameraHint.
  ///
  /// In en, this message translates to:
  /// **'Adds one scanned product to the cart as a full bottle'**
  String get sellScanCameraHint;

  /// No description provided for @sellScanCameraLabel.
  ///
  /// In en, this message translates to:
  /// **'Scan a barcode with the camera'**
  String get sellScanCameraLabel;

  /// No description provided for @sellScanCameraError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the camera scanner. Try scanning with the hardware scanner, or pick the product by name.'**
  String get sellScanCameraError;

  /// No description provided for @sellPhoneNumberHint.
  ///
  /// In en, this message translates to:
  /// **'0712345678'**
  String get sellPhoneNumberHint;

  /// No description provided for @sellScanNoProductBarcode.
  ///
  /// In en, this message translates to:
  /// **'No product carries that barcode. Add it in Inventory — on the product or on one of its variants — or pick the product by name.'**
  String get sellScanNoProductBarcode;

  /// No description provided for @sellSearchNameOrCategory.
  ///
  /// In en, this message translates to:
  /// **'Name or category'**
  String get sellSearchNameOrCategory;

  /// No description provided for @sellSearchProducts.
  ///
  /// In en, this message translates to:
  /// **'Search products'**
  String get sellSearchProducts;

  /// No description provided for @sellShotsSection.
  ///
  /// In en, this message translates to:
  /// **'Cups'**
  String get sellShotsSection;

  /// No description provided for @sellVariantCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 variant} other{{count} variants}}'**
  String sellVariantCount(num count);

  /// No description provided for @sellCartItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String sellCartItemCount(num count);

  /// No description provided for @inventoryAddAnotherVariant.
  ///
  /// In en, this message translates to:
  /// **'Add another variant'**
  String get inventoryAddAnotherVariant;

  /// No description provided for @inventoryAddBarcode.
  ///
  /// In en, this message translates to:
  /// **'Add a barcode'**
  String get inventoryAddBarcode;

  /// No description provided for @inventoryAddFirstVariant.
  ///
  /// In en, this message translates to:
  /// **'Add its first variant'**
  String get inventoryAddFirstVariant;

  /// No description provided for @inventoryAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get inventoryAddProduct;

  /// No description provided for @inventoryManualRestock.
  ///
  /// In en, this message translates to:
  /// **'Restock manually'**
  String get inventoryManualRestock;

  /// No description provided for @settingsCreditSection.
  ///
  /// In en, this message translates to:
  /// **'Credit sales'**
  String get settingsCreditSection;

  /// No description provided for @settingsCreditOffSummary.
  ///
  /// In en, this message translates to:
  /// **'Off — on-account sales are not offered.'**
  String get settingsCreditOffSummary;

  /// No description provided for @settingsCreditOnSummary.
  ///
  /// In en, this message translates to:
  /// **'On — default limit {limit}.'**
  String settingsCreditOnSummary(Object limit);

  /// No description provided for @settingsCreditEnabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Allow sales on account'**
  String get settingsCreditEnabledLabel;

  /// No description provided for @settingsCreditDefaultLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Default credit limit (KSh)'**
  String get settingsCreditDefaultLimitLabel;

  /// No description provided for @settingsCreditLimitModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Over-limit sales'**
  String get settingsCreditLimitModeLabel;

  /// No description provided for @settingsCreditLimitBlock.
  ///
  /// In en, this message translates to:
  /// **'Require manager approval'**
  String get settingsCreditLimitBlock;

  /// No description provided for @settingsCreditLimitWarn.
  ///
  /// In en, this message translates to:
  /// **'Warn, then allow'**
  String get settingsCreditLimitWarn;

  /// No description provided for @settingsCreditCashiersLabel.
  ///
  /// In en, this message translates to:
  /// **'Allow cashiers to sell on account'**
  String get settingsCreditCashiersLabel;

  /// No description provided for @settingsCreditReminderLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment reminder message'**
  String get settingsCreditReminderLabel;

  /// No description provided for @settingsCreditReminderHelper.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to use the default reminder.'**
  String get settingsCreditReminderHelper;

  /// No description provided for @settingsCreditSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save credit settings'**
  String get settingsCreditSaveAction;

  /// No description provided for @settingsCreditInvalidLimit.
  ///
  /// In en, this message translates to:
  /// **'Enter a limit of 0 or more.'**
  String get settingsCreditInvalidLimit;

  /// No description provided for @settingsCreditSaved.
  ///
  /// In en, this message translates to:
  /// **'Credit settings saved.'**
  String get settingsCreditSaved;

  /// No description provided for @inventoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No products yet'**
  String get inventoryEmptyTitle;

  /// No description provided for @inventoryEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add your first product to start tracking stock and sales.'**
  String get inventoryEmptyBody;

  /// No description provided for @inventoryAddVariantsFirst.
  ///
  /// In en, this message translates to:
  /// **'Add {name}\'s variants first — its stock is their total.'**
  String inventoryAddVariantsFirst(Object name);

  /// No description provided for @inventoryAdjustAction.
  ///
  /// In en, this message translates to:
  /// **'Adjust stock'**
  String get inventoryAdjustAction;

  /// No description provided for @inventoryAdjustStockFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t adjust stock. Try again.'**
  String get inventoryAdjustStockFailed;

  /// No description provided for @inventoryAdjustStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust stock — {name}'**
  String inventoryAdjustStockTitle(Object name);

  /// No description provided for @inventoryBarcodeHint.
  ///
  /// In en, this message translates to:
  /// **'6001234567892'**
  String get inventoryBarcodeHint;

  /// No description provided for @inventoryBarcodeOnOtherProduct.
  ///
  /// In en, this message translates to:
  /// **'That barcode is already on another product.'**
  String get inventoryBarcodeOnOtherProduct;

  /// No description provided for @inventoryBarcodesHelp.
  ///
  /// In en, this message translates to:
  /// **'A code on the product adds the whole product. A code on a variant — entered in that variant\'s own form — adds that variant, at its price and from its stock. Each code can only ever resolve to one of them.'**
  String get inventoryBarcodesHelp;

  /// No description provided for @inventoryBarcodesSection.
  ///
  /// In en, this message translates to:
  /// **'Barcodes'**
  String get inventoryBarcodesSection;

  /// No description provided for @inventoryChooseVariantTitle.
  ///
  /// In en, this message translates to:
  /// **'Which variant? · {name}'**
  String inventoryChooseVariantTitle(Object name);

  /// No description provided for @inventoryDefaultCategory.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get inventoryDefaultCategory;

  /// No description provided for @inventoryDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get inventoryDeleteAction;

  /// No description provided for @inventoryDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from inventory? Its past sales stay on record.'**
  String inventoryDeleteMessage(Object name);

  /// No description provided for @inventoryDeactivatedProduct.
  ///
  /// In en, this message translates to:
  /// **'deactivated {name}'**
  String inventoryDeactivatedProduct(Object name);

  /// No description provided for @inventoryDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete product?'**
  String get inventoryDeleteTitle;

  /// No description provided for @inventoryDeltaLabel.
  ///
  /// In en, this message translates to:
  /// **'Change (+50 restock, -2 breakage)'**
  String get inventoryDeltaLabel;

  /// No description provided for @inventoryEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get inventoryEditAction;

  /// No description provided for @inventoryActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Product actions'**
  String get inventoryActionsTooltip;

  /// No description provided for @inventoryEditProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit product'**
  String get inventoryEditProduct;

  /// No description provided for @inventoryExciseStampField.
  ///
  /// In en, this message translates to:
  /// **'Excise stamp batch (optional)'**
  String get inventoryExciseStampField;

  /// No description provided for @inventoryFieldCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get inventoryFieldCategory;

  /// No description provided for @inventoryFieldCostPrice.
  ///
  /// In en, this message translates to:
  /// **'Cost price'**
  String get inventoryFieldCostPrice;

  /// No description provided for @inventoryFieldHalfPrice.
  ///
  /// In en, this message translates to:
  /// **'Half price'**
  String get inventoryFieldHalfPrice;

  /// No description provided for @inventoryFieldHalfPriceOptional.
  ///
  /// In en, this message translates to:
  /// **'Half price (optional)'**
  String get inventoryFieldHalfPriceOptional;

  /// No description provided for @inventoryFieldHalfPriceHelper.
  ///
  /// In en, this message translates to:
  /// **'Only products with a half price are sold in halves. Leave it empty and the till will not offer a half.'**
  String get inventoryFieldHalfPriceHelper;

  /// No description provided for @inventoryFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get inventoryFieldName;

  /// No description provided for @inventoryFieldQuarterPrice.
  ///
  /// In en, this message translates to:
  /// **'Quarter price'**
  String get inventoryFieldQuarterPrice;

  /// No description provided for @inventoryFieldQuarterPriceOptional.
  ///
  /// In en, this message translates to:
  /// **'Quarter price (optional)'**
  String get inventoryFieldQuarterPriceOptional;

  /// No description provided for @inventoryFieldQuarterPriceHelper.
  ///
  /// In en, this message translates to:
  /// **'Only products with a quarter price are sold in quarters. Leave it empty and the till will not offer a quarter.'**
  String get inventoryFieldQuarterPriceHelper;

  /// No description provided for @inventoryPhotoSection.
  ///
  /// In en, this message translates to:
  /// **'Photograph'**
  String get inventoryPhotoSection;

  /// No description provided for @inventoryPhotoHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown on the till so a cashier can match the shelf. Not shown anywhere else in the app.'**
  String get inventoryPhotoHelp;

  /// No description provided for @inventoryPhotoFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get inventoryPhotoFromGallery;

  /// No description provided for @inventoryPhotoFromCamera.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get inventoryPhotoFromCamera;

  /// No description provided for @inventoryPhotoAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a photograph'**
  String get inventoryPhotoAdd;

  /// No description provided for @inventoryPhotoRemovedNote.
  ///
  /// In en, this message translates to:
  /// **'The photograph will be removed when you save.'**
  String get inventoryPhotoRemovedNote;

  /// No description provided for @inventoryPhotoChange.
  ///
  /// In en, this message translates to:
  /// **'Change photograph'**
  String get inventoryPhotoChange;

  /// No description provided for @inventoryPhotoRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove photograph'**
  String get inventoryPhotoRemove;

  /// No description provided for @inventoryPhotoAddFailed.
  ///
  /// In en, this message translates to:
  /// **'The photograph could not be saved. Check the phone has storage space free, then try again.'**
  String get inventoryPhotoAddFailed;

  /// No description provided for @inventoryPhotoRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'The photograph could not be removed. Try again.'**
  String get inventoryPhotoRemoveFailed;

  /// No description provided for @inventoryFieldReorderLevel.
  ///
  /// In en, this message translates to:
  /// **'Reorder level'**
  String get inventoryFieldReorderLevel;

  /// No description provided for @inventoryFieldSellPrice.
  ///
  /// In en, this message translates to:
  /// **'Sell price'**
  String get inventoryFieldSellPrice;

  /// No description provided for @inventoryFieldSizeMl.
  ///
  /// In en, this message translates to:
  /// **'Size (ml)'**
  String get inventoryFieldSizeMl;

  /// No description provided for @inventoryFieldSizeMlHelper.
  ///
  /// In en, this message translates to:
  /// **'Bottle, keg or tank — 330, 500, 50000'**
  String get inventoryFieldSizeMlHelper;

  /// No description provided for @productUnitPickerLabel.
  ///
  /// In en, this message translates to:
  /// **'How this product is measured'**
  String get productUnitPickerLabel;

  /// No description provided for @productUnitEach.
  ///
  /// In en, this message translates to:
  /// **'Counted'**
  String get productUnitEach;

  /// No description provided for @productUnitLitre.
  ///
  /// In en, this message translates to:
  /// **'By the litre'**
  String get productUnitLitre;

  /// No description provided for @productUnitMillilitre.
  ///
  /// In en, this message translates to:
  /// **'By the millilitre'**
  String get productUnitMillilitre;

  /// No description provided for @productUnitCup.
  ///
  /// In en, this message translates to:
  /// **'By the cup'**
  String get productUnitCup;

  /// No description provided for @productSizeLabelLitre.
  ///
  /// In en, this message translates to:
  /// **'How many ml one litre holds'**
  String get productSizeLabelLitre;

  /// No description provided for @productSizeLabelMillilitre.
  ///
  /// In en, this message translates to:
  /// **'How many ml one unit holds'**
  String get productSizeLabelMillilitre;

  /// No description provided for @productSizeLabelCup.
  ///
  /// In en, this message translates to:
  /// **'How many ml one cup holds'**
  String get productSizeLabelCup;

  /// No description provided for @productUnitCupPourHint.
  ///
  /// In en, this message translates to:
  /// **'Cups are poured from a bigger container: add that container, then configure its cups in Inventory.'**
  String get productUnitCupPourHint;

  /// No description provided for @inventoryFieldStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get inventoryFieldStock;

  /// No description provided for @inventoryFieldStockQty.
  ///
  /// In en, this message translates to:
  /// **'Stock qty'**
  String get inventoryFieldStockQty;

  /// No description provided for @inventoryFieldTotalStock.
  ///
  /// In en, this message translates to:
  /// **'Total stock (from variants)'**
  String get inventoryFieldTotalStock;

  /// No description provided for @inventoryGoBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get inventoryGoBack;

  /// No description provided for @inventoryLowStockLimitTitle.
  ///
  /// In en, this message translates to:
  /// **'Low stock limit'**
  String get inventoryLowStockLimitTitle;

  /// No description provided for @inventoryLowStockLimitSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every product warns below {limit}. Tap to change.'**
  String inventoryLowStockLimitSubtitle(Object limit);

  /// No description provided for @inventoryLowStockLimitAudit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No products} =1{1 product} other{{count} products}} low-stock limit set to {limit}'**
  String inventoryLowStockLimitAudit(num count, Object limit);

  /// No description provided for @inventoryLowStockLimitApplied.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No products to set} =1{1 product now warns below {limit}} other{{count} products now warn below {limit}}}'**
  String inventoryLowStockLimitApplied(num count, Object limit);

  /// No description provided for @importsTitle.
  ///
  /// In en, this message translates to:
  /// **'Import problems'**
  String get importsTitle;

  /// No description provided for @importsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing waiting on you'**
  String get importsEmptyTitle;

  /// No description provided for @importsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Every row from the last import was either written or answered. Import a spreadsheet to add stock in bulk.'**
  String get importsEmptyMessage;

  /// No description provided for @importsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the import list. Try again; if it keeps happening, contact support.'**
  String get importsLoadFailed;

  /// No description provided for @importsCompleteAction.
  ///
  /// In en, this message translates to:
  /// **'Fill in what\'s missing'**
  String get importsCompleteAction;

  /// No description provided for @importsCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Finish this row'**
  String get importsCompleteTitle;

  /// No description provided for @importsPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'This price'**
  String get importsPriceLabel;

  /// No description provided for @importSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'That row could not be saved. Try again; if it keeps happening, contact support.'**
  String get importSaveFailed;

  /// No description provided for @inventoryLowPriceMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} would sell at a loss (KSh {price} vs cost KSh {cost}). Save anyway?'**
  String inventoryLowPriceMessage(Object cost, Object name, Object price);

  /// No description provided for @inventoryLowPriceTitle.
  ///
  /// In en, this message translates to:
  /// **'Sell price is below cost'**
  String get inventoryLowPriceTitle;

  /// No description provided for @inventoryInStock.
  ///
  /// In en, this message translates to:
  /// **'In stock'**
  String get inventoryInStock;

  /// No description provided for @inventoryLowStock.
  ///
  /// In en, this message translates to:
  /// **'low stock'**
  String get inventoryLowStock;

  /// No description provided for @inventoryOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get inventoryOutOfStock;

  /// No description provided for @inventoryNewVariantName.
  ///
  /// In en, this message translates to:
  /// **'New variant'**
  String get inventoryNewVariantName;

  /// No description provided for @inventoryNoBarcodesYet.
  ///
  /// In en, this message translates to:
  /// **'No barcodes yet — this product is sold by name only.'**
  String get inventoryNoBarcodesYet;

  /// No description provided for @inventoryNoVariantsYet.
  ///
  /// In en, this message translates to:
  /// **'no variants yet'**
  String get inventoryNoVariantsYet;

  /// No description provided for @inventoryReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get inventoryReasonLabel;

  /// No description provided for @inventoryRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get inventoryRemoveAction;

  /// No description provided for @inventoryRemoveVariantBarcodeFreed.
  ///
  /// In en, this message translates to:
  /// **'Its barcode is freed so another variant can use it. Sales already recorded keep the name they were sold under.'**
  String get inventoryRemoveVariantBarcodeFreed;

  /// No description provided for @inventoryRemoveVariantStopsSelling.
  ///
  /// In en, this message translates to:
  /// **'It stops being offered at the till. Sales already recorded keep the name they were sold under.'**
  String get inventoryRemoveVariantStopsSelling;

  /// No description provided for @inventoryRemoveVariantTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String inventoryRemoveVariantTitle(Object name);

  /// No description provided for @inventorySaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get inventorySaveAction;

  /// No description provided for @inventorySaveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get inventorySaveAnyway;

  /// No description provided for @inventorySaveBeforeBarcode.
  ///
  /// In en, this message translates to:
  /// **'Save the product first, then add its barcode(s).'**
  String get inventorySaveBeforeBarcode;

  /// No description provided for @inventorySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save — check the phone has storage space free, then try again.'**
  String get inventorySaveFailed;

  /// No description provided for @inventorySaveProductAndVariants.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Save product} =1{Save product and 1 variant} other{Save product and {count} variants}}'**
  String inventorySaveProductAndVariants(num count);

  /// No description provided for @inventoryShotCupsSpoken.
  ///
  /// In en, this message translates to:
  /// **'Cups. Fixed-size cups of any drink in your inventory.'**
  String get inventoryShotCupsSpoken;

  /// No description provided for @inventoryShotCupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Cups'**
  String get inventoryShotCupsTitle;

  /// No description provided for @inventorySizeSuggestionsSpoken.
  ///
  /// In en, this message translates to:
  /// **'Sizes you have used before'**
  String get inventorySizeSuggestionsSpoken;

  /// No description provided for @inventorySoldAsVariants.
  ///
  /// In en, this message translates to:
  /// **'Sold as variants'**
  String get inventorySoldAsVariants;

  /// No description provided for @inventorySoldAsVariantsOffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'For Dark and Regular, or a big cup and a small cup, at different prices'**
  String get inventorySoldAsVariantsOffSubtitle;

  /// No description provided for @inventorySoldAsVariantsOnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The till offers Dark, Regular, Big cup… instead of the whole product'**
  String get inventorySoldAsVariantsOnSubtitle;

  /// No description provided for @inventoryStockCannotGoBelowZero.
  ///
  /// In en, this message translates to:
  /// **'Stock cannot go below zero. Check the current quantity and try again.'**
  String get inventoryStockCannotGoBelowZero;

  /// No description provided for @inventoryStockSavedLocally.
  ///
  /// In en, this message translates to:
  /// **'Stock updated on this till. The online count will catch up on the next sync.'**
  String get inventoryStockSavedLocally;

  /// No description provided for @inventoryStockUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Stock update failed. Refresh the inventory and try again.'**
  String get inventoryStockUpdateFailed;

  /// No description provided for @inventoryThisProduct.
  ///
  /// In en, this message translates to:
  /// **'This product'**
  String get inventoryThisProduct;

  /// No description provided for @inventoryUnnamedVariant.
  ///
  /// In en, this message translates to:
  /// **'Give every variant a name — one of them has none (position {position}).'**
  String inventoryUnnamedVariant(Object position);

  /// No description provided for @inventoryVariantStockNow.
  ///
  /// In en, this message translates to:
  /// **'{name} is now {count} in stock.'**
  String inventoryVariantStockNow(Object count, Object name);

  /// No description provided for @inventoryVariantsSection.
  ///
  /// In en, this message translates to:
  /// **'Variants'**
  String get inventoryVariantsSection;

  /// No description provided for @settingsAddShopOnDeviceAction.
  ///
  /// In en, this message translates to:
  /// **'Add another shop on this device'**
  String get settingsAddShopOnDeviceAction;

  /// No description provided for @settingsAddShopTitle.
  ///
  /// In en, this message translates to:
  /// **'Add another shop'**
  String get settingsAddShopTitle;

  /// No description provided for @settingsAddStaffAction.
  ///
  /// In en, this message translates to:
  /// **'Add staff'**
  String get settingsAddStaffAction;

  /// No description provided for @settingsAutoBackupSync.
  ///
  /// In en, this message translates to:
  /// **'Automatic backup and online sync'**
  String get settingsAutoBackupSync;

  /// No description provided for @settingsBackupSection.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get settingsBackupSection;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get profileTitle;

  /// No description provided for @profileNoAccountYet.
  ///
  /// In en, this message translates to:
  /// **'No account is set up yet.'**
  String get profileNoAccountYet;

  /// No description provided for @profileEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get profileEditAction;

  /// No description provided for @profileEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit your details'**
  String get profileEditTitle;

  /// No description provided for @profileEditNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get profileEditNameLabel;

  /// No description provided for @profileEditNameHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown on the till and on the receipts.'**
  String get profileEditNameHelp;

  /// No description provided for @profileEditShopNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get profileEditShopNameLabel;

  /// No description provided for @profileEditEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get profileEditEmailLabel;

  /// No description provided for @profileEditEmailHelp.
  ///
  /// In en, this message translates to:
  /// **'Where PIN-recovery and verification codes are sent.'**
  String get profileEditEmailHelp;

  /// No description provided for @profileEditEmailWarning.
  ///
  /// In en, this message translates to:
  /// **'Changing the email moves where recovery codes are sent. A new address has to be verified before it can be used to recover the PIN, and until it is, keep the old one working.'**
  String get profileEditEmailWarning;

  /// No description provided for @profileEditSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get profileEditSave;

  /// No description provided for @profileEditSaved.
  ///
  /// In en, this message translates to:
  /// **'Your details were saved.'**
  String get profileEditSaved;

  /// No description provided for @profileEditFailed.
  ///
  /// In en, this message translates to:
  /// **'Your details could not be saved. Nothing was changed.'**
  String get profileEditFailed;

  /// No description provided for @profilePhotoLabel.
  ///
  /// In en, this message translates to:
  /// **'Photograph'**
  String get profilePhotoLabel;

  /// No description provided for @profilePhotoHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown next to your name. Pick one from the gallery or take a photo.'**
  String get profilePhotoHelp;

  /// No description provided for @profilePhotoChange.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get profilePhotoChange;

  /// No description provided for @profilePhotoSaved.
  ///
  /// In en, this message translates to:
  /// **'Photograph saved.'**
  String get profilePhotoSaved;

  /// No description provided for @profileEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get profileEmailLabel;

  /// No description provided for @profileVerifiedLabel.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get profileVerifiedLabel;

  /// No description provided for @profileVerifiedYes.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get profileVerifiedYes;

  /// No description provided for @profileVerifiedNo.
  ///
  /// In en, this message translates to:
  /// **'Not verified yet'**
  String get profileVerifiedNo;

  /// No description provided for @profileSinceLabel.
  ///
  /// In en, this message translates to:
  /// **'Selling since'**
  String get profileSinceLabel;

  /// No description provided for @profileShopLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get profileShopLabel;

  /// No description provided for @profileBackToSettings.
  ///
  /// In en, this message translates to:
  /// **'Back to settings'**
  String get profileBackToSettings;

  /// No description provided for @statusDeletionPending.
  ///
  /// In en, this message translates to:
  /// **'Your online account could not be deleted yet. It will be deleted the next time this till can reach the server.'**
  String get statusDeletionPending;

  /// No description provided for @statusBackupOverdue.
  ///
  /// In en, this message translates to:
  /// **'This phone has not been backed up for a while.'**
  String get statusBackupOverdue;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'This till is offline. Sales are still being recorded.'**
  String get statusOffline;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting to the server.'**
  String get statusConnecting;

  /// No description provided for @importRepairedTitle.
  ///
  /// In en, this message translates to:
  /// **'Row repaired'**
  String get importRepairedTitle;

  /// No description provided for @importRepairFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The row was not repaired'**
  String get importRepairFailedTitle;

  /// No description provided for @profileEditSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Details saved'**
  String get profileEditSavedTitle;

  /// No description provided for @profileEditFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The details were not saved'**
  String get profileEditFailedTitle;

  /// No description provided for @inventoryProductSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Product saved'**
  String get inventoryProductSavedTitle;

  /// No description provided for @inventoryProductUpdatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Product updated'**
  String get inventoryProductUpdatedTitle;

  /// No description provided for @inventoryStockSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock updated'**
  String get inventoryStockSavedTitle;

  /// No description provided for @settingsBackupsErasedTitle.
  ///
  /// In en, this message translates to:
  /// **'Backups erased'**
  String get settingsBackupsErasedTitle;

  /// No description provided for @settingsBackupsEraseFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Some backups could not be erased'**
  String get settingsBackupsEraseFailedTitle;

  /// No description provided for @settingsMpesaUpdateFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The setting was not saved'**
  String get settingsMpesaUpdateFailedTitle;

  /// No description provided for @settingsIdentityVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Identity verified'**
  String get settingsIdentityVerifiedTitle;

  /// No description provided for @settingsSyncDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync finished'**
  String get settingsSyncDoneTitle;

  /// No description provided for @settingsStaffSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cashier saved'**
  String get settingsStaffSavedTitle;

  /// No description provided for @settingsStaffSaveFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The cashier was not saved'**
  String get settingsStaffSaveFailedTitle;

  /// No description provided for @settingsStaffRemovedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cashier removed'**
  String get settingsStaffRemovedTitle;

  /// No description provided for @settingsStaffRemoveFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The cashier was not removed'**
  String get settingsStaffRemoveFailedTitle;

  /// No description provided for @settingsPinResetTitle.
  ///
  /// In en, this message translates to:
  /// **'PIN reset'**
  String get settingsPinResetTitle;

  /// No description provided for @settingsBackupDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup made'**
  String get settingsBackupDoneTitle;

  /// No description provided for @settingsBackupDone.
  ///
  /// In en, this message translates to:
  /// **'The encrypted backup was made and is ready to share.'**
  String get settingsBackupDone;

  /// No description provided for @settingsBackupFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The backup failed'**
  String get settingsBackupFailedTitle;

  /// No description provided for @settingsBackupFailed.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be made. The data on this phone is unchanged, and nothing was shared.'**
  String get settingsBackupFailed;

  /// No description provided for @settingsExportDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Export ready'**
  String get settingsExportDoneTitle;

  /// No description provided for @settingsExportEncryptedDone.
  ///
  /// In en, this message translates to:
  /// **'The encrypted backup file is ready to share.'**
  String get settingsExportEncryptedDone;

  /// No description provided for @settingsExportInventoryDone.
  ///
  /// In en, this message translates to:
  /// **'The inventory workbook is ready to share.'**
  String get settingsExportInventoryDone;

  /// No description provided for @settingsExportFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The export failed'**
  String get settingsExportFailedTitle;

  /// No description provided for @settingsExportFailed.
  ///
  /// In en, this message translates to:
  /// **'The file could not be made. Nothing was shared.'**
  String get settingsExportFailed;

  /// No description provided for @settingsRestoreDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup restored'**
  String get settingsRestoreDoneTitle;

  /// No description provided for @settingsRestoreFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The backup was not restored'**
  String get settingsRestoreFailedTitle;

  /// No description provided for @settingsImportDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get settingsImportDoneTitle;

  /// No description provided for @settingsImportFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The import failed'**
  String get settingsImportFailedTitle;

  /// No description provided for @settingsUpdateFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'The update was not installed'**
  String get settingsUpdateFailedTitle;

  /// No description provided for @settingsAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get settingsAccountSection;

  /// No description provided for @settingsProfileRow.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get settingsProfileRow;

  /// No description provided for @settingsUpdatesSection.
  ///
  /// In en, this message translates to:
  /// **'App updates'**
  String get settingsUpdatesSection;

  /// No description provided for @settingsUpdatesCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsUpdatesCheck;

  /// No description provided for @settingsUpdatesAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is ready'**
  String settingsUpdatesAvailable(Object version);

  /// No description provided for @settingsUpdatesFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not check for updates: {reason}'**
  String settingsUpdatesFailed(Object reason);

  /// No description provided for @settingsUpdatesReasonUnreachable.
  ///
  /// In en, this message translates to:
  /// **'the server could not be reached'**
  String get settingsUpdatesReasonUnreachable;

  /// No description provided for @settingsUpdatesReasonMalformed.
  ///
  /// In en, this message translates to:
  /// **'the server did not send a release'**
  String get settingsUpdatesReasonMalformed;

  /// No description provided for @settingsUpdatesCurrent.
  ///
  /// In en, this message translates to:
  /// **'You are on the newest version ({version})'**
  String settingsUpdatesCurrent(Object version);

  /// No description provided for @settingsUpdatesUnknownVersion.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get settingsUpdatesUnknownVersion;

  /// No description provided for @settingsUpdatesInstall.
  ///
  /// In en, this message translates to:
  /// **'Install now'**
  String get settingsUpdatesInstall;

  /// No description provided for @settingsUpdatesDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent}%'**
  String settingsUpdatesDownloading(Object percent);

  /// No description provided for @settingsUpdatesDownloadingUnknown.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get settingsUpdatesDownloadingUnknown;

  /// No description provided for @settingsUpdatesReady.
  ///
  /// In en, this message translates to:
  /// **'Downloaded. Tap install to apply it.'**
  String get settingsUpdatesReady;

  /// No description provided for @settingsUpdatesNoNotes.
  ///
  /// In en, this message translates to:
  /// **'No release notes were published for this version.'**
  String get settingsUpdatesNoNotes;

  /// No description provided for @settingsUpdatesRefused.
  ///
  /// In en, this message translates to:
  /// **'The phone refused this update. It can only be installed over the same signing key and a higher build number — ask the shop\'s developer.'**
  String get settingsUpdatesRefused;

  /// No description provided for @settingsUpdatesPermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'This phone needs permission to install apps. Settings has opened.'**
  String get settingsUpdatesPermissionNeeded;

  /// No description provided for @settingsUpdatesPermissionManual.
  ///
  /// In en, this message translates to:
  /// **'This phone needs permission to install apps. Allow it in Settings, then tap install again.'**
  String get settingsUpdatesPermissionManual;

  /// No description provided for @settingsUpdatesRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart to update'**
  String get settingsUpdatesRestart;

  /// No description provided for @settingsUpdatesPromptBody.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is ready. Your shop\'s data is kept — this updates the app in place instead of replacing it.'**
  String settingsUpdatesPromptBody(Object version);

  /// No description provided for @settingsUpdatesAutoLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-update when idle'**
  String get settingsUpdatesAutoLabel;

  /// No description provided for @settingsUpdatesAutoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Downloads and installs updates while the till is quiet, so the shop never has to stop selling.'**
  String get settingsUpdatesAutoSubtitle;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supportTitle;

  /// No description provided for @supportTicketsSection.
  ///
  /// In en, this message translates to:
  /// **'Support tickets'**
  String get supportTicketsSection;

  /// No description provided for @supportTicketsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us what is broken so we can fix it.'**
  String get supportTicketsSubtitle;

  /// No description provided for @supportNoTickets.
  ///
  /// In en, this message translates to:
  /// **'No support tickets yet. File one below.'**
  String get supportNoTickets;

  /// No description provided for @supportFileTicketLabel.
  ///
  /// In en, this message translates to:
  /// **'What is wrong?'**
  String get supportFileTicketLabel;

  /// No description provided for @supportTicketHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the problem — what you were doing, what happened, and what you expected instead.'**
  String get supportTicketHint;

  /// No description provided for @supportFileTicketAction.
  ///
  /// In en, this message translates to:
  /// **'File ticket'**
  String get supportFileTicketAction;

  /// No description provided for @supportFeatureRequestsSection.
  ///
  /// In en, this message translates to:
  /// **'Feature requests'**
  String get supportFeatureRequestsSection;

  /// No description provided for @supportFeatureRequestsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us what you need next.'**
  String get supportFeatureRequestsSubtitle;

  /// No description provided for @supportNoRequests.
  ///
  /// In en, this message translates to:
  /// **'No feature requests yet. File one below.'**
  String get supportNoRequests;

  /// No description provided for @supportFileRequestLabel.
  ///
  /// In en, this message translates to:
  /// **'What would you like?'**
  String get supportFileRequestLabel;

  /// No description provided for @supportRequestHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the feature — what it should do, and when you would use it.'**
  String get supportRequestHint;

  /// No description provided for @supportFileRequestAction.
  ///
  /// In en, this message translates to:
  /// **'File request'**
  String get supportFileRequestAction;

  /// No description provided for @supportDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get supportDescriptionLabel;

  /// No description provided for @supportDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'More detail helps us fix it faster.'**
  String get supportDescriptionHint;

  /// No description provided for @settingsCashMethod.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get settingsCashMethod;

  /// No description provided for @settingsPrinterRescan.
  ///
  /// In en, this message translates to:
  /// **'Look again'**
  String get settingsPrinterRescan;

  /// No description provided for @settingsPrinterScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the Bluetooth devices. Check Bluetooth is on, then look again.'**
  String get settingsPrinterScanFailed;

  /// No description provided for @settingsNoPairedPrintersHint.
  ///
  /// In en, this message translates to:
  /// **'Pair the printer in this phone\'s Bluetooth settings first, then look again.'**
  String get settingsNoPairedPrintersHint;

  /// No description provided for @settingsChoosePrinter.
  ///
  /// In en, this message translates to:
  /// **'Choose printer'**
  String get settingsChoosePrinter;

  /// No description provided for @settingsConnectAction.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get settingsConnectAction;

  /// No description provided for @settingsConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t connect. Check the identity login and internet connection.'**
  String get settingsConnectFailed;

  /// No description provided for @settingsConnectMpesaTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect M-Pesa'**
  String get settingsConnectMpesaTitle;

  /// No description provided for @settingsCreateShopFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t create the shop. Check the phone has storage free, then try again.'**
  String get settingsCreateShopFailed;

  /// No description provided for @settingsDecryptBackupFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t decrypt the backup.'**
  String get settingsDecryptBackupFailed;

  /// No description provided for @settingsEnterStaffName.
  ///
  /// In en, this message translates to:
  /// **'Enter a staff name'**
  String get settingsEnterStaffName;

  /// No description provided for @settingsEraseBackupsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Erase local backups'**
  String get settingsEraseBackupsConfirm;

  /// No description provided for @settingsEraseBackupsMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes this phone’s backup key and encrypted backup files. Copies already shared to another device or cloud storage are not erased.'**
  String get settingsEraseBackupsMessage;

  /// No description provided for @settingsEraseBackupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Erase encrypted backups?'**
  String get settingsEraseBackupsTitle;

  /// No description provided for @settingsEraseLocalBackupsAction.
  ///
  /// In en, this message translates to:
  /// **'Erase local encrypted backups'**
  String get settingsEraseLocalBackupsAction;

  /// No description provided for @settingsDeleteAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccountAction;

  /// No description provided for @accountDeleteLocalAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete the cashier logins on this phone?'**
  String get accountDeleteLocalAccountsTitle;

  /// No description provided for @accountDeleteLocalAccountsMessage.
  ///
  /// In en, this message translates to:
  /// **'The cashiers’ sign-in details are removed from this phone, so nobody can sign in to this till afterwards. Their names on past sales stay, because those are the shop’s records.'**
  String get accountDeleteLocalAccountsMessage;

  /// No description provided for @accountDeleteLocalAccountsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete them'**
  String get accountDeleteLocalAccountsDelete;

  /// No description provided for @accountDeleteLocalAccountsKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep them'**
  String get accountDeleteLocalAccountsKeep;

  /// No description provided for @accountDeleteLocalAccountsRemoved.
  ///
  /// In en, this message translates to:
  /// **'The cashier logins on this phone were deleted. Nobody can sign in to this till.'**
  String get accountDeleteLocalAccountsRemoved;

  /// No description provided for @accountDeleteLocalAccountsSealed.
  ///
  /// In en, this message translates to:
  /// **'The cashier logins on this phone were sealed: they cannot be used, but the records of them were kept.'**
  String get accountDeleteLocalAccountsSealed;

  /// No description provided for @settingsBackupsErasedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No backup files were on this phone.} =1{One backup file was erased.} other{{count} backup files were erased.}}'**
  String settingsBackupsErasedCount(num count);

  /// No description provided for @settingsBackupsEraseFailed.
  ///
  /// In en, this message translates to:
  /// **'The backup files could not all be erased. The key is gone, so anything left cannot be read, but there may be a file left on the phone.'**
  String get settingsBackupsEraseFailed;

  /// No description provided for @accountDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this account for good?'**
  String get accountDeleteConfirmTitle;

  /// No description provided for @accountDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Your online account and this shop’s record of it are deleted. Everything on this phone that names or contacts a person — your name, your email, your PIN, the cashiers, the till numbers — is overwritten with unreadable data, and the key that would read it back is destroyed. The takings and stock figures themselves are left alone, because those are your books.\n\nAny encrypted backup taken before today is also made unreadable. This cannot be undone.'**
  String get accountDeleteConfirmMessage;

  /// No description provided for @accountDeleteConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Delete and erase'**
  String get accountDeleteConfirmAction;

  /// No description provided for @accountDeleteDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Account deleted'**
  String get accountDeleteDoneTitle;

  /// No description provided for @accountDeleteDoneRemote.
  ///
  /// In en, this message translates to:
  /// **'The online account is deleted on the server as well as on this phone. Keep the receipt below.'**
  String get accountDeleteDoneRemote;

  /// No description provided for @accountDeleteDoneLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'This phone no longer holds any of your details. The server could not be reached, so ask it to finish the deletion when you are back online — the receipt below is what to quote.'**
  String get accountDeleteDoneLocalOnly;

  /// No description provided for @accountDeleteReceipt.
  ///
  /// In en, this message translates to:
  /// **'Deletion reference: {id}\nCompleted: {at}'**
  String accountDeleteReceipt(Object at, Object id);

  /// No description provided for @accountDeleteCompactionPending.
  ///
  /// In en, this message translates to:
  /// **'The data is unreadable, but the file was never fully rewritten. Open the app again with free storage to finish the job.'**
  String get accountDeleteCompactionPending;

  /// No description provided for @accountDeleteErasureFailed.
  ///
  /// In en, this message translates to:
  /// **'The account was not deleted because the erasure could not finish. Nothing was changed.'**
  String get accountDeleteErasureFailed;

  /// No description provided for @settingsForgotPinAction.
  ///
  /// In en, this message translates to:
  /// **'Forgot PIN?'**
  String get settingsForgotPinAction;

  /// No description provided for @pinResetRowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Email a code and set a new owner PIN'**
  String get pinResetRowSubtitle;

  /// No description provided for @pinResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a new owner PIN'**
  String get pinResetTitle;

  /// No description provided for @pinResetIntro.
  ///
  /// In en, this message translates to:
  /// **'We will email a 6-digit code to {email}. It proves the phone belongs to you, which is the only way a forgotten PIN can be reset.'**
  String pinResetIntro(Object email);

  /// No description provided for @pinResetSendCode.
  ///
  /// In en, this message translates to:
  /// **'Email me a code'**
  String get pinResetSendCode;

  /// No description provided for @pinResetSending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get pinResetSending;

  /// No description provided for @pinResetResend.
  ///
  /// In en, this message translates to:
  /// **'Send another code'**
  String get pinResetResend;

  /// No description provided for @pinResetSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get pinResetSaving;

  /// No description provided for @pinResetSentTo.
  ///
  /// In en, this message translates to:
  /// **'Code sent to {email}. Enter it here, then your new PIN.'**
  String pinResetSentTo(Object email);

  /// No description provided for @pinResetCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code from the email'**
  String get pinResetCodeLabel;

  /// No description provided for @pinResetNewPinLabel.
  ///
  /// In en, this message translates to:
  /// **'New PIN'**
  String get pinResetNewPinLabel;

  /// No description provided for @pinResetNewPinAgainLabel.
  ///
  /// In en, this message translates to:
  /// **'New PIN again'**
  String get pinResetNewPinAgainLabel;

  /// No description provided for @pinResetPinsDiffer.
  ///
  /// In en, this message translates to:
  /// **'The two PINs do not match.'**
  String get pinResetPinsDiffer;

  /// No description provided for @pinResetPinShape.
  ///
  /// In en, this message translates to:
  /// **'A PIN is exactly six digits.'**
  String get pinResetPinShape;

  /// No description provided for @pinResetCodeWrong.
  ///
  /// In en, this message translates to:
  /// **'That code is not right. Check your email and try again.'**
  String get pinResetCodeWrong;

  /// No description provided for @pinResetOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection. A PIN reset needs the server to email you a code, so it cannot run offline.'**
  String get pinResetOffline;

  /// No description provided for @pinResetTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server did not answer in time. Try again.'**
  String get pinResetTimeout;

  /// No description provided for @pinResetTooMany.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a few minutes, then ask for a new code.'**
  String get pinResetTooMany;

  /// No description provided for @pinResetNoEmail.
  ///
  /// In en, this message translates to:
  /// **'This shop has no email on record, so there is nowhere to send a code. Add and verify an email first.'**
  String get pinResetNoEmail;

  /// No description provided for @pinResetStartOver.
  ///
  /// In en, this message translates to:
  /// **'That code has expired. Ask for a new one.'**
  String get pinResetStartOver;

  /// No description provided for @pinResetServer.
  ///
  /// In en, this message translates to:
  /// **'The server refused the reset. Try again shortly.'**
  String get pinResetServer;

  /// No description provided for @pinResetDone.
  ///
  /// In en, this message translates to:
  /// **'Your owner PIN has been changed. Use the new one from now on.'**
  String get pinResetDone;

  /// No description provided for @settingsExportEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Export encrypted backup (.duka)'**
  String get settingsExportEncrypted;

  /// No description provided for @settingsExportInventory.
  ///
  /// In en, this message translates to:
  /// **'Export inventory (.xlsx)'**
  String get settingsExportInventory;

  /// No description provided for @settingsIdentityLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not link your online account. Check your connection and sign in with the same email you entered during setup.'**
  String get settingsIdentityLinkFailed;

  /// No description provided for @settingsIdentityLinked.
  ///
  /// In en, this message translates to:
  /// **'Online identity linked. M-Pesa and analytics are now available.'**
  String get settingsIdentityLinked;

  /// No description provided for @settingsIdentityVerified.
  ///
  /// In en, this message translates to:
  /// **'Signed in. Auto-backups, analytics and auto-update are now on.'**
  String get settingsIdentityVerified;

  /// No description provided for @settingsIdentityNotLinkedMessage.
  ///
  /// In en, this message translates to:
  /// **'Selling works fully offline. Verify your email to switch on auto-backups, analytics and auto-update.'**
  String get settingsIdentityNotLinkedMessage;

  /// No description provided for @settingsIdentityNotLinkedTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email to finish setup'**
  String get settingsIdentityNotLinkedTitle;

  /// No description provided for @settingsVerifyPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your admin PIN'**
  String get settingsVerifyPinTitle;

  /// No description provided for @settingsVerifyPinMessage.
  ///
  /// In en, this message translates to:
  /// **'Confirm you are the shop admin with your 6-digit PIN. Your online account is created for {email}, and we will send a 6-digit code to that address to prove it is yours.'**
  String settingsVerifyPinMessage(Object email);

  /// No description provided for @settingsVerifyPinWrong.
  ///
  /// In en, this message translates to:
  /// **'That is not the admin PIN for this shop.'**
  String get settingsVerifyPinWrong;

  /// No description provided for @settingsVerifyPinLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit admin PIN'**
  String get settingsVerifyPinLabel;

  /// No description provided for @settingsVerifyPinInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit admin PIN'**
  String get settingsVerifyPinInvalid;

  /// No description provided for @settingsVerifyCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code we emailed'**
  String get settingsVerifyCodeTitle;

  /// No description provided for @settingsVerifyCodeMessage.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {email}. It expires in {minutes} minutes.\n\nAfter you enter it, sign in with your email and the same 6-digit PIN you use on this till.'**
  String settingsVerifyCodeMessage(Object email, Object minutes);

  /// No description provided for @settingsVerifyPinLocked.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong PINs on this till. Try again in {seconds}s.'**
  String settingsVerifyPinLocked(Object seconds);

  /// No description provided for @settingsVerifyCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get settingsVerifyCodeLabel;

  /// No description provided for @settingsVerifyCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get settingsVerifyCodeInvalid;

  /// No description provided for @settingsVerifyCodeSent.
  ///
  /// In en, this message translates to:
  /// **'Code sent to {email}.'**
  String settingsVerifyCodeSent(Object email);

  /// No description provided for @settingsVerifyCodeWrong.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{That code is not right. 1 attempt left.} other{That code is not right. {count} attempts left.}}'**
  String settingsVerifyCodeWrong(num count);

  /// No description provided for @settingsVerifyCodeExpired.
  ///
  /// In en, this message translates to:
  /// **'That code has expired. Send a new one and try again.'**
  String get settingsVerifyCodeExpired;

  /// No description provided for @settingsVerifyCodeBurnt.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong attempts. Send a new code and try again.'**
  String get settingsVerifyCodeBurnt;

  /// No description provided for @settingsVerifyResendAction.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get settingsVerifyResendAction;

  /// No description provided for @settingsVerifyTooManyCodes.
  ///
  /// In en, this message translates to:
  /// **'Too many codes requested. Wait a few minutes before asking for another.'**
  String get settingsVerifyTooManyCodes;

  /// No description provided for @settingsVerifyNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'This server cannot verify emails yet. Try again later.'**
  String get settingsVerifyNotConfigured;

  /// No description provided for @settingsVerifyEmailFailed.
  ///
  /// In en, this message translates to:
  /// **'The email could not be sent. Check your connection and send a new code.'**
  String get settingsVerifyEmailFailed;

  /// No description provided for @settingsVerifyIdentityUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the account server. Try again when you have signal.'**
  String get settingsVerifyIdentityUnavailable;

  /// No description provided for @settingsVerifyShopMissing.
  ///
  /// In en, this message translates to:
  /// **'This account has no shop yet. Finish shop setup first.'**
  String get settingsVerifyShopMissing;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// No description provided for @diagnosticsRecentTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent failures'**
  String get diagnosticsRecentTitle;

  /// No description provided for @diagnosticsRecentCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 failure kept} other{{count} failures kept}} — the last {days} weeks, newer than {cap} rows are not kept'**
  String diagnosticsRecentCount(Object cap, num count, Object days);

  /// No description provided for @diagnosticsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing has gone wrong lately'**
  String get diagnosticsEmptyTitle;

  /// No description provided for @diagnosticsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'When something fails, the app records what it was doing and keeps it here. The newest failures replace the oldest, so this list never grows without limit.'**
  String get diagnosticsEmptyMessage;

  /// No description provided for @diagnosticsUnreadableTitle.
  ///
  /// In en, this message translates to:
  /// **'The failure log could not be read'**
  String get diagnosticsUnreadableTitle;

  /// No description provided for @diagnosticsUnreadableMessage.
  ///
  /// In en, this message translates to:
  /// **'The log is on this phone, but it did not open. That is itself worth reporting — refresh to try again, and send this screen to the shop\'s developer.'**
  String get diagnosticsUnreadableMessage;

  /// No description provided for @diagnosticsTrailTitle.
  ///
  /// In en, this message translates to:
  /// **'What the shop was doing'**
  String get diagnosticsTrailTitle;

  /// No description provided for @diagnosticsStackTitle.
  ///
  /// In en, this message translates to:
  /// **'Stack trace'**
  String get diagnosticsStackTitle;

  /// No description provided for @diagnosticsCopyReport.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get diagnosticsCopyReport;

  /// No description provided for @diagnosticsLedgerCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock ledger'**
  String get diagnosticsLedgerCheckTitle;

  /// No description provided for @diagnosticsLedgerCheckSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every stock count, checked against the history that produced it.'**
  String get diagnosticsLedgerCheckSubtitle;

  /// No description provided for @diagnosticsLedgerHealthy.
  ///
  /// In en, this message translates to:
  /// **'Every count agrees with its history.'**
  String get diagnosticsLedgerHealthy;

  /// No description provided for @diagnosticsLedgerChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking the stock ledger…'**
  String get diagnosticsLedgerChecking;

  /// No description provided for @diagnosticsLedgerDifferences.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 product does not agree} other{{count} products do not agree}}'**
  String diagnosticsLedgerDifferences(num count);

  /// No description provided for @diagnosticsLedgerDifferenceRow.
  ///
  /// In en, this message translates to:
  /// **'{name}: the till says {counted}, the history says {ledger}'**
  String diagnosticsLedgerDifferenceRow(
      Object counted, Object ledger, Object name);

  /// No description provided for @diagnosticsLedgerRepairAction.
  ///
  /// In en, this message translates to:
  /// **'Fix'**
  String get diagnosticsLedgerRepairAction;

  /// No description provided for @diagnosticsLedgerRepaired.
  ///
  /// In en, this message translates to:
  /// **'{name} now agrees with its history.'**
  String diagnosticsLedgerRepaired(Object name);

  /// No description provided for @diagnosticsLedgerRepairFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not correct {name}. Try again.'**
  String diagnosticsLedgerRepairFailed(Object name);

  /// No description provided for @diagnosticsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get diagnosticsClear;

  /// No description provided for @diagnosticsClearConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the failure log?'**
  String get diagnosticsClearConfirmTitle;

  /// No description provided for @diagnosticsClearConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The recorded failures will be deleted from this device. This cannot be undone.'**
  String get diagnosticsClearConfirmMessage;

  /// No description provided for @diagnosticsReportCopied.
  ///
  /// In en, this message translates to:
  /// **'Report copied to the clipboard.'**
  String get diagnosticsReportCopied;

  /// No description provided for @diagnosticsCleared.
  ///
  /// In en, this message translates to:
  /// **'Failure log cleared.'**
  String get diagnosticsCleared;

  /// No description provided for @diagnosticsRouteUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown screen'**
  String get diagnosticsRouteUnknown;

  /// No description provided for @diagnosticsActorUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown user'**
  String get diagnosticsActorUnknown;

  /// No description provided for @diagnosticsActionUnknown.
  ///
  /// In en, this message translates to:
  /// **'nothing in particular'**
  String get diagnosticsActionUnknown;

  /// No description provided for @diagnosticsEntryContext.
  ///
  /// In en, this message translates to:
  /// **'on {route} · {actor} · {action}'**
  String diagnosticsEntryContext(Object action, Object actor, Object route);

  /// No description provided for @settingsImportInventory.
  ///
  /// In en, this message translates to:
  /// **'Import inventory (.xlsx)'**
  String get settingsImportInventory;

  /// No description provided for @settingsImportStageReading.
  ///
  /// In en, this message translates to:
  /// **'Reading the workbook…'**
  String get settingsImportStageReading;

  /// No description provided for @settingsImportStageParsing.
  ///
  /// In en, this message translates to:
  /// **'Reading the rows…'**
  String get settingsImportStageParsing;

  /// No description provided for @settingsImportStageWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing the products…'**
  String get settingsImportStageWriting;

  /// No description provided for @settingsImportStageBarcodes.
  ///
  /// In en, this message translates to:
  /// **'Attaching the barcodes…'**
  String get settingsImportStageBarcodes;

  /// No description provided for @settingsImportStageVariants.
  ///
  /// In en, this message translates to:
  /// **'Attaching the variants…'**
  String get settingsImportStageVariants;

  /// No description provided for @settingsImportStageDone.
  ///
  /// In en, this message translates to:
  /// **'Done.'**
  String get settingsImportStageDone;

  /// No description provided for @settingsImportProgressPercent.
  ///
  /// In en, this message translates to:
  /// **'{stage} {percent}%'**
  String settingsImportProgressPercent(Object percent, Object stage);

  /// No description provided for @settingsImportWorkbookFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t import the workbook. Check the file and try again.'**
  String get settingsImportWorkbookFailed;

  /// No description provided for @importNotOurFormat.
  ///
  /// In en, this message translates to:
  /// **'That file isn’t in this app’s inventory format, so nothing was imported. Add a header row to the sheet — Name, Cost price, Selling price, Stock qty — or export a template from Settings and paste your rows into it.'**
  String get importNotOurFormat;

  /// No description provided for @settingsIncluded.
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get settingsIncluded;

  /// No description provided for @settingsInvalidEncryptedBackup.
  ///
  /// In en, this message translates to:
  /// **'That encrypted backup is invalid or belongs to another installation.'**
  String get settingsInvalidEncryptedBackup;

  /// No description provided for @settingsInvalidWorkbook.
  ///
  /// In en, this message translates to:
  /// **'That workbook has invalid inventory data. No products were imported.'**
  String get settingsInvalidWorkbook;

  /// No description provided for @settingsLoadShopsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the shops on this device.'**
  String get settingsLoadShopsFailed;

  /// No description provided for @settingsOneShopOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Only one shop is set up on this device. Add another here and you can move between them.'**
  String get settingsOneShopOnDevice;

  /// No description provided for @settingsCurrentShop.
  ///
  /// In en, this message translates to:
  /// **'Current shop'**
  String get settingsCurrentShop;

  /// No description provided for @settingsLinkedShop.
  ///
  /// In en, this message translates to:
  /// **'Linked to the backend'**
  String get settingsLinkedShop;

  /// No description provided for @settingsLocalOnlyShop.
  ///
  /// In en, this message translates to:
  /// **'On this device only'**
  String get settingsLocalOnlyShop;

  /// No description provided for @settingsSwitchedToShop.
  ///
  /// In en, this message translates to:
  /// **'Switched to {name}. Its stock, sales and staff are kept separate.'**
  String settingsSwitchedToShop(Object name);

  /// No description provided for @settingsMpesaMethod.
  ///
  /// In en, this message translates to:
  /// **'M-Pesa'**
  String get settingsMpesaMethod;

  /// No description provided for @settingsMpesaOffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Excluded — turn on to accept M-Pesa. Requires a one-time backend connection.'**
  String get settingsMpesaOffSubtitle;

  /// No description provided for @settingsMpesaOnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Included — customers can pay by M-Pesa STK push. Requires internet at checkout.'**
  String get settingsMpesaOnSubtitle;

  /// No description provided for @settingsMpesaUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t update M-Pesa setting — check your connection and try again.'**
  String get settingsMpesaUpdateFailed;

  /// No description provided for @settingsNoOnlineShops.
  ///
  /// In en, this message translates to:
  /// **'No online shops are linked to this identity yet.'**
  String get settingsNoOnlineShops;

  /// No description provided for @settingsPairAPrinter.
  ///
  /// In en, this message translates to:
  /// **'Pair a printer'**
  String get settingsPairAPrinter;

  /// No description provided for @settingsPairAPrinterFirst.
  ///
  /// In en, this message translates to:
  /// **'Pair a printer first.'**
  String get settingsPairAPrinterFirst;

  /// No description provided for @settingsPairAnotherPrinter.
  ///
  /// In en, this message translates to:
  /// **'Pair another'**
  String get settingsPairAnotherPrinter;

  /// No description provided for @settingsPaymentChannelId.
  ///
  /// In en, this message translates to:
  /// **'Payment channel ID'**
  String get settingsPaymentChannelId;

  /// No description provided for @settingsPaymentMethodsSection.
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get settingsPaymentMethodsSection;

  /// No description provided for @settingsPinLabel.
  ///
  /// In en, this message translates to:
  /// **'4-digit PIN'**
  String get settingsPinLabel;

  /// No description provided for @settingsPrintAfterSale.
  ///
  /// In en, this message translates to:
  /// **'Print after every sale'**
  String get settingsPrintAfterSale;

  /// No description provided for @settingsPrinterConnectionDropped.
  ///
  /// In en, this message translates to:
  /// **'The printer connection dropped. Check the printer is on, then print again.'**
  String get settingsPrinterConnectionDropped;

  /// No description provided for @settingsPrinterDisabled.
  ///
  /// In en, this message translates to:
  /// **'Printing is switched off.'**
  String get settingsPrinterDisabled;

  /// No description provided for @settingsPrinterNotPaired.
  ///
  /// In en, this message translates to:
  /// **'That printer is not paired with this phone. Pair it from the phone\'s Bluetooth settings first.'**
  String get settingsPrinterNotPaired;

  /// No description provided for @settingsPrinterPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission was turned off for {app}. Open the phone’s app settings and allow Bluetooth.'**
  String settingsPrinterPermissionDenied(Object app);

  /// No description provided for @settingsPrinterPermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'{app} needs permission to use Bluetooth. Allow it in Settings, then try again.'**
  String settingsPrinterPermissionNeeded(Object app);

  /// No description provided for @settingsPrinterSection.
  ///
  /// In en, this message translates to:
  /// **'Receipt printer'**
  String get settingsPrinterSection;

  /// No description provided for @settingsPrinterUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is switched off on this phone, or it has no Bluetooth.'**
  String get settingsPrinterUnavailable;

  /// No description provided for @settingsPrinterUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the printer. Check it is switched on and in range, then try again.'**
  String get settingsPrinterUnreachable;

  /// No description provided for @settingsPrintingEnabled.
  ///
  /// In en, this message translates to:
  /// **'Printing enabled'**
  String get settingsPrintingEnabled;

  /// No description provided for @settingsPrintingOnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This till can print receipts.'**
  String get settingsPrintingOnSubtitle;

  /// No description provided for @settingsPrintingPairedOffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Paired, but switched off. Reprints still work.'**
  String get settingsPrintingPairedOffSubtitle;

  /// No description provided for @settingsRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get settingsRemoveAction;

  /// No description provided for @settingsRemoveStaffTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove staff member?'**
  String get settingsRemoveStaffTitle;

  /// No description provided for @settingsResetPinAction.
  ///
  /// In en, this message translates to:
  /// **'Reset PIN'**
  String get settingsResetPinAction;

  /// No description provided for @settingsRestoreEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Restore encrypted backup'**
  String get settingsRestoreEncrypted;

  /// No description provided for @settingsRoleCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get settingsRoleCashier;

  /// No description provided for @settingsRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get settingsRoleLabel;

  /// No description provided for @settingsRoleManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get settingsRoleManager;

  /// No description provided for @settingsSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsSaveAction;

  /// No description provided for @settingsSeparateOfflineDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Each shop has separate offline data'**
  String get settingsSeparateOfflineDataTitle;

  /// No description provided for @settingsShopNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get settingsShopNameLabel;

  /// No description provided for @settingsShopNotOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Set this shop up on this device first'**
  String get settingsShopNotOnDevice;

  /// No description provided for @settingsSignInBeforeAddingShop.
  ///
  /// In en, this message translates to:
  /// **'Sign in as the shop admin before adding another shop.'**
  String get settingsSignInBeforeAddingShop;

  /// No description provided for @settingsStaffNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get settingsStaffNameLabel;

  /// No description provided for @settingsStaffRemovedOffline.
  ///
  /// In en, this message translates to:
  /// **'Cashier removed locally. Backend access will be updated on the next successful sync.'**
  String get settingsStaffRemovedOffline;

  /// No description provided for @settingsStaffSavedOffline.
  ///
  /// In en, this message translates to:
  /// **'Cashier saved offline. It will be linked to the backend on the next successful sync.'**
  String get settingsStaffSavedOffline;

  /// No description provided for @settingsStaffEmpty.
  ///
  /// In en, this message translates to:
  /// **'No managers or cashiers yet.'**
  String get settingsStaffEmpty;

  /// No description provided for @settingsStaffActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Actions for {name}'**
  String settingsStaffActionsTooltip(Object name);

  /// No description provided for @settingsStaffNameTaken.
  ///
  /// In en, this message translates to:
  /// **'A staff member named \"{name}\" already exists'**
  String settingsStaffNameTaken(Object name);

  /// No description provided for @settingsAddStaffFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t add staff — try again.'**
  String get settingsAddStaffFailed;

  /// No description provided for @settingsResetPinFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reset PIN — try again.'**
  String get settingsResetPinFailed;

  /// No description provided for @settingsRemoveStaffFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t remove staff — try again.'**
  String get settingsRemoveStaffFailed;

  /// No description provided for @settingsRemoveStaffMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} will no longer be able to sign in. Their past sales stay on record.'**
  String settingsRemoveStaffMessage(Object name);

  /// No description provided for @settingsConnectMpesaMessage.
  ///
  /// In en, this message translates to:
  /// **'The platform connects this shop to M-Pesa through PayHero. Enter only the shop Till or Paybill number; PayHero credentials stay on the backend. Staff continue using local PINs for the till.'**
  String get settingsConnectMpesaMessage;

  /// No description provided for @settingsPaymentChannelHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the shop Till or Paybill number. The platform registers the payment channel for you.'**
  String get settingsPaymentChannelHint;

  /// No description provided for @settingsStaffSection.
  ///
  /// In en, this message translates to:
  /// **'Managers and cashiers'**
  String get settingsStaffSection;

  /// No description provided for @settingsSwitchAction.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get settingsSwitchAction;

  /// No description provided for @settingsSwitchShopAction.
  ///
  /// In en, this message translates to:
  /// **'Switch linked shop'**
  String get settingsSwitchShopAction;

  /// No description provided for @settingsSwitchShopFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not switch shops'**
  String get settingsSwitchShopFailed;

  /// No description provided for @settingsSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed — try again when you have signal.'**
  String get settingsSyncFailed;

  /// No description provided for @settingsSyncNowAction.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get settingsSyncNowAction;

  /// No description provided for @settingsSyncOfflineExcel.
  ///
  /// In en, this message translates to:
  /// **'No internet — saved an Excel file instead. Share it from the prompt that opened.'**
  String get settingsSyncOfflineExcel;

  /// No description provided for @settingsSyncSection.
  ///
  /// In en, this message translates to:
  /// **'Sync — Google Sheets & Excel'**
  String get settingsSyncSection;

  /// No description provided for @settingsSyncSheets.
  ///
  /// In en, this message translates to:
  /// **'Synced to Google Sheets just now.'**
  String get settingsSyncSheets;

  /// No description provided for @settingsSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get settingsSyncing;

  /// No description provided for @settingsTestPrintAction.
  ///
  /// In en, this message translates to:
  /// **'Test print'**
  String get settingsTestPrintAction;

  /// No description provided for @settingsTestReceiptSent.
  ///
  /// In en, this message translates to:
  /// **'Test receipt sent.'**
  String get settingsTestReceiptSent;

  /// No description provided for @settingsVerifyAction.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get settingsVerifyAction;

  /// No description provided for @settingsShopReady.
  ///
  /// In en, this message translates to:
  /// **'{name} is ready. Your admin account and PIN carried across.'**
  String settingsShopReady(Object name);

  /// No description provided for @settingsPaperRoll.
  ///
  /// In en, this message translates to:
  /// **'{size}mm roll'**
  String settingsPaperRoll(Object size);

  /// No description provided for @settingsTaxSummary.
  ///
  /// In en, this message translates to:
  /// **'VAT {rate}% · receipts numbered {till}-000001'**
  String settingsTaxSummary(Object rate, Object till);

  /// No description provided for @settingsTaxSummaryWithTin.
  ///
  /// In en, this message translates to:
  /// **'VAT {rate}% · TIN {tin} · receipts numbered {till}-000001'**
  String settingsTaxSummaryWithTin(Object rate, Object till, Object tin);

  /// No description provided for @settingsRestoredProducts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Restored 1 product} other{Restored {count} products}}'**
  String settingsRestoredProducts(num count);

  /// No description provided for @settingsImportedProducts.
  ///
  /// In en, this message translates to:
  /// **'{products, plural, =1{Imported 1 product} other{Imported {products} products}}'**
  String settingsImportedProducts(num products);

  /// No description provided for @settingsImportedProductsWithRefused.
  ///
  /// In en, this message translates to:
  /// **'{products, plural, =1{Imported 1 product.} other{Imported {products} products.}} {refused}: {detail}'**
  String settingsImportedProductsWithRefused(
      Object detail, num products, Object refused);

  /// No description provided for @settingsBarcodesRefusedList.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 barcode} other{{count} barcodes}} were already on another product'**
  String settingsBarcodesRefusedList(num count);

  /// No description provided for @settingsNoPairedPrinters.
  ///
  /// In en, this message translates to:
  /// **'No Bluetooth printers are paired with this phone. Pair one from the phone\'s Bluetooth settings, then try again.'**
  String get settingsNoPairedPrinters;

  /// No description provided for @settingsPairingCancelled.
  ///
  /// In en, this message translates to:
  /// **'Pairing was cancelled. Pair the printer from the phone\'s Bluetooth settings, then try again.'**
  String get settingsPairingCancelled;

  /// No description provided for @settingsPrinterPaired.
  ///
  /// In en, this message translates to:
  /// **'{name} paired.'**
  String settingsPrinterPaired(Object name);

  /// No description provided for @settingsResetPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset PIN for {name}'**
  String settingsResetPinTitle(Object name);

  /// No description provided for @settingsPinResetFor.
  ///
  /// In en, this message translates to:
  /// **'PIN reset for {name}'**
  String settingsPinResetFor(Object name);

  /// No description provided for @settingsRoleAdminFull.
  ///
  /// In en, this message translates to:
  /// **'{role} (full rights)'**
  String settingsRoleAdminFull(Object role);

  /// No description provided for @settingsVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'v{version}'**
  String settingsVersionLabel(Object version);

  /// No description provided for @settingsYourShopsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your shops'**
  String get settingsYourShopsTitle;

  /// No description provided for @settingsBusinessProfile.
  ///
  /// In en, this message translates to:
  /// **'Business profile'**
  String get settingsBusinessProfile;

  /// No description provided for @settingsBusinessProfileChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change business profile'**
  String get settingsBusinessProfileChangeTitle;

  /// No description provided for @settingsBusinessProfileChangeWarning.
  ///
  /// In en, this message translates to:
  /// **'This changes navigation and terminology for this shop. Existing sales, stock, tax snapshots, cash balances and financial results stay unchanged.'**
  String get settingsBusinessProfileChangeWarning;

  /// No description provided for @settingsBusinessProfileChangeAction.
  ///
  /// In en, this message translates to:
  /// **'Apply profile'**
  String get settingsBusinessProfileChangeAction;

  /// No description provided for @settingsBusinessProfileChanged.
  ///
  /// In en, this message translates to:
  /// **'Business profile changed to {profile}'**
  String settingsBusinessProfileChanged(Object profile);

  /// No description provided for @settingsBusinessProfilePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'What will change'**
  String get settingsBusinessProfilePreviewTitle;

  /// No description provided for @settingsBusinessProfilePreviewNavigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation: {before} → {after}'**
  String settingsBusinessProfilePreviewNavigation(Object after, Object before);

  /// No description provided for @settingsBusinessProfilePreviewTerminology.
  ///
  /// In en, this message translates to:
  /// **'Product wording: {before} → {after}'**
  String settingsBusinessProfilePreviewTerminology(Object after, Object before);

  /// No description provided for @settingsBusinessProfileStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get settingsBusinessProfileStock;

  /// No description provided for @settingsBusinessProfileMoneyFirst.
  ///
  /// In en, this message translates to:
  /// **'Money-first records'**
  String get settingsBusinessProfileMoneyFirst;

  /// No description provided for @activityProfileChanged.
  ///
  /// In en, this message translates to:
  /// **'Business profile changed'**
  String get activityProfileChanged;

  /// No description provided for @transactionsExpenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Expense · {category}'**
  String transactionsExpenseTitle(Object category);

  /// No description provided for @transactionsExpenseSourceTill.
  ///
  /// In en, this message translates to:
  /// **'Till cash'**
  String get transactionsExpenseSourceTill;

  /// No description provided for @transactionsExpenseSourceOther.
  ///
  /// In en, this message translates to:
  /// **'Other funds'**
  String get transactionsExpenseSourceOther;

  /// No description provided for @shotCupsActionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Cup actions'**
  String get shotCupsActionsLabel;

  /// No description provided for @shotCupsAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add a cup'**
  String get shotCupsAddAction;

  /// No description provided for @shotCupsCapacityHelper.
  ///
  /// In en, this message translates to:
  /// **'Leave it empty if you do not know the size. With a size, the app works out what each cup cost you to pour.'**
  String get shotCupsCapacityHelper;

  /// No description provided for @shotCupsCapacityHint.
  ///
  /// In en, this message translates to:
  /// **'30'**
  String get shotCupsCapacityHint;

  /// No description provided for @shotCupsCapacityLabel.
  ///
  /// In en, this message translates to:
  /// **'Size in ml (optional)'**
  String get shotCupsCapacityLabel;

  /// No description provided for @shotCupsCapacityMax.
  ///
  /// In en, this message translates to:
  /// **'Capacity must be {max} ml or less.'**
  String shotCupsCapacityMax(Object max);

  /// No description provided for @shotCupsCapacityPositive.
  ///
  /// In en, this message translates to:
  /// **'The size cannot be less than zero.'**
  String get shotCupsCapacityPositive;

  /// No description provided for @shotCupsCapacityValue.
  ///
  /// In en, this message translates to:
  /// **'{capacity} ml'**
  String shotCupsCapacityValue(Object capacity);

  /// No description provided for @shotCupsCapacityWholeMl.
  ///
  /// In en, this message translates to:
  /// **'Capacity must be whole millilitres, for example 30 or 45.'**
  String get shotCupsCapacityWholeMl;

  /// No description provided for @shotCupsCardName.
  ///
  /// In en, this message translates to:
  /// **'{label} · {capacity} ml'**
  String shotCupsCardName(Object capacity, Object label);

  /// No description provided for @shotCupsCardSpoken.
  ///
  /// In en, this message translates to:
  /// **'{name}, {detail}, {price}'**
  String shotCupsCardSpoken(Object detail, Object name, Object price);

  /// No description provided for @shotCupsCardSpokenInactive.
  ///
  /// In en, this message translates to:
  /// **'{name}, {detail}, {price}, not sold'**
  String shotCupsCardSpokenInactive(Object detail, Object name, Object price);

  /// No description provided for @shotCupsChooseDrink.
  ///
  /// In en, this message translates to:
  /// **'Choose the drink this cup is poured from.'**
  String get shotCupsChooseDrink;

  /// No description provided for @shotCupsDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Small cup'**
  String get shotCupsDefaultName;

  /// No description provided for @shotCupsEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get shotCupsEditAction;

  /// No description provided for @shotCupsEmptyMessageNoPermission.
  ///
  /// In en, this message translates to:
  /// **'No cups have been set up for this shop.'**
  String get shotCupsEmptyMessageNoPermission;

  /// No description provided for @shotCupsEmptyMessageOwner.
  ///
  /// In en, this message translates to:
  /// **'Add one to sell fixed-size cups of any drink in your inventory.'**
  String get shotCupsEmptyMessageOwner;

  /// No description provided for @shotCupsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No cups yet'**
  String get shotCupsEmptyTitle;

  /// No description provided for @shotCupsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load the cups. Try again.'**
  String get shotCupsLoadFailed;

  /// No description provided for @shotCupsNameAtTillLabel.
  ///
  /// In en, this message translates to:
  /// **'Name at the till'**
  String get shotCupsNameAtTillLabel;

  /// No description provided for @shotCupsNameHelper.
  ///
  /// In en, this message translates to:
  /// **'What the cashier taps'**
  String get shotCupsNameHelper;

  /// No description provided for @shotCupsNameHint.
  ///
  /// In en, this message translates to:
  /// **'Small cup, Big cup'**
  String get shotCupsNameHint;

  /// No description provided for @shotCupsNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Give the cup a name, like Small cup or Big cup.'**
  String get shotCupsNameRequired;

  /// No description provided for @shotCupsNotSold.
  ///
  /// In en, this message translates to:
  /// **'Not sold'**
  String get shotCupsNotSold;

  /// No description provided for @shotCupsPerBottle.
  ///
  /// In en, this message translates to:
  /// **'{count} cups per bottle'**
  String shotCupsPerBottle(Object count);

  /// No description provided for @shotCupsPouredFromLabel.
  ///
  /// In en, this message translates to:
  /// **'Poured from'**
  String get shotCupsPouredFromLabel;

  /// No description provided for @shotCupsPriceHelper.
  ///
  /// In en, this message translates to:
  /// **'For one cup'**
  String get shotCupsPriceHelper;

  /// No description provided for @shotCupsPriceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Price must be a number, 0 or more.'**
  String get shotCupsPriceInvalid;

  /// No description provided for @shotCupsPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Price (KSh)'**
  String get shotCupsPriceLabel;

  /// No description provided for @shotCupsRetryLoading.
  ///
  /// In en, this message translates to:
  /// **'Try loading again'**
  String get shotCupsRetryLoading;

  /// No description provided for @shotCupsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save the cup. Try again.'**
  String get shotCupsSaveFailed;

  /// No description provided for @shotCupsStopSellingAction.
  ///
  /// In en, this message translates to:
  /// **'Stop selling'**
  String get shotCupsStopSellingAction;

  /// No description provided for @shotCupsStopSellingMessage.
  ///
  /// In en, this message translates to:
  /// **'{product} cups stop appearing at the till. Sales already recorded are untouched.'**
  String shotCupsStopSellingMessage(Object product);

  /// No description provided for @shotCupsStopSellingTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop selling {name}?'**
  String shotCupsStopSellingTitle(Object name);

  /// No description provided for @shotCupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Cups'**
  String get shotCupsTitle;

  /// No description provided for @taxSettingsAdminOnly.
  ///
  /// In en, this message translates to:
  /// **'Only the shop admin can change tax settings.'**
  String get taxSettingsAdminOnly;

  /// No description provided for @taxSettingsVatRateLine.
  ///
  /// In en, this message translates to:
  /// **'VAT rate {percent}%'**
  String taxSettingsVatRateLine(Object percent);

  /// No description provided for @taxSettingsVatRateSpoken.
  ///
  /// In en, this message translates to:
  /// **'VAT rate {percent} percent'**
  String taxSettingsVatRateSpoken(Object percent);

  /// No description provided for @taxSettingsWorkedExample.
  ///
  /// In en, this message translates to:
  /// **'A KSh 100 sale carries KSh {vat} VAT, leaving KSh {net} net.'**
  String taxSettingsWorkedExample(Object net, Object vat);

  /// No description provided for @taxSettingsPricesIncludeVatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'On: you type the shelf price and VAT is extracted from it. Off: you type the net price and VAT is added on top.'**
  String get taxSettingsPricesIncludeVatSubtitle;

  /// No description provided for @taxSettingsTillCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'Receipts are numbered {tillCode}-000001, and KRA needs that number to match the sequence it has on file. Give each till its own code.'**
  String taxSettingsTillCodeHelp(Object tillCode);

  /// No description provided for @taxSettingsEtimsOnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'On — every sale is filed with KRA. Sales keep working with no signal; receipts upload as soon as there is a connection.'**
  String get taxSettingsEtimsOnSubtitle;

  /// No description provided for @taxSettingsEtimsOffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Off — sales are recorded and VAT reports remain available. KRA eTIMS is not activated.'**
  String get taxSettingsEtimsOffSubtitle;

  /// No description provided for @taxSettingsTinNotRegisteredHelp.
  ///
  /// In en, this message translates to:
  /// **'Receipts cannot be issued until this shop\'s KRA PIN is registered. Until then, sales are recorded but no tax invoice is issued.'**
  String get taxSettingsTinNotRegisteredHelp;

  /// No description provided for @taxSettingsWaitForReceiptsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Queued automatically after every sale while online. Sales never wait for it.'**
  String get taxSettingsWaitForReceiptsSubtitle;

  /// No description provided for @taxSettingsTillCodeDialogHelp.
  ///
  /// In en, this message translates to:
  /// **'Letters and digits only. Every till in a shop needs its own code, because KRA rejects two tills issuing the same receipt number.'**
  String get taxSettingsTillCodeDialogHelp;

  /// No description provided for @taxSettingsKraPinDialogHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter the PIN exactly as printed on this shop\'s KRA certificate, including the P0 prefix. A PIN issued to the wrong business puts invoices on someone else\'s return.'**
  String get taxSettingsKraPinDialogHelp;

  /// No description provided for @taxSettingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Check the phone has storage free.'**
  String get taxSettingsSaveFailed;

  /// No description provided for @taxSettingsApplyAction.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get taxSettingsApplyAction;

  /// No description provided for @taxSettingsChangeAction.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get taxSettingsChangeAction;

  /// No description provided for @taxSettingsEtimsOff.
  ///
  /// In en, this message translates to:
  /// **'eTIMS receipts switched off'**
  String get taxSettingsEtimsOff;

  /// No description provided for @taxSettingsEtimsOn.
  ///
  /// In en, this message translates to:
  /// **'eTIMS receipts switched on'**
  String get taxSettingsEtimsOn;

  /// No description provided for @taxSettingsEtimsSection.
  ///
  /// In en, this message translates to:
  /// **'Tax reporting'**
  String get taxSettingsEtimsSection;

  /// No description provided for @taxSettingsEtimsUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t update eTIMS. Check your connection and try again.'**
  String get taxSettingsEtimsUpdateFailed;

  /// No description provided for @taxSettingsEtimsNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Link this shop to the backend before switching eTIMS on.'**
  String get taxSettingsEtimsNotLinked;

  /// No description provided for @taxSettingsIssueEtimsTitle.
  ///
  /// In en, this message translates to:
  /// **'Issue tax receipts'**
  String get taxSettingsIssueEtimsTitle;

  /// No description provided for @taxSettingsKraPinTitle.
  ///
  /// In en, this message translates to:
  /// **'KRA taxpayer PIN'**
  String get taxSettingsKraPinTitle;

  /// No description provided for @taxSettingsKraUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach KRA. Check the shop is linked and you have a connection, then try again.'**
  String get taxSettingsKraUnreachable;

  /// No description provided for @taxSettingsKraUnreachableRetry.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach KRA. Try again when you have a connection.'**
  String get taxSettingsKraUnreachableRetry;

  /// No description provided for @taxSettingsNotActivatedStatus.
  ///
  /// In en, this message translates to:
  /// **'KRA eTIMS not activated'**
  String get taxSettingsNotActivatedStatus;

  /// No description provided for @taxSettingsNotActivatedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Risiti by PesaStack Limited is the planned provider. Activation stays off until the shop is onboarded and approved.'**
  String get taxSettingsNotActivatedSubtitle;

  /// No description provided for @taxSettingsPricesIncludeVat.
  ///
  /// In en, this message translates to:
  /// **'Prices include VAT'**
  String get taxSettingsPricesIncludeVat;

  /// No description provided for @taxSettingsReceiptNumberingSection.
  ///
  /// In en, this message translates to:
  /// **'Receipt numbering'**
  String get taxSettingsReceiptNumberingSection;

  /// No description provided for @taxSettingsRegisterAction.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get taxSettingsRegisterAction;

  /// No description provided for @taxSettingsRegisterPinFirst.
  ///
  /// In en, this message translates to:
  /// **'Register your KRA taxpayer PIN first.'**
  String get taxSettingsRegisterPinFirst;

  /// No description provided for @taxSettingsRegisteredDevice.
  ///
  /// In en, this message translates to:
  /// **'Registered device'**
  String get taxSettingsRegisteredDevice;

  /// No description provided for @taxSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get taxSettingsSaved;

  /// No description provided for @taxSettingsTillCode.
  ///
  /// In en, this message translates to:
  /// **'Till code'**
  String get taxSettingsTillCode;

  /// No description provided for @taxSettingsTillCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one letter or digit'**
  String get taxSettingsTillCodeRequired;

  /// No description provided for @taxSettingsTinLabel.
  ///
  /// In en, this message translates to:
  /// **'TIN (PIN)'**
  String get taxSettingsTinLabel;

  /// No description provided for @taxSettingsTinNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'TIN not registered'**
  String get taxSettingsTinNotRegistered;

  /// No description provided for @taxSettingsTinRegisteredHelp.
  ///
  /// In en, this message translates to:
  /// **'Invoices are issued against this PIN.'**
  String get taxSettingsTinRegisteredHelp;

  /// No description provided for @taxSettingsTinTooShort.
  ///
  /// In en, this message translates to:
  /// **'A TIN is at least 4 characters'**
  String get taxSettingsTinTooShort;

  /// No description provided for @taxSettingsTinInvalid.
  ///
  /// In en, this message translates to:
  /// **'A KRA PIN is A or P, nine digits, then one letter.'**
  String get taxSettingsTinInvalid;

  /// No description provided for @taxSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tax settings'**
  String get taxSettingsTitle;

  /// No description provided for @taxSettingsVatExempt.
  ///
  /// In en, this message translates to:
  /// **'Exempt — receipts omit the VAT line entirely.'**
  String get taxSettingsVatExempt;

  /// No description provided for @taxSettingsVatSection.
  ///
  /// In en, this message translates to:
  /// **'Value Added Tax'**
  String get taxSettingsVatSection;

  /// No description provided for @taxSettingsWaitForReceipts.
  ///
  /// In en, this message translates to:
  /// **'Wait for receipts to be issued'**
  String get taxSettingsWaitForReceipts;

  /// No description provided for @variantAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add variant'**
  String get variantAddTitle;

  /// No description provided for @variantBarcodeHelper.
  ///
  /// In en, this message translates to:
  /// **'Scanning this adds this variant, not the product'**
  String get variantBarcodeHelper;

  /// No description provided for @variantBarcodeHint.
  ///
  /// In en, this message translates to:
  /// **'6001234567892'**
  String get variantBarcodeHint;

  /// No description provided for @variantBarcodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Barcode (optional)'**
  String get variantBarcodeLabel;

  /// No description provided for @variantCostPriceHelper.
  ///
  /// In en, this message translates to:
  /// **'Empty keeps {amount}'**
  String variantCostPriceHelper(Object amount);

  /// No description provided for @variantCostPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Cost price'**
  String get variantCostPriceLabel;

  /// No description provided for @variantCostPriceNotANumber.
  ///
  /// In en, this message translates to:
  /// **'Cost price must be a number, or empty to use {amount}'**
  String variantCostPriceNotANumber(Object amount);

  /// No description provided for @variantCostPriceNotNegative.
  ///
  /// In en, this message translates to:
  /// **'Cost price must be 0 or more'**
  String get variantCostPriceNotNegative;

  /// No description provided for @variantCountableNote.
  ///
  /// In en, this message translates to:
  /// **'Countable — no serving size. One bottle is one Dark.'**
  String get variantCountableNote;

  /// No description provided for @variantEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit variant'**
  String get variantEditTitle;

  /// No description provided for @variantNameHint.
  ///
  /// In en, this message translates to:
  /// **'Dark, Regular, Big cup'**
  String get variantNameHint;

  /// No description provided for @variantNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get variantNameLabel;

  /// No description provided for @variantNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Give the variant a name, like Dark or Big cup'**
  String get variantNameRequired;

  /// No description provided for @variantNameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Name must be {max} characters or fewer'**
  String variantNameTooLong(Object max);

  /// No description provided for @variantReorderLevelHelper.
  ///
  /// In en, this message translates to:
  /// **'Warn at or below'**
  String get variantReorderLevelHelper;

  /// No description provided for @variantReorderLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Reorder level'**
  String get variantReorderLevelLabel;

  /// No description provided for @variantReorderLevelNotNegative.
  ///
  /// In en, this message translates to:
  /// **'Reorder level must be 0 or more'**
  String get variantReorderLevelNotNegative;

  /// No description provided for @variantSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save variant'**
  String get variantSaveAction;

  /// No description provided for @variantSellPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Sell price'**
  String get variantSellPriceLabel;

  /// No description provided for @variantSellPriceNotANumber.
  ///
  /// In en, this message translates to:
  /// **'Selling price must be a number'**
  String get variantSellPriceNotANumber;

  /// No description provided for @variantSellPriceNotNegative.
  ///
  /// In en, this message translates to:
  /// **'Selling price must be 0 or more'**
  String get variantSellPriceNotNegative;

  /// No description provided for @variantSizeHelper.
  ///
  /// In en, this message translates to:
  /// **'Millilitres or litres — 500ml, 0.5L, 1.5 L.'**
  String get variantSizeHelper;

  /// No description provided for @variantSizeLeaveBlankHelper.
  ///
  /// In en, this message translates to:
  /// **'Leave blank if it isn\'t sold by volume'**
  String get variantSizeLeaveBlankHelper;

  /// No description provided for @variantSizeHintLitre.
  ///
  /// In en, this message translates to:
  /// **'0.5L'**
  String get variantSizeHintLitre;

  /// No description provided for @variantSizeHintMillilitre.
  ///
  /// In en, this message translates to:
  /// **'500ml'**
  String get variantSizeHintMillilitre;

  /// No description provided for @variantSizeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Size must be a number, optionally with ml or L — for example 500ml'**
  String get variantSizeInvalid;

  /// No description provided for @variantSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Serving size'**
  String get variantSizeLabel;

  /// No description provided for @variantSizeRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the serving size, for example 500ml'**
  String get variantSizeRequired;

  /// No description provided for @variantSizeSuggestionsSpoken.
  ///
  /// In en, this message translates to:
  /// **'Cup sizes you have used before'**
  String get variantSizeSuggestionsSpoken;

  /// No description provided for @variantSkuHelper.
  ///
  /// In en, this message translates to:
  /// **'Your own reference for this variant'**
  String get variantSkuHelper;

  /// No description provided for @variantSkuLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock-keeping code (optional)'**
  String get variantSkuLabel;

  /// No description provided for @variantStartingStockHelper.
  ///
  /// In en, this message translates to:
  /// **'How many you have now'**
  String get variantStartingStockHelper;

  /// No description provided for @variantStartingStockLabel.
  ///
  /// In en, this message translates to:
  /// **'Starting stock'**
  String get variantStartingStockLabel;

  /// No description provided for @variantUnitCup.
  ///
  /// In en, this message translates to:
  /// **'Per cup'**
  String get variantUnitCup;

  /// No description provided for @variantUnitEach.
  ///
  /// In en, this message translates to:
  /// **'Each (countable)'**
  String get variantUnitEach;

  /// No description provided for @variantUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Measured in'**
  String get variantUnitLabel;

  /// No description provided for @variantUnitLitre.
  ///
  /// In en, this message translates to:
  /// **'Per litre'**
  String get variantUnitLitre;

  /// No description provided for @variantUnitMillilitre.
  ///
  /// In en, this message translates to:
  /// **'Per millilitre'**
  String get variantUnitMillilitre;

  /// No description provided for @chooserSignedInShop.
  ///
  /// In en, this message translates to:
  /// **'Signed-in shop: {shop}'**
  String chooserSignedInShop(Object shop);

  /// No description provided for @chooserHeading.
  ///
  /// In en, this message translates to:
  /// **'Choose how you want to start'**
  String get chooserHeading;

  /// No description provided for @chooserHasShopWarning.
  ///
  /// In en, this message translates to:
  /// **'This device already runs a shop. Setting up again adds a second one, on the same admin account and the same PIN.'**
  String get chooserHasShopWarning;

  /// No description provided for @chooserSignInAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get chooserSignInAction;

  /// No description provided for @chooserSignInAsStaffAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in as staff'**
  String get chooserSignInAsStaffAction;

  /// No description provided for @chooserSetupAnother.
  ///
  /// In en, this message translates to:
  /// **'Set up another shop on this device'**
  String get chooserSetupAnother;

  /// No description provided for @chooserSetupFirst.
  ///
  /// In en, this message translates to:
  /// **'Set up a shop on this device'**
  String get chooserSetupFirst;

  /// No description provided for @chooserSignInHelp.
  ///
  /// In en, this message translates to:
  /// **'Cashiers, managers and admins all sign in with the PIN their shop gave them.'**
  String get chooserSignInHelp;

  /// No description provided for @loginRoleAdmins.
  ///
  /// In en, this message translates to:
  /// **'Admins'**
  String get loginRoleAdmins;

  /// No description provided for @loginRoleManagers.
  ///
  /// In en, this message translates to:
  /// **'Managers'**
  String get loginRoleManagers;

  /// No description provided for @loginRoleCashiers.
  ///
  /// In en, this message translates to:
  /// **'Cashiers'**
  String get loginRoleCashiers;

  /// No description provided for @loginRoleAccountsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No accounts} =1{1 account} other{{count} accounts}}'**
  String loginRoleAccountsCount(num count);

  /// No description provided for @chooserSetupHelp.
  ///
  /// In en, this message translates to:
  /// **'A shop admin sets this device up once. After that, everyone signs in with the PIN they are given. No internet is needed.'**
  String get chooserSetupHelp;

  /// No description provided for @chartNothingToShow.
  ///
  /// In en, this message translates to:
  /// **'Nothing to show yet.'**
  String get chartNothingToShow;

  /// No description provided for @chartSpokenNoValues.
  ///
  /// In en, this message translates to:
  /// **'{title}. No values.'**
  String chartSpokenNoValues(Object title);

  /// No description provided for @chartSpokenPeak.
  ///
  /// In en, this message translates to:
  /// **'{title}. {count, plural, =1{1 value} other{{count} values}}. Highest is {peak} at {value}.'**
  String chartSpokenPeak(num count, Object peak, Object title, Object value);

  /// No description provided for @chartSpokenSelected.
  ///
  /// In en, this message translates to:
  /// **'{title}. Selected {label}. {value}.'**
  String chartSpokenSelected(Object label, Object title, Object value);

  /// No description provided for @chartSpokenBar.
  ///
  /// In en, this message translates to:
  /// **'{label}, {value}'**
  String chartSpokenBar(Object label, Object value);

  /// No description provided for @variantAllSizesLabel.
  ///
  /// In en, this message translates to:
  /// **'All sizes'**
  String get variantAllSizesLabel;

  /// No description provided for @variantOneVariantLabel.
  ///
  /// In en, this message translates to:
  /// **'One variant'**
  String get variantOneVariantLabel;

  /// No description provided for @backupLaterAction.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get backupLaterAction;

  /// No description provided for @backupNowAction.
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backupNowAction;

  /// No description provided for @backupFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Backup could not be completed. Check storage and try again.'**
  String get backupFailedMessage;

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get scanTitle;

  /// No description provided for @scanHoldInsideFrame.
  ///
  /// In en, this message translates to:
  /// **'Hold the barcode inside the frame'**
  String get scanHoldInsideFrame;

  /// No description provided for @scanUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'The camera is not available'**
  String get scanUnavailableTitle;

  /// No description provided for @scanUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'You can still sell this product. Search for it by name on the Sell screen, or use a Bluetooth or USB barcode scanner, which types the code straight into the till.'**
  String get scanUnavailableMessage;

  /// No description provided for @scanBackToSelling.
  ///
  /// In en, this message translates to:
  /// **'Back to selling'**
  String get scanBackToSelling;

  /// No description provided for @scanRetryCamera.
  ///
  /// In en, this message translates to:
  /// **'Try camera again'**
  String get scanRetryCamera;

  /// No description provided for @scanPointAtBarcode.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the barcode'**
  String get scanPointAtBarcode;

  /// No description provided for @scanCodesRead.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 code read} other{{count} codes read}}'**
  String scanCodesRead(num count);

  /// No description provided for @scanDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get scanDone;

  /// No description provided for @scanEnterCodeManually.
  ///
  /// In en, this message translates to:
  /// **'Enter code manually'**
  String get scanEnterCodeManually;

  /// No description provided for @scanFlashOnTooltip.
  ///
  /// In en, this message translates to:
  /// **'Turn the flash on'**
  String get scanFlashOnTooltip;

  /// No description provided for @scanFlashOffTooltip.
  ///
  /// In en, this message translates to:
  /// **'Turn the flash off'**
  String get scanFlashOffTooltip;

  /// No description provided for @scanPermissionDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera access is off'**
  String get scanPermissionDeniedTitle;

  /// No description provided for @scanPermissionDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'The camera needs permission to read a barcode. Turn camera access on for this app in your phone\'s settings, then try again.'**
  String get scanPermissionDeniedMessage;

  /// No description provided for @scanManualTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter barcode'**
  String get scanManualTitle;

  /// No description provided for @scanManualLabel.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get scanManualLabel;

  /// No description provided for @scanManualHint.
  ///
  /// In en, this message translates to:
  /// **'Type the digits printed under the barcode'**
  String get scanManualHint;

  /// No description provided for @scanManualAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get scanManualAdd;

  /// No description provided for @scanManualInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'That is not a barcode this till can read'**
  String get scanManualInvalidCode;

  /// No description provided for @signOutTitleNamed.
  ///
  /// In en, this message translates to:
  /// **'Sign out {name}'**
  String signOutTitleNamed(Object name);

  /// No description provided for @signOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOutTitle;

  /// No description provided for @signOutDetail.
  ///
  /// In en, this message translates to:
  /// **'The PIN pad comes back for the next person.'**
  String get signOutDetail;

  /// No description provided for @signOutCartWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You have 1 item in the cart} other{You have {count} items in the cart}}'**
  String signOutCartWarningTitle(num count);

  /// No description provided for @signOutCartWarningDetail.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been charged, and signing out clears the cart.'**
  String get signOutCartWarningDetail;

  /// No description provided for @signOutShiftWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Your shift is still open'**
  String get signOutShiftWarningTitle;

  /// No description provided for @signOutShiftWarningDetail.
  ///
  /// In en, this message translates to:
  /// **'The cash you started with is still counted against your shift. You can sign out and reconcile later, but the shift stays open until someone closes it.'**
  String get signOutShiftWarningDetail;

  /// No description provided for @signOutStayAction.
  ///
  /// In en, this message translates to:
  /// **'Stay signed in'**
  String get signOutStayAction;

  /// No description provided for @signOutConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOutConfirmAction;

  /// No description provided for @signOutWarningSpoken.
  ///
  /// In en, this message translates to:
  /// **'{title}. {detail}'**
  String signOutWarningSpoken(Object detail, Object title);

  /// No description provided for @sellScanHintSearchProducts.
  ///
  /// In en, this message translates to:
  /// **'Search products...'**
  String get sellScanHintSearchProducts;

  /// No description provided for @sellEnterValidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number'**
  String get sellEnterValidPhone;

  /// No description provided for @sellTotalOnly.
  ///
  /// In en, this message translates to:
  /// **'Total:'**
  String get sellTotalOnly;

  /// No description provided for @sellScanVariantOnlyMessage.
  ///
  /// In en, this message translates to:
  /// **'{product} is sold as variants, so its own barcode is not enough. Scan one of its variant barcodes, or tap the product to choose.'**
  String sellScanVariantOnlyMessage(Object product);

  /// No description provided for @sellScanVariantOutOfStockMessage.
  ///
  /// In en, this message translates to:
  /// **'{variant} is out of stock.'**
  String sellScanVariantOutOfStockMessage(Object variant);

  /// No description provided for @sellNoVariantsYetHint.
  ///
  /// In en, this message translates to:
  /// **'Add them in Inventory, for example Dark, Regular or Big cup, and they will appear here.'**
  String get sellNoVariantsYetHint;

  /// No description provided for @sellPourOptionTitle.
  ///
  /// In en, this message translates to:
  /// **'{label} · {ml} ml'**
  String sellPourOptionTitle(Object label, Object ml);

  /// No description provided for @settingsBackupsErased.
  ///
  /// In en, this message translates to:
  /// **'Local encrypted backups and their key were erased.'**
  String get settingsBackupsErased;

  /// No description provided for @settingsPaymentChannelIdRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a numeric Till or Paybill number'**
  String get settingsPaymentChannelIdRequired;

  /// No description provided for @settingsCloseAction.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get settingsCloseAction;

  /// No description provided for @inventoryRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {product} from inventory?'**
  String inventoryRemoveTitle(Object product);

  /// No description provided for @inventoryCostPriceNotANumber.
  ///
  /// In en, this message translates to:
  /// **'Cost price must be a number'**
  String get inventoryCostPriceNotANumber;

  /// No description provided for @inventorySellPriceNotANumber.
  ///
  /// In en, this message translates to:
  /// **'Sell price must be a number'**
  String get inventorySellPriceNotANumber;

  /// No description provided for @inventoryStockNotANumber.
  ///
  /// In en, this message translates to:
  /// **'Stock must be a number'**
  String get inventoryStockNotANumber;

  /// No description provided for @inventoryNoVariantsHelper.
  ///
  /// In en, this message translates to:
  /// **'No variants yet. The till will ask for one instead of selling the whole product.'**
  String get inventoryNoVariantsHelper;

  /// No description provided for @inventoryStockIsDerived.
  ///
  /// In en, this message translates to:
  /// **'The variants\' total, kept in step for you'**
  String get inventoryStockIsDerived;

  /// No description provided for @dashboardStaffNameSince.
  ///
  /// In en, this message translates to:
  /// **'{staffName}, since {startTime}'**
  String dashboardStaffNameSince(Object staffName, Object startTime);

  /// No description provided for @dashboardSalesToday.
  ///
  /// In en, this message translates to:
  /// **'Sales today · {scopeLabel}'**
  String dashboardSalesToday(Object scopeLabel);

  /// No description provided for @dashboardSee.
  ///
  /// In en, this message translates to:
  /// **'See all {totalCount}'**
  String dashboardSee(Object totalCount);

  /// No description provided for @dashboardSalesLabel.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get dashboardSalesLabel;

  /// No description provided for @dashboardProfitLabel.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get dashboardProfitLabel;

  /// No description provided for @dashboardAverageSaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Average sale'**
  String get dashboardAverageSaleLabel;

  /// No description provided for @dashboardLowStockNoun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{product low} other{products low}}'**
  String dashboardLowStockNoun(num count);

  /// No description provided for @dashboardExpectedInDrawer.
  ///
  /// In en, this message translates to:
  /// **'Expected in drawer'**
  String get dashboardExpectedInDrawer;

  /// No description provided for @dashboardNoShiftMessage.
  ///
  /// In en, this message translates to:
  /// **'No shift open. Sales still record, but they will not appear in a shift report.'**
  String get dashboardNoShiftMessage;

  /// No description provided for @dashboardOpenShiftAction.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get dashboardOpenShiftAction;

  /// No description provided for @dashboardOpenShiftSpoken.
  ///
  /// In en, this message translates to:
  /// **'Open shift since {since}. Expected in drawer {expected}. Open the shift.'**
  String dashboardOpenShiftSpoken(Object expected, Object since);

  /// No description provided for @dashboardReorderSection.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get dashboardReorderSection;

  /// No description provided for @dashboardUnitsInStock.
  ///
  /// In en, this message translates to:
  /// **'{qty} in stock'**
  String dashboardUnitsInStock(Object qty);

  /// No description provided for @analyticsAgainstDaysBefore.
  ///
  /// In en, this message translates to:
  /// **'against the {days} days before'**
  String analyticsAgainstDaysBefore(Object days);

  /// No description provided for @dashboardId.
  ///
  /// In en, this message translates to:
  /// **'{id}'**
  String dashboardId(Object id);

  /// No description provided for @loginName.
  ///
  /// In en, this message translates to:
  /// **'{name}, {roleLabel}'**
  String loginName(Object name, Object roleLabel);

  /// No description provided for @loginFilledPINDigitsEntered.
  ///
  /// In en, this message translates to:
  /// **'{filled} of {length} PIN digits entered'**
  String loginFilledPINDigitsEntered(Object filled, Object length);

  /// No description provided for @loginDigit.
  ///
  /// In en, this message translates to:
  /// **'Digit {digit}'**
  String loginDigit(Object digit);

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'{label} is required'**
  String fieldRequired(Object label);

  /// No description provided for @loginSignInAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginSignInAction;

  /// No description provided for @approvalTitle.
  ///
  /// In en, this message translates to:
  /// **'Manager approval'**
  String get approvalTitle;

  /// No description provided for @approvalWrongPin.
  ///
  /// In en, this message translates to:
  /// **'That PIN is not the one on file. Try again.'**
  String get approvalWrongPin;

  /// No description provided for @approvalNoManagers.
  ///
  /// In en, this message translates to:
  /// **'Nobody can approve this yet: add a manager or use the owner sign-in.'**
  String get approvalNoManagers;

  /// No description provided for @approvalPinLabel.
  ///
  /// In en, this message translates to:
  /// **'Your 6-digit PIN'**
  String get approvalPinLabel;

  /// No description provided for @approvalConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approvalConfirmAction;

  /// No description provided for @roleNameOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleNameOwner;

  /// No description provided for @roleNameManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get roleNameManager;

  /// No description provided for @roleNameCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get roleNameCashier;

  /// No description provided for @sellPaymentOnAccount.
  ///
  /// In en, this message translates to:
  /// **'On account'**
  String get sellPaymentOnAccount;

  /// No description provided for @sellCreditNoCustomer.
  ///
  /// In en, this message translates to:
  /// **'Tap to choose the customer'**
  String get sellCreditNoCustomer;

  /// No description provided for @sellCreditPickCustomer.
  ///
  /// In en, this message translates to:
  /// **'Who takes this on account?'**
  String get sellCreditPickCustomer;

  /// No description provided for @sellCreditOverLimit.
  ///
  /// In en, this message translates to:
  /// **'{name} would owe {total}.'**
  String sellCreditOverLimit(Object name, Object total);

  /// No description provided for @sellCreditOverLimitAsk.
  ///
  /// In en, this message translates to:
  /// **'{name} would owe {total}.'**
  String sellCreditOverLimitAsk(Object name, Object total);

  /// No description provided for @customerAddInlineAction.
  ///
  /// In en, this message translates to:
  /// **'Add a new customer'**
  String get customerAddInlineAction;

  /// No description provided for @customerSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer saved'**
  String get customerSavedTitle;

  /// No description provided for @customerAddedMessage.
  ///
  /// In en, this message translates to:
  /// **'The customer is on the list.'**
  String get customerAddedMessage;

  /// No description provided for @customerEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get customerEditAction;

  /// No description provided for @customersTitle.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customersTitle;

  /// No description provided for @creditOwedToYou.
  ///
  /// In en, this message translates to:
  /// **'Owed to you'**
  String get creditOwedToYou;

  /// No description provided for @creditOwedByCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No one owes anything} =1{One customer owes} other{{count} customers owe}}'**
  String creditOwedByCount(num count);

  /// No description provided for @creditAging7.
  ///
  /// In en, this message translates to:
  /// **'0–7 days'**
  String get creditAging7;

  /// No description provided for @creditAging30.
  ///
  /// In en, this message translates to:
  /// **'8–30 days'**
  String get creditAging30;

  /// No description provided for @creditAging60.
  ///
  /// In en, this message translates to:
  /// **'31–60 days'**
  String get creditAging60;

  /// No description provided for @creditAgingOver.
  ///
  /// In en, this message translates to:
  /// **'60+ days'**
  String get creditAgingOver;

  /// No description provided for @customersFilterOwes.
  ///
  /// In en, this message translates to:
  /// **'Owes money'**
  String get customersFilterOwes;

  /// No description provided for @customersSortName.
  ///
  /// In en, this message translates to:
  /// **'By name'**
  String get customersSortName;

  /// No description provided for @customerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or number'**
  String get customerSearchHint;

  /// No description provided for @customersEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No customers yet'**
  String get customersEmptyTitle;

  /// No description provided for @customersEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Sell on account and the till keeps the balance here instead of on paper.'**
  String get customersEmptyMessage;

  /// No description provided for @customersNoMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get customersNoMatchesTitle;

  /// No description provided for @customersNoMatchesMessage.
  ///
  /// In en, this message translates to:
  /// **'Nobody matches that search.'**
  String get customersNoMatchesMessage;

  /// No description provided for @customerOwesChip.
  ///
  /// In en, this message translates to:
  /// **'Owes {amount}'**
  String customerOwesChip(Object amount);

  /// No description provided for @customerCreditChip.
  ///
  /// In en, this message translates to:
  /// **'Credit with them {amount}'**
  String customerCreditChip(Object amount);

  /// No description provided for @customerAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add customer'**
  String get customerAddAction;

  /// No description provided for @customerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get customerNameLabel;

  /// No description provided for @customerLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Credit limit (KSh)'**
  String get customerLimitLabel;

  /// No description provided for @customerLimitHelper.
  ///
  /// In en, this message translates to:
  /// **'Blank uses the shop default.'**
  String get customerLimitHelper;

  /// No description provided for @customerLimitInvalid.
  ///
  /// In en, this message translates to:
  /// **'A limit is a number of shillings.'**
  String get customerLimitInvalid;

  /// No description provided for @customerNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get customerNotesLabel;

  /// No description provided for @customerSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save customer'**
  String get customerSaveAction;

  /// No description provided for @customerBalanceOwedHeading.
  ///
  /// In en, this message translates to:
  /// **'Owed to the shop'**
  String get customerBalanceOwedHeading;

  /// No description provided for @customerBalanceCreditHeading.
  ///
  /// In en, this message translates to:
  /// **'In credit with the shop'**
  String get customerBalanceCreditHeading;

  /// No description provided for @customerBalanceClearHeading.
  ///
  /// In en, this message translates to:
  /// **'Nothing owed'**
  String get customerBalanceClearHeading;

  /// No description provided for @customerBalanceLimitHeading.
  ///
  /// In en, this message translates to:
  /// **'Limit {limit}. Room {headroom}.'**
  String customerBalanceLimitHeading(Object headroom, Object limit);

  /// No description provided for @customerAddPayment.
  ///
  /// In en, this message translates to:
  /// **'Add payment'**
  String get customerAddPayment;

  /// No description provided for @customerRemindAction.
  ///
  /// In en, this message translates to:
  /// **'Remind'**
  String get customerRemindAction;

  /// No description provided for @customerStatementAction.
  ///
  /// In en, this message translates to:
  /// **'Statement'**
  String get customerStatementAction;

  /// No description provided for @customerDeactivateAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get customerDeactivateAction;

  /// No description provided for @customerDeactivateError.
  ///
  /// In en, this message translates to:
  /// **'{message}'**
  String customerDeactivateError(Object message);

  /// No description provided for @creditDeactivateFailed.
  ///
  /// In en, this message translates to:
  /// **'{message}'**
  String creditDeactivateFailed(Object message);

  /// No description provided for @customerReminderFailed.
  ///
  /// In en, this message translates to:
  /// **'There is no app that could open the message.'**
  String get customerReminderFailed;

  /// No description provided for @creditHistoryLabel.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get creditHistoryLabel;

  /// No description provided for @creditHistoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this account yet'**
  String get creditHistoryEmptyTitle;

  /// No description provided for @creditHistoryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'A sale on account or a first payment starts the history.'**
  String get creditHistoryEmptyMessage;

  /// No description provided for @creditEntryCharge.
  ///
  /// In en, this message translates to:
  /// **'Bought on account'**
  String get creditEntryCharge;

  /// No description provided for @creditEntryPayment.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get creditEntryPayment;

  /// No description provided for @creditEntryAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Corrected'**
  String get creditEntryAdjustment;

  /// No description provided for @creditEntryWriteoff.
  ///
  /// In en, this message translates to:
  /// **'Written off'**
  String get creditEntryWriteoff;

  /// No description provided for @creditEntryReturn.
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get creditEntryReturn;

  /// No description provided for @customerStatementTitle.
  ///
  /// In en, this message translates to:
  /// **'Statement — {name}'**
  String customerStatementTitle(Object name);

  /// No description provided for @customerStatementBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance: {balance}'**
  String customerStatementBalance(Object balance);

  /// No description provided for @customerStatementShareHint.
  ///
  /// In en, this message translates to:
  /// **'Copy the text, then paste it wherever the customer will read it.'**
  String get customerStatementShareHint;

  /// No description provided for @customerCopyStatement.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get customerCopyStatement;

  /// No description provided for @creditPaymentOwes.
  ///
  /// In en, this message translates to:
  /// **'Currently owes {amount}'**
  String creditPaymentOwes(Object amount);

  /// No description provided for @creditPaymentAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'The amount being paid'**
  String get creditPaymentAmountLabel;

  /// No description provided for @creditPaymentAmountHelper.
  ///
  /// In en, this message translates to:
  /// **'The full balance is pre-filled.'**
  String get creditPaymentAmountHelper;

  /// No description provided for @creditPaymentAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'A payment is more than zero.'**
  String get creditPaymentAmountInvalid;

  /// No description provided for @creditPaymentCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get creditPaymentCash;

  /// No description provided for @creditPaymentMpesa.
  ///
  /// In en, this message translates to:
  /// **'M-Pesa'**
  String get creditPaymentMpesa;

  /// No description provided for @creditPaymentCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'M-Pesa code'**
  String get creditPaymentCodeLabel;

  /// No description provided for @creditPaymentConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Take the payment'**
  String get creditPaymentConfirmAction;

  /// No description provided for @creditPaymentTaken.
  ///
  /// In en, this message translates to:
  /// **'{name} paid {amount}.'**
  String creditPaymentTaken(Object amount, Object name);

  /// No description provided for @creditRepaymentTakenTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment taken'**
  String get creditRepaymentTakenTitle;

  /// No description provided for @activityCreditRepayment.
  ///
  /// In en, this message translates to:
  /// **'Credit payment taken'**
  String get activityCreditRepayment;

  /// No description provided for @activityCreditAdjusted.
  ///
  /// In en, this message translates to:
  /// **'Credit account adjusted'**
  String get activityCreditAdjusted;

  /// No description provided for @loginPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get loginPinLabel;

  /// No description provided for @analyticsYourSalesTitle.
  ///
  /// In en, this message translates to:
  /// **'Your sales'**
  String get analyticsYourSalesTitle;

  /// No description provided for @receiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive stock'**
  String get receiveTitle;

  /// No description provided for @receiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record what arrived and what you paid for it.'**
  String get receiveSubtitle;

  /// No description provided for @receiveSupplierLabel.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get receiveSupplierLabel;

  /// No description provided for @receiveNoSupplier.
  ///
  /// In en, this message translates to:
  /// **'No supplier'**
  String get receiveNoSupplier;

  /// No description provided for @receiveSupplierRefLabel.
  ///
  /// In en, this message translates to:
  /// **'Invoice or delivery note number'**
  String get receiveSupplierRefLabel;

  /// No description provided for @receiveSupplierRefHint.
  ///
  /// In en, this message translates to:
  /// **'The number on the supplier\'s paper.'**
  String get receiveSupplierRefHint;

  /// No description provided for @receiveLinesLabel.
  ///
  /// In en, this message translates to:
  /// **'What arrived'**
  String get receiveLinesLabel;

  /// No description provided for @receiveAddProductAction.
  ///
  /// In en, this message translates to:
  /// **'Add a product'**
  String get receiveAddProductAction;

  /// No description provided for @receiveQtyLabel.
  ///
  /// In en, this message translates to:
  /// **'How many'**
  String get receiveQtyLabel;

  /// No description provided for @receiveUnitCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Cost each (KSh)'**
  String get receiveUnitCostLabel;

  /// No description provided for @receiveLineTotal.
  ///
  /// In en, this message translates to:
  /// **'Line total: {total}'**
  String receiveLineTotal(Object total);

  /// No description provided for @receiveTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'What the delivery cost'**
  String get receiveTotalLabel;

  /// No description provided for @receivePostAction.
  ///
  /// In en, this message translates to:
  /// **'Post it'**
  String get receivePostAction;

  /// No description provided for @receiveRemoveLineAction.
  ///
  /// In en, this message translates to:
  /// **'Remove this line'**
  String get receiveRemoveLineAction;

  /// No description provided for @receiveSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search the catalogue'**
  String get receiveSearchLabel;

  /// No description provided for @receiveAlreadyOn.
  ///
  /// In en, this message translates to:
  /// **'Already on this delivery: {count}'**
  String receiveAlreadyOn(Object count);

  /// No description provided for @receiveNoLines.
  ///
  /// In en, this message translates to:
  /// **'Add at least one thing that arrived.'**
  String get receiveNoLines;

  /// No description provided for @receiveFailed.
  ///
  /// In en, this message translates to:
  /// **'The delivery could not be recorded. Nothing has changed.'**
  String get receiveFailed;

  /// No description provided for @receiveDone.
  ///
  /// In en, this message translates to:
  /// **'The stock is on the shelf and the costs are up to date.'**
  String get receiveDone;

  /// No description provided for @receiveAddSupplierAction.
  ///
  /// In en, this message translates to:
  /// **'Add a supplier'**
  String get receiveAddSupplierAction;

  /// No description provided for @receiveDraftRestored.
  ///
  /// In en, this message translates to:
  /// **'A half-finished delivery was brought back.'**
  String get receiveDraftRestored;

  /// No description provided for @receiveDraftDiscarded.
  ///
  /// In en, this message translates to:
  /// **'The half-finished delivery was thrown away.'**
  String get receiveDraftDiscarded;

  /// No description provided for @receiveDraftDiscardAction.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get receiveDraftDiscardAction;

  /// No description provided for @receiveDraftDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this half-finished delivery?'**
  String get receiveDraftDiscardTitle;

  /// No description provided for @receiveDraftDiscardMessage.
  ///
  /// In en, this message translates to:
  /// **'What you scanned in goes away for good. The stock and the costs are untouched.'**
  String get receiveDraftDiscardMessage;

  /// No description provided for @receiveDraftDiscardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard it'**
  String get receiveDraftDiscardConfirm;

  /// No description provided for @receiveDraftAction.
  ///
  /// In en, this message translates to:
  /// **'Resume delivery'**
  String get receiveDraftAction;

  /// No description provided for @receiveQtyValue.
  ///
  /// In en, this message translates to:
  /// **'{qty}'**
  String receiveQtyValue(Object qty);

  /// No description provided for @receiveDeliveriesAction.
  ///
  /// In en, this message translates to:
  /// **'Deliveries'**
  String get receiveDeliveriesAction;

  /// No description provided for @receiveHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Deliveries'**
  String get receiveHistoryTitle;

  /// No description provided for @receiveHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No deliveries recorded yet. Receiving stock gets you one here.'**
  String get receiveHistoryEmpty;

  /// No description provided for @receiveReceiptCost.
  ///
  /// In en, this message translates to:
  /// **'Cost {total}'**
  String receiveReceiptCost(Object total);

  /// No description provided for @receiveViewAction.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get receiveViewAction;

  /// No description provided for @supplierAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a supplier'**
  String get supplierAddTitle;

  /// No description provided for @supplierAddSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The name of the shop or person you buy from, and the number to order on.'**
  String get supplierAddSubtitle;

  /// No description provided for @supplierNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Supplier name'**
  String get supplierNameLabel;

  /// No description provided for @supplierNameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Enter the supplier\'s name.'**
  String get supplierNameTooShort;

  /// No description provided for @supplierNameAlreadyOnList.
  ///
  /// In en, this message translates to:
  /// **'That supplier is already on the list.'**
  String get supplierNameAlreadyOnList;

  /// No description provided for @supplierPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get supplierPhoneLabel;

  /// No description provided for @supplierPhoneHelper.
  ///
  /// In en, this message translates to:
  /// **'For ordering later. 07…, 01… or 254…'**
  String get supplierPhoneHelper;

  /// No description provided for @supplierPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'That is not a Kenyan number. Use 07…, 01…, +254… or 254…'**
  String get supplierPhoneInvalid;

  /// No description provided for @supplierSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save supplier'**
  String get supplierSaveAction;

  /// No description provided for @supplierSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'{message}'**
  String supplierSaveFailed(Object message);

  /// No description provided for @receiveVoidAction.
  ///
  /// In en, this message translates to:
  /// **'Void delivery'**
  String get receiveVoidAction;

  /// No description provided for @receiveVoidTitle.
  ///
  /// In en, this message translates to:
  /// **'Void this delivery?'**
  String get receiveVoidTitle;

  /// No description provided for @receiveVoidMessage.
  ///
  /// In en, this message translates to:
  /// **'The stock it brought goes back off the shelf, and its cost comes off the history. This cannot be undone.'**
  String get receiveVoidMessage;

  /// No description provided for @receiveVoidConfirm.
  ///
  /// In en, this message translates to:
  /// **'Void delivery'**
  String get receiveVoidConfirm;

  /// No description provided for @receiveVoided.
  ///
  /// In en, this message translates to:
  /// **'The delivery was voided. The stock went back off the shelf.'**
  String get receiveVoided;

  /// No description provided for @receiveVoidFailed.
  ///
  /// In en, this message translates to:
  /// **'{message}'**
  String receiveVoidFailed(Object message);

  /// No description provided for @receiveVoidedBy.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get receiveVoidedBy;

  /// No description provided for @transactionsReturnedBadge.
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get transactionsReturnedBadge;

  /// No description provided for @transactionsPartlyReturnedBadge.
  ///
  /// In en, this message translates to:
  /// **'Partly returned'**
  String get transactionsPartlyReturnedBadge;

  /// No description provided for @returnTitle.
  ///
  /// In en, this message translates to:
  /// **'Return items'**
  String get returnTitle;

  /// No description provided for @returnHistoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Already returned'**
  String get returnHistoryLabel;

  /// No description provided for @returnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose what is coming back, say why, and choose how the money goes back.'**
  String get returnSubtitle;

  /// No description provided for @returnReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Why is it coming back?'**
  String get returnReasonLabel;

  /// No description provided for @returnReasonHint.
  ///
  /// In en, this message translates to:
  /// **'For example: the customer changed their mind.'**
  String get returnReasonHint;

  /// No description provided for @returnMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'How should the money go back?'**
  String get returnMethodLabel;

  /// No description provided for @returnMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get returnMethodCash;

  /// No description provided for @returnMethodMpesa.
  ///
  /// In en, this message translates to:
  /// **'M-Pesa'**
  String get returnMethodMpesa;

  /// No description provided for @returnRefundLabel.
  ///
  /// In en, this message translates to:
  /// **'Money to give back'**
  String get returnRefundLabel;

  /// No description provided for @returnConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Give it back'**
  String get returnConfirmAction;

  /// No description provided for @returnNoLines.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one thing to give back.'**
  String get returnNoLines;

  /// No description provided for @returnReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Say why it is coming back.'**
  String get returnReasonRequired;

  /// No description provided for @returnFailed.
  ///
  /// In en, this message translates to:
  /// **'The return could not be recorded. Nothing has changed.'**
  String get returnFailed;

  /// No description provided for @returnNoShiftOpen.
  ///
  /// In en, this message translates to:
  /// **'Open a shift first, so the money can come out of the drawer.'**
  String get returnNoShiftOpen;

  /// No description provided for @returnUnverifiedPayment.
  ///
  /// In en, this message translates to:
  /// **'That payment was never confirmed, so it cannot be given back yet.'**
  String get returnUnverifiedPayment;

  /// No description provided for @returnMoreThanSold.
  ///
  /// In en, this message translates to:
  /// **'More was returned than was sold on that line.'**
  String get returnMoreThanSold;

  /// No description provided for @returnLineGone.
  ///
  /// In en, this message translates to:
  /// **'That line is no longer on the sale.'**
  String get returnLineGone;

  /// No description provided for @returnLineAllReturned.
  ///
  /// In en, this message translates to:
  /// **'All returned'**
  String get returnLineAllReturned;

  /// No description provided for @returnLineRemaining.
  ///
  /// In en, this message translates to:
  /// **'{qty} left'**
  String returnLineRemaining(Object qty);

  /// No description provided for @returnRestockLabel.
  ///
  /// In en, this message translates to:
  /// **'Put it back on the shelf'**
  String get returnRestockLabel;

  /// No description provided for @returnWriteOffLabel.
  ///
  /// In en, this message translates to:
  /// **'Write it off (damaged or expired)'**
  String get returnWriteOffLabel;

  /// No description provided for @returnLessAction.
  ///
  /// In en, this message translates to:
  /// **'Return less'**
  String get returnLessAction;

  /// No description provided for @returnMoreAction.
  ///
  /// In en, this message translates to:
  /// **'Return more'**
  String get returnMoreAction;

  /// No description provided for @returnDone.
  ///
  /// In en, this message translates to:
  /// **'Returned. The money is on its way back.'**
  String get returnDone;

  /// No description provided for @analyticsShiftsSection.
  ///
  /// In en, this message translates to:
  /// **'Shifts'**
  String get analyticsShiftsSection;

  /// No description provided for @analyticsShiftsCount.
  ///
  /// In en, this message translates to:
  /// **'Shifts'**
  String get analyticsShiftsCount;

  /// No description provided for @analyticsShiftsClosed.
  ///
  /// In en, this message translates to:
  /// **'{closed} closed'**
  String analyticsShiftsClosed(Object closed);

  /// No description provided for @analyticsShiftsExpected.
  ///
  /// In en, this message translates to:
  /// **'Cash expected'**
  String get analyticsShiftsExpected;

  /// No description provided for @analyticsShiftsCounted.
  ///
  /// In en, this message translates to:
  /// **'Cash counted'**
  String get analyticsShiftsCounted;

  /// No description provided for @analyticsNoShifts.
  ///
  /// In en, this message translates to:
  /// **'No shifts in this period'**
  String get analyticsNoShifts;

  /// No description provided for @analyticsNoShiftsHint.
  ///
  /// In en, this message translates to:
  /// **'When a shift is opened and counted, it appears here with what the drawer should have held and what was actually in it.'**
  String get analyticsNoShiftsHint;

  /// No description provided for @loginChooseShopTitle.
  ///
  /// In en, this message translates to:
  /// **'Which shop are you opening?'**
  String get loginChooseShopTitle;

  /// No description provided for @loginChooseShopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This phone has {count} shops. Choose the one you are working in.'**
  String loginChooseShopSubtitle(Object count);

  /// No description provided for @loginChooseShopAction.
  ///
  /// In en, this message translates to:
  /// **'Choose a different shop'**
  String get loginChooseShopAction;

  /// No description provided for @loginCurrentShopLabel.
  ///
  /// In en, this message translates to:
  /// **'Now signing in to {shop}'**
  String loginCurrentShopLabel(Object shop);

  /// No description provided for @backToPinPadAction.
  ///
  /// In en, this message translates to:
  /// **'Back to PIN pad'**
  String get backToPinPadAction;

  /// No description provided for @staffLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in as staff'**
  String get staffLoginTitle;

  /// No description provided for @staffUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get staffUsernameLabel;

  /// No description provided for @staffPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get staffPasswordLabel;

  /// No description provided for @loginWrongCredentials.
  ///
  /// In en, this message translates to:
  /// **'Wrong username or password'**
  String get loginWrongCredentials;

  /// No description provided for @loginNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the shop server. Try again.'**
  String get loginNetworkError;

  /// No description provided for @permissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your till'**
  String get permissionsTitle;

  /// No description provided for @permissionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'These two let the till do its job. You can skip either one and change it later in Settings.'**
  String get permissionsSubtitle;

  /// No description provided for @permissionsCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get permissionsCameraTitle;

  /// No description provided for @permissionsCameraWhy.
  ///
  /// In en, this message translates to:
  /// **'Scan barcodes with the handset camera, and photograph a product for its tile.'**
  String get permissionsCameraWhy;

  /// No description provided for @permissionsBluetoothTitle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get permissionsBluetoothTitle;

  /// No description provided for @permissionsBluetoothWhy.
  ///
  /// In en, this message translates to:
  /// **'Send receipts to a Bluetooth receipt printer.'**
  String get permissionsBluetoothWhy;

  /// No description provided for @permissionsAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get permissionsAllow;

  /// No description provided for @permissionsAllowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get permissionsAllowed;

  /// No description provided for @permissionsOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get permissionsOpenSettings;

  /// No description provided for @permissionsContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get permissionsContinue;

  /// No description provided for @permissionsOptionalNote.
  ///
  /// In en, this message translates to:
  /// **'None of these are required. A till with a barcode scanner and no camera can still sell everything.'**
  String get permissionsOptionalNote;

  /// No description provided for @permissionsMatrixTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissionsMatrixTitle;

  /// No description provided for @permissionsMatrixOwnerOnly.
  ///
  /// In en, this message translates to:
  /// **'Only the owner can change permissions.'**
  String get permissionsMatrixOwnerOnly;

  /// No description provided for @permissionsMatrixRolePermissions.
  ///
  /// In en, this message translates to:
  /// **'Role permissions'**
  String get permissionsMatrixRolePermissions;

  /// No description provided for @permissionsMatrixManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get permissionsMatrixManager;

  /// No description provided for @permissionsMatrixCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get permissionsMatrixCashier;

  /// No description provided for @permissionsMatrixStaffOverrides.
  ///
  /// In en, this message translates to:
  /// **'Staff overrides'**
  String get permissionsMatrixStaffOverrides;

  /// No description provided for @permissionsMatrixStaffMember.
  ///
  /// In en, this message translates to:
  /// **'Staff member'**
  String get permissionsMatrixStaffMember;

  /// No description provided for @permissionsMatrixNoOverride.
  ///
  /// In en, this message translates to:
  /// **'No individual override'**
  String get permissionsMatrixNoOverride;

  /// No description provided for @permissionsMatrixIndividualOverride.
  ///
  /// In en, this message translates to:
  /// **'Individual override'**
  String get permissionsMatrixIndividualOverride;

  /// No description provided for @permissionsMatrixRoleDefault.
  ///
  /// In en, this message translates to:
  /// **'Uses role default'**
  String get permissionsMatrixRoleDefault;

  /// No description provided for @permissionsMatrixReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to role default'**
  String get permissionsMatrixReset;

  /// No description provided for @permissionsMatrixAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get permissionsMatrixAllow;

  /// No description provided for @permissionsMatrixApproval.
  ///
  /// In en, this message translates to:
  /// **'Approval'**
  String get permissionsMatrixApproval;

  /// No description provided for @permissionsMatrixDeny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get permissionsMatrixDeny;

  /// No description provided for @blackbeeSeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Seed BlackBee products'**
  String get blackbeeSeedTitle;

  /// No description provided for @blackbeeSeedAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get blackbeeSeedAdded;

  /// No description provided for @blackbeeSeedPriceRequired.
  ///
  /// In en, this message translates to:
  /// **'Price and selling price required'**
  String get blackbeeSeedPriceRequired;

  /// No description provided for @incomingPaymentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Incoming M-Pesa'**
  String get incomingPaymentsTitle;

  /// No description provided for @incomingPaymentsManagerOnly.
  ///
  /// In en, this message translates to:
  /// **'Only a manager can view incoming payments.'**
  String get incomingPaymentsManagerOnly;

  /// No description provided for @incomingPaymentsUnclaimed.
  ///
  /// In en, this message translates to:
  /// **'Unclaimed'**
  String get incomingPaymentsUnclaimed;

  /// No description provided for @incomingPaymentsClaimed.
  ///
  /// In en, this message translates to:
  /// **'Claimed'**
  String get incomingPaymentsClaimed;

  /// No description provided for @incomingPaymentsIgnored.
  ///
  /// In en, this message translates to:
  /// **'Ignored'**
  String get incomingPaymentsIgnored;

  /// No description provided for @incomingPaymentsDisputed.
  ///
  /// In en, this message translates to:
  /// **'Disputed'**
  String get incomingPaymentsDisputed;

  /// No description provided for @incomingPaymentsNewNotice.
  ///
  /// In en, this message translates to:
  /// **'New unclaimed M-Pesa payment received.'**
  String get incomingPaymentsNewNotice;

  /// No description provided for @incomingPaymentsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Incoming payments could not be loaded.'**
  String get incomingPaymentsLoadFailed;

  /// No description provided for @incomingPaymentsSetAsideTitle.
  ///
  /// In en, this message translates to:
  /// **'Set payment aside'**
  String get incomingPaymentsSetAsideTitle;

  /// No description provided for @incomingPaymentsReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get incomingPaymentsReason;

  /// No description provided for @incomingPaymentsSetAsideAction.
  ///
  /// In en, this message translates to:
  /// **'Set aside'**
  String get incomingPaymentsSetAsideAction;

  /// No description provided for @incomingPaymentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No payments here.'**
  String get incomingPaymentsEmpty;

  /// No description provided for @incomingPaymentsSetAsideFailed.
  ///
  /// In en, this message translates to:
  /// **'The payment could not be set aside.'**
  String get incomingPaymentsSetAsideFailed;

  /// No description provided for @onboardingImportedProducts.
  ///
  /// In en, this message translates to:
  /// **'Imported {products} products.'**
  String onboardingImportedProducts(Object products);

  /// No description provided for @ownerLabelRequired.
  ///
  /// In en, this message translates to:
  /// **'{label} is required'**
  String ownerLabelRequired(Object label);

  /// No description provided for @reportsShowingSales.
  ///
  /// In en, this message translates to:
  /// **'Showing {length} of {unfilteredCount} sales.'**
  String reportsShowingSales(Object length, Object unfilteredCount);

  /// No description provided for @reportsChange.
  ///
  /// In en, this message translates to:
  /// **'change {amount}'**
  String reportsChange(Object amount);

  /// No description provided for @reportsStaffName.
  ///
  /// In en, this message translates to:
  /// **'{staffName}, {detail}, {amount}'**
  String reportsStaffName(Object amount, Object detail, Object staffName);

  /// No description provided for @reportsExpectedTill.
  ///
  /// In en, this message translates to:
  /// **'Expected in till {amount}'**
  String reportsExpectedTill(Object amount);

  /// No description provided for @taxVatRatePercent.
  ///
  /// In en, this message translates to:
  /// **'{vatRatePercent}%'**
  String taxVatRatePercent(Object vatRatePercent);

  /// No description provided for @taxTaxpayerPIN.
  ///
  /// In en, this message translates to:
  /// **'Taxpayer PIN {tin}'**
  String taxTaxpayerPIN(Object tin);

  /// No description provided for @inventoryStockqtyStock.
  ///
  /// In en, this message translates to:
  /// **'{stockqty} in stock'**
  String inventoryStockqtyStock(Object stockqty);

  /// No description provided for @inventoryNameStock.
  ///
  /// In en, this message translates to:
  /// **'{name}, {amount}, {stockqty} in stock'**
  String inventoryNameStock(Object amount, Object name, Object stockqty);

  /// No description provided for @inventoryBarcodeAlready.
  ///
  /// In en, this message translates to:
  /// **'That barcode is already on {name}.'**
  String inventoryBarcodeAlready(Object name);

  /// No description provided for @inventoryEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String inventoryEdit(Object name);

  /// No description provided for @inventoryBarcodeAlreadyUsedAnother.
  ///
  /// In en, this message translates to:
  /// **'Barcode {code} is already used by another product or variant.'**
  String inventoryBarcodeAlreadyUsedAnother(Object code);

  /// No description provided for @inventoryBarcodeAlready2.
  ///
  /// In en, this message translates to:
  /// **'Barcode {code} is already on {name}.'**
  String inventoryBarcodeAlready2(Object code, Object name);

  /// No description provided for @inventoryLabelMustNumberEmpty.
  ///
  /// In en, this message translates to:
  /// **'{label} must be a number, or empty if not sold in portions'**
  String inventoryLabelMustNumberEmpty(Object label);

  /// No description provided for @inventoryLabelMust0.
  ///
  /// In en, this message translates to:
  /// **'{label} must be 0 or more'**
  String inventoryLabelMust0(Object label);

  /// No description provided for @inventoryRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove {barcode}'**
  String inventoryRemove(Object barcode);

  /// No description provided for @inventoryQuantity.
  ///
  /// In en, this message translates to:
  /// **'{quantity}'**
  String inventoryQuantity(Object quantity);

  /// No description provided for @dashboardGreetingAnonymous.
  ///
  /// In en, this message translates to:
  /// **'{greeting}.'**
  String dashboardGreetingAnonymous(Object greeting);

  /// No description provided for @dashboardGreetingNamed.
  ///
  /// In en, this message translates to:
  /// **'{greeting}, {name}.'**
  String dashboardGreetingNamed(Object greeting, Object name);

  /// No description provided for @dashboardScopeShop.
  ///
  /// In en, this message translates to:
  /// **'the whole shop'**
  String get dashboardScopeShop;

  /// No description provided for @dashboardScopeOwn.
  ///
  /// In en, this message translates to:
  /// **'just you'**
  String get dashboardScopeOwn;

  /// No description provided for @dashboardGreetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get dashboardGreetingMorning;

  /// No description provided for @dashboardGreetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get dashboardGreetingAfternoon;

  /// No description provided for @dashboardGreetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get dashboardGreetingEvening;

  /// No description provided for @dashboardSalesByHour.
  ///
  /// In en, this message translates to:
  /// **'Sales by hour'**
  String get dashboardSalesByHour;

  /// No description provided for @dashboardPeakHourSpoken.
  ///
  /// In en, this message translates to:
  /// **'Busiest at {hour}, {amount}.'**
  String dashboardPeakHourSpoken(Object amount, Object hour);

  /// No description provided for @dashboardNoSalesTitle.
  ///
  /// In en, this message translates to:
  /// **'No sales today'**
  String get dashboardNoSalesTitle;

  /// No description provided for @dashboardNoSalesTodayBody.
  ///
  /// In en, this message translates to:
  /// **'That\'s normal if you haven\'t opened yet.'**
  String get dashboardNoSalesTodayBody;

  /// No description provided for @dashboardNoSalesFirstBody.
  ///
  /// In en, this message translates to:
  /// **'Sales will appear here as soon as the first sale goes through the till.'**
  String get dashboardNoSalesFirstBody;

  /// No description provided for @liveStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get liveStatusConnected;

  /// No description provided for @liveStatusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated {when}'**
  String liveStatusUpdated(Object when);

  /// No description provided for @liveStatusJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get liveStatusJustNow;

  /// No description provided for @liveStatusMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}} ago'**
  String liveStatusMinutes(num count);

  /// No description provided for @liveStatusHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour} other{{count} hours}} ago'**
  String liveStatusHours(num count);

  /// No description provided for @liveStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get liveStatusConnecting;

  /// No description provided for @liveStatusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get liveStatusReconnecting;

  /// No description provided for @dashboardAllClear.
  ///
  /// In en, this message translates to:
  /// **'All clear'**
  String get dashboardAllClear;

  /// No description provided for @analyticsTransactionCaption.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transaction} other{{count} transactions}}'**
  String analyticsTransactionCaption(num count);

  /// No description provided for @analyticsMarginCaption.
  ///
  /// In en, this message translates to:
  /// **'{margin}% margin'**
  String analyticsMarginCaption(Object margin);

  /// No description provided for @analyticsAvgBasketCaption.
  ///
  /// In en, this message translates to:
  /// **'per sale'**
  String get analyticsAvgBasketCaption;

  /// No description provided for @analyticsSalesLabel.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get analyticsSalesLabel;

  /// No description provided for @analyticsTopProductsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 product sold} other{{count} products sold}}'**
  String analyticsTopProductsCount(num count);

  /// No description provided for @saleDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sale details'**
  String get saleDetailsTitle;

  /// No description provided for @saleDetailsWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get saleDetailsWhen;

  /// No description provided for @saleDetailsWhere.
  ///
  /// In en, this message translates to:
  /// **'Where'**
  String get saleDetailsWhere;

  /// No description provided for @saleDetailsHow.
  ///
  /// In en, this message translates to:
  /// **'How it was paid'**
  String get saleDetailsHow;

  /// No description provided for @saleDetailsWho.
  ///
  /// In en, this message translates to:
  /// **'Who sold it'**
  String get saleDetailsWho;

  /// No description provided for @saleDetailsWhat.
  ///
  /// In en, this message translates to:
  /// **'What was sold'**
  String get saleDetailsWhat;

  /// No description provided for @saleDetailsNoItems.
  ///
  /// In en, this message translates to:
  /// **'No items were recorded on this sale.'**
  String get saleDetailsNoItems;

  /// No description provided for @saleDetailsReference.
  ///
  /// In en, this message translates to:
  /// **'Reference {reference}'**
  String saleDetailsReference(Object reference);

  /// No description provided for @saleDetailsTendered.
  ///
  /// In en, this message translates to:
  /// **'Tendered {tendered} · change {change}'**
  String saleDetailsTendered(Object change, Object tendered);

  /// No description provided for @saleDetailsQuantity.
  ///
  /// In en, this message translates to:
  /// **'{quantity} ×'**
  String saleDetailsQuantity(Object quantity);

  /// No description provided for @transactionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get transactionsTitle;

  /// No description provided for @transactionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 sale in the last 14 days} other{{count} sales in the last 14 days}}'**
  String transactionsSubtitle(num count);

  /// No description provided for @transactionsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No sales yet'**
  String get transactionsEmptyTitle;

  /// No description provided for @transactionsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Every sale rung up at this till is listed here, with who sold it.'**
  String get transactionsEmptyMessage;

  /// No description provided for @transactionsEmptyOwnTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing sold yet today'**
  String get transactionsEmptyOwnTitle;

  /// No description provided for @transactionsEmptyOwnMessage.
  ///
  /// In en, this message translates to:
  /// **'You have not rung up any sales on this till yet. Sign in as a manager or owner to see the whole shop.'**
  String get transactionsEmptyOwnMessage;

  /// No description provided for @transactionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'That list could not be loaded.'**
  String get transactionsLoadFailed;

  /// No description provided for @transactionsSoldBy.
  ///
  /// In en, this message translates to:
  /// **'Sold by {name}'**
  String transactionsSoldBy(Object name);

  /// No description provided for @transactionsAuditBy.
  ///
  /// In en, this message translates to:
  /// **'Logged as {name}'**
  String transactionsAuditBy(Object name);

  /// No description provided for @transactionsMethod.
  ///
  /// In en, this message translates to:
  /// **'{method}'**
  String transactionsMethod(Object method);

  /// No description provided for @transactionsItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing} =1{1 item} other{{count} items}}'**
  String transactionsItemsCount(num count);

  /// No description provided for @transactionsMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Just now} other{{count} minutes ago}}'**
  String transactionsMinutesAgo(num count);

  /// No description provided for @transactionsHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{An hour ago} other{{count} hours ago}}'**
  String transactionsHoursAgo(num count);

  /// No description provided for @transactionsOn.
  ///
  /// In en, this message translates to:
  /// **'{day}/{month}'**
  String transactionsOn(Object day, Object month);

  /// No description provided for @dashboardTransactionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get dashboardTransactionsLabel;

  /// No description provided for @analyticsTopProductsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing sold in this period.'**
  String get analyticsTopProductsEmpty;

  /// No description provided for @analyticsProfitLabel.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get analyticsProfitLabel;

  /// No description provided for @analyticsNetProfitLabel.
  ///
  /// In en, this message translates to:
  /// **'Net profit'**
  String get analyticsNetProfitLabel;

  /// No description provided for @analyticsNetProfitCaption.
  ///
  /// In en, this message translates to:
  /// **'After posted expenses'**
  String get analyticsNetProfitCaption;

  /// No description provided for @analyticsAvgBasketLabel.
  ///
  /// In en, this message translates to:
  /// **'Avg basket'**
  String get analyticsAvgBasketLabel;

  /// No description provided for @analyticsSortedBy.
  ///
  /// In en, this message translates to:
  /// **'{label}, sorted {direction}'**
  String analyticsSortedBy(Object direction, Object label);

  /// No description provided for @analyticsNotSorted.
  ///
  /// In en, this message translates to:
  /// **'{label} column, not sorted'**
  String analyticsNotSorted(Object label);

  /// No description provided for @analyticsSortedAscending.
  ///
  /// In en, this message translates to:
  /// **'ascending'**
  String get analyticsSortedAscending;

  /// No description provided for @analyticsSortedDescending.
  ///
  /// In en, this message translates to:
  /// **'descending'**
  String get analyticsSortedDescending;

  /// No description provided for @analyticsRowSpokenFull.
  ///
  /// In en, this message translates to:
  /// **'{product}, {units} units, {revenue} revenue, {profit} profit, {margin} margin'**
  String analyticsRowSpokenFull(Object margin, Object product, Object profit,
      Object revenue, Object units);

  /// No description provided for @analyticsRowSpokenCompact.
  ///
  /// In en, this message translates to:
  /// **'{units} units · {profit} profit · {margin} margin'**
  String analyticsRowSpokenCompact(Object margin, Object profit, Object units);

  /// No description provided for @analyticsTransactionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get analyticsTransactionsLabel;

  /// No description provided for @analyticsPaymentMethodsSection.
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get analyticsPaymentMethodsSection;

  /// No description provided for @analyticsNothingTaken.
  ///
  /// In en, this message translates to:
  /// **'Nothing taken in this period.'**
  String get analyticsNothingTaken;

  /// No description provided for @analyticsPaymentMixTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get analyticsPaymentMixTotal;

  /// No description provided for @analyticsPaymentMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get analyticsPaymentMethodCash;

  /// No description provided for @analyticsPaymentMethodMpesa.
  ///
  /// In en, this message translates to:
  /// **'M-Pesa'**
  String get analyticsPaymentMethodMpesa;

  /// No description provided for @analyticsPaymentMethodMobileMoney.
  ///
  /// In en, this message translates to:
  /// **'Mobile money'**
  String get analyticsPaymentMethodMobileMoney;

  /// No description provided for @analyticsPaymentMethodCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get analyticsPaymentMethodCard;

  /// No description provided for @analyticsPaymentMethodBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get analyticsPaymentMethodBankTransfer;

  /// No description provided for @analyticsPaymentRowSpoken.
  ///
  /// In en, this message translates to:
  /// **'{label}, {share} of takings, {amount} across {count, plural, =1{1 sale} other{{count} sales}}'**
  String analyticsPaymentRowSpoken(
      Object amount, num count, Object label, Object share);

  /// No description provided for @attentionItemsToFix.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 to fix} other{{count} to fix}}'**
  String attentionItemsToFix(num count);

  /// No description provided for @attentionCountBadge.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String attentionCountBadge(Object count);

  /// No description provided for @attentionSpoken.
  ///
  /// In en, this message translates to:
  /// **'{label}. {detail}'**
  String attentionSpoken(Object detail, Object label);

  /// No description provided for @attentionSectionTitleNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get attentionSectionTitleNeedsAttention;

  /// No description provided for @attentionDismissAction.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get attentionDismissAction;

  /// No description provided for @attentionKraRefused.
  ///
  /// In en, this message translates to:
  /// **'KRA refused {count, plural, =1{1 receipt} other{{count} receipts}}'**
  String attentionKraRefused(num count);

  /// No description provided for @attentionKraRefusedDetail.
  ///
  /// In en, this message translates to:
  /// **'The shop details KRA is using need correcting.'**
  String get attentionKraRefusedDetail;

  /// No description provided for @attentionKraRefusedFixAction.
  ///
  /// In en, this message translates to:
  /// **'Fix details'**
  String get attentionKraRefusedFixAction;

  /// No description provided for @attentionKraRefusedRetryAction.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get attentionKraRefusedRetryAction;

  /// No description provided for @attentionKraPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting on KRA for {count, plural, =1{1 receipt} other{{count} receipts}}'**
  String attentionKraPending(num count);

  /// No description provided for @attentionKraPendingDetail.
  ///
  /// In en, this message translates to:
  /// **'These are recorded locally. They will issue on their own.'**
  String get attentionKraPendingDetail;

  /// No description provided for @attentionKraRetryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry now'**
  String get attentionKraRetryAction;

  /// No description provided for @attentionKraRetryFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reach KRA. The receipts stay queued and will go up on the next connection.'**
  String get attentionKraRetryFailed;

  /// No description provided for @attentionUnverifiedPayments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 payment} other{{count} payments}} not confirmed'**
  String attentionUnverifiedPayments(num count);

  /// No description provided for @attentionUnverifiedPaymentsDetail.
  ///
  /// In en, this message translates to:
  /// **'Taken while offline. Check each one against the till roll.'**
  String get attentionUnverifiedPaymentsDetail;

  /// No description provided for @attentionImportProblems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 row} other{{count} rows}} failed to import'**
  String attentionImportProblems(num count);

  /// No description provided for @attentionImportProblemsDetail.
  ///
  /// In en, this message translates to:
  /// **'Fill in what the file was missing and they are imported.'**
  String get attentionImportProblemsDetail;

  /// No description provided for @attentionImportProblemsAction.
  ///
  /// In en, this message translates to:
  /// **'Finish now'**
  String get attentionImportProblemsAction;

  /// No description provided for @analyticsChartTitleSalesByDay.
  ///
  /// In en, this message translates to:
  /// **'Sales by day'**
  String get analyticsChartTitleSalesByDay;

  /// No description provided for @loginNoAccountsYetTitle.
  ///
  /// In en, this message translates to:
  /// **'This till has no accounts yet'**
  String get loginNoAccountsYetTitle;

  /// No description provided for @reportsTransactionCaption.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transaction} other{{count} transactions}}'**
  String reportsTransactionCaption(num count);

  /// No description provided for @activityTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activityTitle;

  /// No description provided for @activitySummary.
  ///
  /// In en, this message translates to:
  /// **'{shops, plural, =1{1 shop} other{{shops} shops}}, {entries, plural, =1{1 change} other{{entries} changes}}'**
  String activitySummary(num entries, num shops);

  /// No description provided for @activityViewMerged.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get activityViewMerged;

  /// No description provided for @activityViewByShop.
  ///
  /// In en, this message translates to:
  /// **'By shop'**
  String get activityViewByShop;

  /// No description provided for @activityEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get activityEmptyTitle;

  /// No description provided for @activityEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Changes to stock, prices, staff, backups and settings will appear here for every shop on this phone.'**
  String get activityEmptyMessage;

  /// No description provided for @activityLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the activity log for your shops.'**
  String get activityLoadFailed;

  /// No description provided for @activityShopEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet in this shop.'**
  String get activityShopEmpty;

  /// No description provided for @activityShopUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Unreadable'**
  String get activityShopUnreadable;

  /// No description provided for @activityShopUnreadableDetail.
  ///
  /// In en, this message translates to:
  /// **'This shop\'s activity log could not be read on this phone. Its changes are still recorded; the log simply cannot be shown here.'**
  String get activityShopUnreadableDetail;

  /// No description provided for @activityProductCreated.
  ///
  /// In en, this message translates to:
  /// **'Product added'**
  String get activityProductCreated;

  /// No description provided for @activityProductUpdated.
  ///
  /// In en, this message translates to:
  /// **'Product changed'**
  String get activityProductUpdated;

  /// No description provided for @activityBarcodeAdded.
  ///
  /// In en, this message translates to:
  /// **'Barcode added'**
  String get activityBarcodeAdded;

  /// No description provided for @activityBarcodeRemoved.
  ///
  /// In en, this message translates to:
  /// **'Barcode removed'**
  String get activityBarcodeRemoved;

  /// No description provided for @activityBarcodeKindChanged.
  ///
  /// In en, this message translates to:
  /// **'Barcode label changed'**
  String get activityBarcodeKindChanged;

  /// No description provided for @activityStockAdjusted.
  ///
  /// In en, this message translates to:
  /// **'Stock adjusted'**
  String get activityStockAdjusted;

  /// No description provided for @activitySaleRecorded.
  ///
  /// In en, this message translates to:
  /// **'Sale recorded'**
  String get activitySaleRecorded;

  /// No description provided for @activityShotCupSold.
  ///
  /// In en, this message translates to:
  /// **'Cup sold'**
  String get activityShotCupSold;

  /// No description provided for @activityStaffAdded.
  ///
  /// In en, this message translates to:
  /// **'Staff added'**
  String get activityStaffAdded;

  /// No description provided for @activityStaffRemoved.
  ///
  /// In en, this message translates to:
  /// **'Staff removed'**
  String get activityStaffRemoved;

  /// No description provided for @activityStaffPinReset.
  ///
  /// In en, this message translates to:
  /// **'PIN reset'**
  String get activityStaffPinReset;

  /// No description provided for @activityPaymentChanged.
  ///
  /// In en, this message translates to:
  /// **'Payment method changed'**
  String get activityPaymentChanged;

  /// No description provided for @activityPrinterPaired.
  ///
  /// In en, this message translates to:
  /// **'Printer paired'**
  String get activityPrinterPaired;

  /// No description provided for @activityPrinterSaved.
  ///
  /// In en, this message translates to:
  /// **'Printer settings saved'**
  String get activityPrinterSaved;

  /// No description provided for @activityTaxChanged.
  ///
  /// In en, this message translates to:
  /// **'Tax settings changed'**
  String get activityTaxChanged;

  /// No description provided for @activitySyncChanged.
  ///
  /// In en, this message translates to:
  /// **'Backup sync settings changed'**
  String get activitySyncChanged;

  /// No description provided for @activityBackupExported.
  ///
  /// In en, this message translates to:
  /// **'Backup exported'**
  String get activityBackupExported;

  /// No description provided for @activityBackupRestored.
  ///
  /// In en, this message translates to:
  /// **'Backup restored'**
  String get activityBackupRestored;

  /// No description provided for @activityBackupErased.
  ///
  /// In en, this message translates to:
  /// **'Backup erased'**
  String get activityBackupErased;

  /// No description provided for @activityShopSwitched.
  ///
  /// In en, this message translates to:
  /// **'Switched shop'**
  String get activityShopSwitched;

  /// No description provided for @activityShopCreated.
  ///
  /// In en, this message translates to:
  /// **'Shop created'**
  String get activityShopCreated;

  /// No description provided for @activityShiftOpened.
  ///
  /// In en, this message translates to:
  /// **'Shift opened'**
  String get activityShiftOpened;

  /// No description provided for @activityShiftClosed.
  ///
  /// In en, this message translates to:
  /// **'Shift closed'**
  String get activityShiftClosed;

  /// No description provided for @activityIdentityLinked.
  ///
  /// In en, this message translates to:
  /// **'Online account linked'**
  String get activityIdentityLinked;

  /// No description provided for @activityProductPhotoSet.
  ///
  /// In en, this message translates to:
  /// **'Product photo added'**
  String get activityProductPhotoSet;

  /// No description provided for @activityProductPhotoRemoved.
  ///
  /// In en, this message translates to:
  /// **'Product photo removed'**
  String get activityProductPhotoRemoved;

  /// No description provided for @activityOwnerPinReset.
  ///
  /// In en, this message translates to:
  /// **'Owner PIN reset'**
  String get activityOwnerPinReset;

  /// No description provided for @activityAccountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Account deleted and data erased'**
  String get activityAccountDeleted;

  /// No description provided for @activityVariantAdded.
  ///
  /// In en, this message translates to:
  /// **'Variant added'**
  String get activityVariantAdded;

  /// No description provided for @activityVariantUpdated.
  ///
  /// In en, this message translates to:
  /// **'Variant changed'**
  String get activityVariantUpdated;

  /// No description provided for @activityVariantRemoved.
  ///
  /// In en, this message translates to:
  /// **'Variant removed'**
  String get activityVariantRemoved;

  /// No description provided for @reportsStaffRowSpoken.
  ///
  /// In en, this message translates to:
  /// **'{name}, {count, plural, =1{1 transaction} other{{count} transactions}}, taking {total}, profit {profit}'**
  String reportsStaffRowSpoken(
      num count, Object name, Object profit, Object total);

  /// No description provided for @portfolioTitle.
  ///
  /// In en, this message translates to:
  /// **'All shops'**
  String get portfolioTitle;

  /// No description provided for @portfolioOpenAction.
  ///
  /// In en, this message translates to:
  /// **'How all my shops are doing'**
  String get portfolioOpenAction;

  /// No description provided for @portfolioRangeWeek.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get portfolioRangeWeek;

  /// No description provided for @portfolioRangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get portfolioRangeLabel;

  /// No description provided for @portfolioRangeCurrent.
  ///
  /// In en, this message translates to:
  /// **'current range'**
  String get portfolioRangeCurrent;

  /// No description provided for @portfolioRangeMonth.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get portfolioRangeMonth;

  /// No description provided for @portfolioRangeQuarter.
  ///
  /// In en, this message translates to:
  /// **'90 days'**
  String get portfolioRangeQuarter;

  /// No description provided for @portfolioSharedTitle.
  ///
  /// In en, this message translates to:
  /// **'Who\'s taking what'**
  String get portfolioSharedTitle;

  /// No description provided for @portfolioShopsTitle.
  ///
  /// In en, this message translates to:
  /// **'Shops'**
  String get portfolioShopsTitle;

  /// No description provided for @portfolioTotalRevenue.
  ///
  /// In en, this message translates to:
  /// **'Total takings'**
  String get portfolioTotalRevenue;

  /// No description provided for @portfolioProfit.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get portfolioProfit;

  /// No description provided for @portfolioTransactions.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get portfolioTransactions;

  /// No description provided for @portfolioAvgBasket.
  ///
  /// In en, this message translates to:
  /// **'Avg basket'**
  String get portfolioAvgBasket;

  /// No description provided for @portfolioTopShop.
  ///
  /// In en, this message translates to:
  /// **'Busiest: {shop} at {amount}'**
  String portfolioTopShop(Object amount, Object shop);

  /// No description provided for @portfolioEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No shops to report yet'**
  String get portfolioEmptyTitle;

  /// No description provided for @portfolioEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Add a shop on this device, or check the internet connection and try again.'**
  String get portfolioEmptyMessage;

  /// No description provided for @portfolioFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the shop figures. This view needs a connection.'**
  String get portfolioFailureMessage;

  /// No description provided for @portfolioShopRowSpoken.
  ///
  /// In en, this message translates to:
  /// **'{shop}, {revenue} takings, {profit} profit, {count, plural, =1{1 transaction} other{{count} transactions}}, {share} of all shops'**
  String portfolioShopRowSpoken(
      num count, Object profit, Object revenue, Object share, Object shop);

  /// No description provided for @productSizeLabelKilogram.
  ///
  /// In en, this message translates to:
  /// **'How many litres the tank holds (ml)'**
  String get productSizeLabelKilogram;

  /// No description provided for @productUnitKilogram.
  ///
  /// In en, this message translates to:
  /// **'Tank (kg)'**
  String get productUnitKilogram;

  /// No description provided for @variantUnitKilogram.
  ///
  /// In en, this message translates to:
  /// **'Tank (kg)'**
  String get variantUnitKilogram;

  /// No description provided for @tankFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a tank'**
  String get tankFormTitle;

  /// No description provided for @tankFormSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A tank is a big container you pour drinks from. It can hold beer, soda or anything else you sell by the cup. Write what is in it and how you sell it. You can add as many tanks as you want.'**
  String get tankFormSubtitle;

  /// No description provided for @tankFieldName.
  ///
  /// In en, this message translates to:
  /// **'What is in the tank?'**
  String get tankFieldName;

  /// No description provided for @tankFieldNameHint.
  ///
  /// In en, this message translates to:
  /// **'Write the name of the drink. For example: Tusker.'**
  String get tankFieldNameHint;

  /// No description provided for @tankFieldCapacityL.
  ///
  /// In en, this message translates to:
  /// **'How much the tank holds (litres)'**
  String get tankFieldCapacityL;

  /// No description provided for @tankFieldCapacityLHint.
  ///
  /// In en, this message translates to:
  /// **'Write a number. A big drum holds 50 litres — write 50.'**
  String get tankFieldCapacityLHint;

  /// No description provided for @tankFieldTankCount.
  ///
  /// In en, this message translates to:
  /// **'How many full tanks you have now'**
  String get tankFieldTankCount;

  /// No description provided for @tankFieldTankCountHint.
  ///
  /// In en, this message translates to:
  /// **'Write a number, like 1 or 2. Use 0 if the delivery has not arrived yet.'**
  String get tankFieldTankCountHint;

  /// No description provided for @tankFieldTankCost.
  ///
  /// In en, this message translates to:
  /// **'What one full tank cost you (KSh)'**
  String get tankFieldTankCost;

  /// No description provided for @tankFieldTankCostHint.
  ///
  /// In en, this message translates to:
  /// **'The money you paid for the whole tank. We use it to work out the profit on every cup.'**
  String get tankFieldTankCostHint;

  /// No description provided for @tankCapacityInvalid.
  ///
  /// In en, this message translates to:
  /// **'Write how much the tank holds. Only numbers, like 50.'**
  String get tankCapacityInvalid;

  /// No description provided for @tankCountRequired.
  ///
  /// In en, this message translates to:
  /// **'Write how many tanks you have. Use 0 if none have arrived yet.'**
  String get tankCountRequired;

  /// No description provided for @tankNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Write what is in the tank.'**
  String get tankNameRequired;

  /// No description provided for @tankAddAction.
  ///
  /// In en, this message translates to:
  /// **'Save this tank'**
  String get tankAddAction;

  /// No description provided for @tankPriceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Write what one full tank cost you. Only numbers.'**
  String get tankPriceInvalid;

  /// No description provided for @tankSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'That tank could not be saved. Your numbers are still here — try again.'**
  String get tankSaveFailed;

  /// No description provided for @tankAddEntry.
  ///
  /// In en, this message translates to:
  /// **'Add a tank'**
  String get tankAddEntry;

  /// No description provided for @tankServingsTitle.
  ///
  /// In en, this message translates to:
  /// **'How do you sell it?'**
  String get tankServingsTitle;

  /// No description provided for @tankServingsHint.
  ///
  /// In en, this message translates to:
  /// **'Write each cup you sell. For example a small cup and a big cup.'**
  String get tankServingsHint;

  /// No description provided for @tankServingLabel.
  ///
  /// In en, this message translates to:
  /// **'Cup {n}'**
  String tankServingLabel(Object n);

  /// No description provided for @tankFieldServingName.
  ///
  /// In en, this message translates to:
  /// **'What do you call it?'**
  String get tankFieldServingName;

  /// No description provided for @tankFieldServingNameHint.
  ///
  /// In en, this message translates to:
  /// **'For example: Small cup, Big cup.'**
  String get tankFieldServingNameHint;

  /// No description provided for @tankFieldServingMl.
  ///
  /// In en, this message translates to:
  /// **'How much is in one cup (ml)'**
  String get tankFieldServingMl;

  /// No description provided for @tankFieldServingMlHint.
  ///
  /// In en, this message translates to:
  /// **'For example: 330. Leave it empty if you do not know.'**
  String get tankFieldServingMlHint;

  /// No description provided for @tankFieldServingPrice.
  ///
  /// In en, this message translates to:
  /// **'Price for one cup (KSh)'**
  String get tankFieldServingPrice;

  /// No description provided for @tankFieldServingPriceHint.
  ///
  /// In en, this message translates to:
  /// **'What you sell one cup for.'**
  String get tankFieldServingPriceHint;

  /// No description provided for @tankServingAdd.
  ///
  /// In en, this message translates to:
  /// **'Add another cup'**
  String get tankServingAdd;

  /// No description provided for @tankServingRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove this cup'**
  String get tankServingRemove;

  /// No description provided for @tankServingNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Write what you call this cup.'**
  String get tankServingNameRequired;

  /// No description provided for @tankServingPriceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Write the price for one cup. Only numbers.'**
  String get tankServingPriceInvalid;

  /// No description provided for @tankServingSizeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Write how much is in one cup, or leave it empty.'**
  String get tankServingSizeInvalid;

  /// No description provided for @tankServingTooBig.
  ///
  /// In en, this message translates to:
  /// **'That cup is bigger than the tank.'**
  String get tankServingTooBig;

  /// No description provided for @tankServingMinOne.
  ///
  /// In en, this message translates to:
  /// **'Write at least one cup you sell.'**
  String get tankServingMinOne;

  /// No description provided for @tankCreated.
  ///
  /// In en, this message translates to:
  /// **'{name} is added. You can now sell it in the cups you set.'**
  String tankCreated(Object name);

  /// No description provided for @actionTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionTryAgain;

  /// No description provided for @actionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// No description provided for @actionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get actionSkip;

  /// No description provided for @actionSendCopy.
  ///
  /// In en, this message translates to:
  /// **'Send a copy'**
  String get actionSendCopy;

  /// No description provided for @loginWhoAreYou.
  ///
  /// In en, this message translates to:
  /// **'Who are you?'**
  String get loginWhoAreYou;

  /// No description provided for @supportMarkResolved.
  ///
  /// In en, this message translates to:
  /// **'Mark as solved'**
  String get supportMarkResolved;

  /// No description provided for @analyticsReorderInInventory.
  ///
  /// In en, this message translates to:
  /// **'Ask for more in Stock'**
  String get analyticsReorderInInventory;

  /// No description provided for @reportsShiftAndTillSection.
  ///
  /// In en, this message translates to:
  /// **'Money in the till'**
  String get reportsShiftAndTillSection;

  /// No description provided for @inventoryWhichVariant.
  ///
  /// In en, this message translates to:
  /// **'Which size of {name}?'**
  String inventoryWhichVariant(Object name);

  /// No description provided for @inventoryRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String inventoryRemoveConfirm(Object name);

  /// No description provided for @servingAllInCart.
  ///
  /// In en, this message translates to:
  /// **'Everything left is already in the cart'**
  String get servingAllInCart;

  /// No description provided for @servingFractionLeft.
  ///
  /// In en, this message translates to:
  /// **'Only {count} of a bottle is left'**
  String servingFractionLeft(Object count);

  /// No description provided for @sellAllVariantInCart.
  ///
  /// In en, this message translates to:
  /// **'All of {name} is already in the cart.'**
  String sellAllVariantInCart(Object name);

  /// No description provided for @sellNoVariantLeft.
  ///
  /// In en, this message translates to:
  /// **'There is no {name} left. Take some out of the cart first.'**
  String sellNoVariantLeft(Object name);

  /// No description provided for @sellNotEnoughForShot.
  ///
  /// In en, this message translates to:
  /// **'There is not enough {name} left for another cup. Take some out of the cart first.'**
  String sellNotEnoughForShot(Object name);

  /// No description provided for @sellNotEnoughLeft.
  ///
  /// In en, this message translates to:
  /// **'There is not enough {name} left. Take some out of the cart first.'**
  String sellNotEnoughLeft(Object name);

  /// No description provided for @shotNoVolume.
  ///
  /// In en, this message translates to:
  /// **'{name} has no size written, so a cup cannot be taken from it'**
  String shotNoVolume(Object name);

  /// No description provided for @shotNoneLeft.
  ///
  /// In en, this message translates to:
  /// **'There is no {name} left'**
  String shotNoneLeft(Object name);

  /// No description provided for @shotCupNoSize.
  ///
  /// In en, this message translates to:
  /// **'This cup has no size, so the container will not go down when you sell it'**
  String get shotCupNoSize;

  /// No description provided for @shotCupTooBig.
  ///
  /// In en, this message translates to:
  /// **'This cup is bigger than the container ({ml} ml)'**
  String shotCupTooBig(Object ml);

  /// No description provided for @shotCountLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} cups left in the container'**
  String shotCountLeft(Object count);

  /// No description provided for @reportsPrinterOffPairFirst.
  ///
  /// In en, this message translates to:
  /// **'Printing is switched off. Join a printer in Settings first.'**
  String get reportsPrinterOffPairFirst;

  /// No description provided for @reportsPrinterOff.
  ///
  /// In en, this message translates to:
  /// **'Printing is switched off.'**
  String get reportsPrinterOff;

  /// No description provided for @reportsSendingToPrinter.
  ///
  /// In en, this message translates to:
  /// **'Sending the receipt to the printer…'**
  String get reportsSendingToPrinter;

  /// No description provided for @reportsReceiptReprinted.
  ///
  /// In en, this message translates to:
  /// **'The receipt printed again.'**
  String get reportsReceiptReprinted;

  /// No description provided for @reportsPrintFailedWith.
  ///
  /// In en, this message translates to:
  /// **'Could not print. {advice}'**
  String reportsPrintFailedWith(Object advice);

  /// No description provided for @reportsNoSalesByCashier.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this till was sold by that person.'**
  String get reportsNoSalesByCashier;

  /// No description provided for @reportsCashierReportWaiting.
  ///
  /// In en, this message translates to:
  /// **'Once a shift is opened and a sale is rung up, this report has something to show.'**
  String get reportsCashierReportWaiting;

  /// No description provided for @shiftNeedsStaffEntry.
  ///
  /// In en, this message translates to:
  /// **'A shift needs a worker. Add yourself in Settings, then open the shift again.'**
  String get shiftNeedsStaffEntry;

  /// No description provided for @sellTileStockCountLow.
  ///
  /// In en, this message translates to:
  /// **'{quantity} in stock · running low'**
  String sellTileStockCountLow(Object quantity);

  /// No description provided for @sellNoStockLeft.
  ///
  /// In en, this message translates to:
  /// **'There is none left'**
  String get sellNoStockLeft;

  /// No description provided for @portionFullLabel.
  ///
  /// In en, this message translates to:
  /// **'Full bottle'**
  String get portionFullLabel;

  /// No description provided for @portionHalfLabel.
  ///
  /// In en, this message translates to:
  /// **'Half'**
  String get portionHalfLabel;

  /// No description provided for @portionQuarterLabel.
  ///
  /// In en, this message translates to:
  /// **'Quarter'**
  String get portionQuarterLabel;

  /// No description provided for @supportStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get supportStatusOpen;

  /// No description provided for @supportStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'Being worked on'**
  String get supportStatusInProgress;

  /// No description provided for @supportStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get supportStatusResolved;

  /// No description provided for @reportsNoSalesTitle.
  ///
  /// In en, this message translates to:
  /// **'No sales written yet'**
  String get reportsNoSalesTitle;

  /// No description provided for @reportsOpenTillReport.
  ///
  /// In en, this message translates to:
  /// **'Open the till report'**
  String get reportsOpenTillReport;

  /// No description provided for @reportsClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear the search'**
  String get reportsClearSearch;

  /// No description provided for @dashboardCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not read today\'s numbers.'**
  String get dashboardCouldNotLoad;

  /// No description provided for @dashboardStillWorksDetail.
  ///
  /// In en, this message translates to:
  /// **'The till still works. Pull to try again, or look at the data in Settings.'**
  String get dashboardStillWorksDetail;

  /// No description provided for @analyticsReportingPeriod.
  ///
  /// In en, this message translates to:
  /// **'Shown for'**
  String get analyticsReportingPeriod;

  /// No description provided for @analyticsNothingToCompare.
  ///
  /// In en, this message translates to:
  /// **'nothing to compare against'**
  String get analyticsNothingToCompare;

  /// No description provided for @analyticsNoChange.
  ///
  /// In en, this message translates to:
  /// **'no change'**
  String get analyticsNoChange;

  /// No description provided for @portfolioShiftsCounted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 shift counted} other{{count} shifts counted}}'**
  String portfolioShiftsCounted(num count);

  /// No description provided for @portfolioShiftsOpenNow.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open now} other{{count} open now}}'**
  String portfolioShiftsOpenNow(num count);

  /// No description provided for @portfolioDrawerShort.
  ///
  /// In en, this message translates to:
  /// **'drawer short {amount}'**
  String portfolioDrawerShort(Object amount);

  /// No description provided for @portfolioDrawerOver.
  ///
  /// In en, this message translates to:
  /// **'drawer over {amount}'**
  String portfolioDrawerOver(Object amount);

  /// No description provided for @portfolioShiftsNone.
  ///
  /// In en, this message translates to:
  /// **'no shifts yet'**
  String get portfolioShiftsNone;

  /// No description provided for @sellOutOfStockHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to see why it cannot be sold'**
  String get sellOutOfStockHint;

  /// No description provided for @sellNoPriceSetYet.
  ///
  /// In en, this message translates to:
  /// **'This item has no price and no cup to sell by yet. Set a price in Stock.'**
  String get sellNoPriceSetYet;

  /// No description provided for @loginNotInThisShop.
  ///
  /// In en, this message translates to:
  /// **'That person is not in this shop. Pick the shop they work in.'**
  String get loginNotInThisShop;

  /// No description provided for @analyticsMarginLabel.
  ///
  /// In en, this message translates to:
  /// **'Margin'**
  String get analyticsMarginLabel;

  /// No description provided for @inventoryRepackAction.
  ///
  /// In en, this message translates to:
  /// **'Repack stock'**
  String get inventoryRepackAction;

  /// No description provided for @inventoryRepackTitle.
  ///
  /// In en, this message translates to:
  /// **'Repack stock'**
  String get inventoryRepackTitle;

  /// No description provided for @inventoryRepackSourceProduct.
  ///
  /// In en, this message translates to:
  /// **'Source product'**
  String get inventoryRepackSourceProduct;

  /// No description provided for @inventoryRepackSourceQuantity.
  ///
  /// In en, this message translates to:
  /// **'Source quantity used'**
  String get inventoryRepackSourceQuantity;

  /// No description provided for @inventoryRepackSourceHelp.
  ///
  /// In en, this message translates to:
  /// **'For example, 10 kg of bulk sugar'**
  String get inventoryRepackSourceHelp;

  /// No description provided for @inventoryRepackOutputProduct.
  ///
  /// In en, this message translates to:
  /// **'Output product'**
  String get inventoryRepackOutputProduct;

  /// No description provided for @inventoryRepackOutputQuantity.
  ///
  /// In en, this message translates to:
  /// **'Output quantity made'**
  String get inventoryRepackOutputQuantity;

  /// No description provided for @inventoryRepackOutputHelp.
  ///
  /// In en, this message translates to:
  /// **'For example, 20 packets of 500 g'**
  String get inventoryRepackOutputHelp;

  /// No description provided for @inventoryRepackCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get inventoryRepackCancel;

  /// No description provided for @inventoryRepackRecord.
  ///
  /// In en, this message translates to:
  /// **'Record repack'**
  String get inventoryRepackRecord;

  /// No description provided for @inventoryRepackSaved.
  ///
  /// In en, this message translates to:
  /// **'Repack recorded. Stock sync will include both movements.'**
  String get inventoryRepackSaved;

  /// No description provided for @inventoryRepackInsufficientStock.
  ///
  /// In en, this message translates to:
  /// **'Repack cannot use more stock than is available.'**
  String get inventoryRepackInsufficientStock;

  /// No description provided for @inventoryRepackFailed.
  ///
  /// In en, this message translates to:
  /// **'Repack could not be recorded.'**
  String get inventoryRepackFailed;

  /// No description provided for @drinksAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Drinks operations'**
  String get drinksAnalyticsTitle;

  /// No description provided for @drinksAnalyticsLitresSold.
  ///
  /// In en, this message translates to:
  /// **'Litres sold'**
  String get drinksAnalyticsLitresSold;

  /// No description provided for @drinksAnalyticsPourSales.
  ///
  /// In en, this message translates to:
  /// **'Pour sales'**
  String get drinksAnalyticsPourSales;

  /// No description provided for @drinksAnalyticsMeasuredLines.
  ///
  /// In en, this message translates to:
  /// **'Measured servings'**
  String get drinksAnalyticsMeasuredLines;

  /// No description provided for @drinksAnalyticsOpenTabs.
  ///
  /// In en, this message translates to:
  /// **'Open tabs'**
  String get drinksAnalyticsOpenTabs;

  /// No description provided for @drinksAnalyticsTankBalance.
  ///
  /// In en, this message translates to:
  /// **'Tank balance'**
  String get drinksAnalyticsTankBalance;

  /// No description provided for @drinksAnalyticsWaste.
  ///
  /// In en, this message translates to:
  /// **'Waste/spillage'**
  String get drinksAnalyticsWaste;

  /// No description provided for @drinksAnalyticsDipVariance.
  ///
  /// In en, this message translates to:
  /// **'Dip variance'**
  String get drinksAnalyticsDipVariance;

  /// No description provided for @drinksAnalyticsDipBelow.
  ///
  /// In en, this message translates to:
  /// **'below expected'**
  String get drinksAnalyticsDipBelow;

  /// No description provided for @drinksAnalyticsDipAbove.
  ///
  /// In en, this message translates to:
  /// **'above expected'**
  String get drinksAnalyticsDipAbove;

  /// No description provided for @drinksAnalyticsNoTankData.
  ///
  /// In en, this message translates to:
  /// **'No tank balance recorded'**
  String get drinksAnalyticsNoTankData;

  /// No description provided for @drinksAnalyticsLitres.
  ///
  /// In en, this message translates to:
  /// **'{amount} L'**
  String drinksAnalyticsLitres(Object amount);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'sw'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'sw':
      return AppLocalizationsSw();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
