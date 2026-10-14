import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

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
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

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

  /// No description provided for @sellBrowseProductsAction.
  ///
  /// In en, this message translates to:
  /// **'Browse products'**
  String get sellBrowseProductsAction;

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
  /// **'Shots'**
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
  /// **'Shot cups. Fixed-size shots of any drink in your inventory.'**
  String get inventoryShotCupsSpoken;

  /// No description provided for @inventoryShotCupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Shot cups'**
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
  /// **'Could not check ({reason})'**
  String settingsUpdatesFailed(Object reason);

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
  /// **'A PIN is exactly four digits.'**
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
  /// **'Email verified. Auto-backups, analytics and auto-update are now on.'**
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
  /// **'Confirm you are the shop admin with your 4-digit PIN. Your online account is created for {email}, and we will send a 6-digit code to that address to prove it is yours.'**
  String settingsVerifyPinMessage(Object email);

  /// No description provided for @settingsVerifyPinWrong.
  ///
  /// In en, this message translates to:
  /// **'That is not the admin PIN for this shop.'**
  String get settingsVerifyPinWrong;

  /// No description provided for @settingsVerifyPinLabel.
  ///
  /// In en, this message translates to:
  /// **'4-digit admin PIN'**
  String get settingsVerifyPinLabel;

  /// No description provided for @settingsVerifyCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code we emailed'**
  String get settingsVerifyCodeTitle;

  /// No description provided for @settingsVerifyCodeMessage.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {email}. It expires in {minutes} minutes.'**
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
  /// **'This shop needs to be registered with the backend once. Sign in with the shop identity account; staff continue using local PINs for the till.'**
  String get settingsConnectMpesaMessage;

  /// No description provided for @settingsPaymentChannelHint.
  ///
  /// In en, this message translates to:
  /// **'Find your channel ID on the payment provider dashboard, under your wallet/channel settings.'**
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

  /// No description provided for @shotCupsActionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Shot cup actions'**
  String get shotCupsActionsLabel;

  /// No description provided for @shotCupsAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add a shot cup'**
  String get shotCupsAddAction;

  /// No description provided for @shotCupsCapacityHelper.
  ///
  /// In en, this message translates to:
  /// **'Fixed for this cup'**
  String get shotCupsCapacityHelper;

  /// No description provided for @shotCupsCapacityHint.
  ///
  /// In en, this message translates to:
  /// **'30'**
  String get shotCupsCapacityHint;

  /// No description provided for @shotCupsCapacityLabel.
  ///
  /// In en, this message translates to:
  /// **'Capacity (ml)'**
  String get shotCupsCapacityLabel;

  /// No description provided for @shotCupsCapacityMax.
  ///
  /// In en, this message translates to:
  /// **'Capacity must be {max} ml or less.'**
  String shotCupsCapacityMax(Object max);

  /// No description provided for @shotCupsCapacityPositive.
  ///
  /// In en, this message translates to:
  /// **'Capacity must be more than zero.'**
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
  /// **'Choose the drink this shot is poured from.'**
  String get shotCupsChooseDrink;

  /// No description provided for @shotCupsDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Shot'**
  String get shotCupsDefaultName;

  /// No description provided for @shotCupsEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get shotCupsEditAction;

  /// No description provided for @shotCupsEmptyMessageNoPermission.
  ///
  /// In en, this message translates to:
  /// **'No shot cups have been set up for this shop.'**
  String get shotCupsEmptyMessageNoPermission;

  /// No description provided for @shotCupsEmptyMessageOwner.
  ///
  /// In en, this message translates to:
  /// **'Add one to sell fixed-size shots of any drink in your inventory.'**
  String get shotCupsEmptyMessageOwner;

  /// No description provided for @shotCupsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No shot cups yet'**
  String get shotCupsEmptyTitle;

  /// No description provided for @shotCupsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load the shot cups. Try again.'**
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
  /// **'Shot, Double, Slim'**
  String get shotCupsNameHint;

  /// No description provided for @shotCupsNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Give the cup a name, like Shot or Double.'**
  String get shotCupsNameRequired;

  /// No description provided for @shotCupsNotSold.
  ///
  /// In en, this message translates to:
  /// **'Not sold'**
  String get shotCupsNotSold;

  /// No description provided for @shotCupsPerBottle.
  ///
  /// In en, this message translates to:
  /// **'{count} per bottle'**
  String shotCupsPerBottle(Object count);

  /// No description provided for @shotCupsPouredFromLabel.
  ///
  /// In en, this message translates to:
  /// **'Poured from'**
  String get shotCupsPouredFromLabel;

  /// No description provided for @shotCupsPriceHelper.
  ///
  /// In en, this message translates to:
  /// **'For one shot'**
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
  /// **'{product} shots stop appearing at the till. Sales already recorded are untouched.'**
  String shotCupsStopSellingMessage(Object product);

  /// No description provided for @shotCupsStopSellingTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop selling {name}?'**
  String shotCupsStopSellingTitle(Object name);

  /// No description provided for @shotCupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Shot cups'**
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
  /// **'Off — sales are recorded but no tax invoice is issued. Turn this on once a TIN is registered.'**
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
  /// **'KRA eTIMS'**
  String get taxSettingsEtimsSection;

  /// No description provided for @taxSettingsEtimsUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t update eTIMS. Check your connection and try again.'**
  String get taxSettingsEtimsUpdateFailed;

  /// No description provided for @taxSettingsIssueEtimsTitle.
  ///
  /// In en, this message translates to:
  /// **'Issue eTIMS receipts'**
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
  /// **'Enter a numeric payment channel ID'**
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
  /// **'{greeting} · {scope}'**
  String dashboardGreetingAnonymous(Object greeting, Object scope);

  /// No description provided for @dashboardGreetingNamed.
  ///
  /// In en, this message translates to:
  /// **'{greeting}, {name} · {role} · {scope}'**
  String dashboardGreetingNamed(
      Object greeting, Object name, Object role, Object scope);

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

  /// No description provided for @analyticsTopProductsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing sold in this period.'**
  String get analyticsTopProductsEmpty;

  /// No description provided for @analyticsTopProductsShowMore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Show 1 more} other{Show {count} more}}'**
  String analyticsTopProductsShowMore(num count);

  /// No description provided for @analyticsTopProductsShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show fewer'**
  String get analyticsTopProductsShowLess;

  /// No description provided for @analyticsProfitLabel.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get analyticsProfitLabel;

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
  /// **'Shot cup sold'**
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
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
