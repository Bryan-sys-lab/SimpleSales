// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'SimpleSales';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionUndo => 'Undo';

  @override
  String get actionSave => 'Save';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get actionConfirm => 'Clear';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionPressBackAgainToExit => 'Press back again to exit';

  @override
  String get errorDuplicateName =>
      'That name is already taken. Try a different one.';

  @override
  String get errorMissingField => 'Fill in every required field.';

  @override
  String get errorWriteFailed =>
      'Could not save. Try again; if it keeps happening, contact support.';

  @override
  String get errorOffline =>
      'No internet connection. Check the network and try again.';

  @override
  String get errorTimedOut =>
      'The connection timed out. Try again when the signal is better.';

  @override
  String get errorSessionExpired => 'Session expired. Sign in again.';

  @override
  String get errorNotPermitted =>
      'Your role does not allow that. Ask the owner for access.';

  @override
  String get errorPaymentFailed =>
      'Payment failed. The customer may have cancelled, or funds were insufficient.';

  @override
  String get errorInsufficientStock =>
      'Not enough stock to complete this sale.';

  @override
  String get errorUnknown =>
      'Something went wrong. Try again; if it keeps happening, contact support.';

  @override
  String get validationProductNameRequired => 'Product name is required';

  @override
  String get validationProductNameTooShort =>
      'Product name must be at least 2 characters';

  @override
  String validationFieldRequired(Object field) {
    return '$field is required';
  }

  @override
  String validationFieldNotANumber(Object field) {
    return '$field must be a valid number';
  }

  @override
  String validationFieldNotNegative(Object field) {
    return '$field cannot be negative';
  }

  @override
  String validationProductNameTooLong(Object max) {
    return 'Product name must be $max characters or fewer';
  }

  @override
  String validationProductCategoryTooLong(Object max) {
    return 'Category must be $max characters or fewer';
  }

  @override
  String get validationProductCostPrice =>
      'Cost price must be a valid amount of 0 or more';

  @override
  String get validationProductSellPrice =>
      'Selling price must be a valid amount of 0 or more';

  @override
  String get validationProductStock => 'Stock quantity must be 0 or more';

  @override
  String get validationProductReorderLevel => 'Reorder level must be 0 or more';

  @override
  String validationProductSize(Object max, Object min) {
    return 'Size must be between $min and $max ml (a 50-litre keg is 50000)';
  }

  @override
  String get validationProductHalfPrice =>
      'Half price must be a valid amount of 0 or more';

  @override
  String get validationProductQuarterPrice =>
      'Quarter price must be a valid amount of 0 or more';

  @override
  String get validationStockRequired => 'Stock quantity is required';

  @override
  String get validationStockNotWhole => 'Stock must be a whole number';

  @override
  String get validationStockNotNegative => 'Stock cannot be negative';

  @override
  String get validationPinRequired => 'PIN is required';

  @override
  String get validationPinNotFourDigits => 'PIN must be exactly 4 digits';

  @override
  String get validationPinNotSixDigits => 'PIN must be exactly 6 digits';

  @override
  String get validationPinConfirmRequired => 'Enter the PIN again';

  @override
  String get validationPinMismatch => 'PINs do not match';

  @override
  String get ownerSetupNameLabel => 'Your name (shop admin)';

  @override
  String get ownerSetupEmailLabel => 'Owner email';

  @override
  String get ownerSetupPinLabel => 'Set a 6-digit PIN';

  @override
  String get ownerSetupPinConfirmLabel => 'Confirm PIN';

  @override
  String get ownerSetupMissingDetails =>
      'Enter your name, email, and shop name';

  @override
  String get ownerSetupInvalidEmail => 'Enter a valid email address';

  @override
  String get shopProfileLabel => 'Business profile';

  @override
  String get shopProfileHelp =>
      'Choose this shop\'s profile once. You can change it later.';

  @override
  String get validationEmailRequired => 'Email is required';

  @override
  String get validationEmailInvalid => 'Enter a valid email address';

  @override
  String get validationPasswordRequired => 'Password is required';

  @override
  String get validationPasswordTooShort =>
      'Password must be at least 6 characters';

  @override
  String get validationPhoneRequired => 'Phone number is required';

  @override
  String get validationPhoneInvalid =>
      'Enter a valid phone number (9 to 12 digits)';

  @override
  String get validationChannelIdRequired => 'Channel ID is required';

  @override
  String get validationChannelIdNotANumber => 'Channel ID must be a number';

  @override
  String get validationLowPriceTitle => 'Warning: low price';

  @override
  String get validationLowPriceMessage =>
      'Sell price is below cost price. This sale will result in a loss. Continue anyway?';

  @override
  String get validationLowPriceConfirm => 'Sell below cost';

  @override
  String get validationDuplicateNameTitle => 'Duplicate product name';

  @override
  String get validationDuplicateNameMessage =>
      'A product with this name already exists. Create anyway?';

  @override
  String get validationDuplicateNameConfirm => 'Create it anyway';

  @override
  String get actionContinue => 'Continue';

  @override
  String get poweredBy => 'Powered by';

  @override
  String get actionDone => 'Done';

  @override
  String get shiftScreenTitle => 'Shift & reconciliation';

  @override
  String get shiftLoadFailedTitle => 'Could not load this till\'s shifts';

  @override
  String get shiftLoadFailedDetail =>
      'Nothing has been recorded against this screen. Try again.';

  @override
  String get shiftBannerRefresh => 'Refresh';

  @override
  String get shiftNoShiftSection => 'Your shift';

  @override
  String get shiftNoShiftTitle => 'No shift open';

  @override
  String get shiftNoShiftMessage =>
      'Open a shift to count the cash you start and end the day with. Without one there is nothing to reconcile against.';

  @override
  String get shiftNoShiftAction => 'Open shift';

  @override
  String get shiftNoShiftNoRoster =>
      'Sign in as someone on the staff roster to open a shift.';

  @override
  String get shiftOpenSection => 'Open shift';

  @override
  String get shiftOpenChip => 'Open';

  @override
  String shiftStartedAt(Object when) {
    return 'Started $when';
  }

  @override
  String get shiftExpectedLabel => 'Expected in the drawer';

  @override
  String get shiftOpeningFloat => 'Opening float';

  @override
  String get shiftCountAction => 'Count the till';

  @override
  String get shiftCloseAction => 'Close and reconcile';

  @override
  String shiftOpenCardSpoken(
      Object expected, Object name, Object variance, Object when) {
    return 'Shift open for $name, started $when. Expected in the drawer $expected. The drawer is $variance.';
  }

  @override
  String shiftRosterDialogTitle(Object name) {
    return 'Add $name to the staff list?';
  }

  @override
  String shiftRosterDialogMessage(Object name) {
    return '$name signs in as the shop owner, and the owner is not on the staff roster. A shift is recorded against a staff entry so sales can be counted against it, so $name needs a roster entry of their own. No PIN is set, so this cannot be signed in to on its own.';
  }

  @override
  String get shiftRosterDialogConfirm => 'Add me to the roster';

  @override
  String get shiftRosterDialogDecline => 'Not now';

  @override
  String shiftCountedSnack(Object amount) {
    return 'Counted $amount in the drawer.';
  }

  @override
  String get shiftClosedBalanced =>
      'Shift closed. The drawer balanced exactly.';

  @override
  String shiftClosedShort(Object amount) {
    return 'Shift closed. $amount short of the expected figure.';
  }

  @override
  String shiftClosedOver(Object amount) {
    return 'Shift closed. $amount over the expected figure.';
  }

  @override
  String get varianceBalanced => 'Balanced';

  @override
  String get varianceBalancedSpoken => 'balanced exactly, no difference';

  @override
  String get varianceShort => 'Short';

  @override
  String varianceShortSpoken(Object amount) {
    return '$amount short of the expected figure';
  }

  @override
  String get varianceOver => 'Over';

  @override
  String varianceOverSpoken(Object amount) {
    return '$amount over the expected figure';
  }

  @override
  String get varianceNotCounted => 'Not counted';

  @override
  String get varianceNotCountedSpoken => 'the drawer has not been counted yet';

  @override
  String get varianceDifferenceLabel => 'Difference';

  @override
  String get varianceShortByLabel => 'Short by';

  @override
  String get varianceOverByLabel => 'Over by';

  @override
  String varianceStripSpoken(Object variance) {
    return 'Difference between counted and expected: $variance';
  }

  @override
  String get shiftFloatAmountLabel => 'Amount (KSh)';

  @override
  String get shiftFloatInvalid => 'Enter a number, 0 or more.';

  @override
  String get shiftCountTitle => 'Count the till';

  @override
  String get shiftCountSubtitle =>
      'How many of each note and coin is in the drawer.';

  @override
  String get shiftCountPileLabel => 'How many';

  @override
  String get shiftCountTotalLabel => 'Counted so far';

  @override
  String shiftCountTotalSpoken(Object amount) {
    return 'Counted so far $amount';
  }

  @override
  String get shiftCountSaveFailed => 'Couldn\'t save the count. Try again.';

  @override
  String get shiftCloseTitle => 'Close shift';

  @override
  String get shiftCloseCashRungUp => 'Cash rung up this shift';

  @override
  String get shiftCloseCountedLabel => 'Counted in the drawer';

  @override
  String get shiftCloseCountedHelp =>
      'Pre-filled from your count. Correct it if it changed.';

  @override
  String get shiftCloseNextFloatLabel => 'Float for the next shift';

  @override
  String get shiftCloseNextFloatHelp => 'What stays in the drawer';

  @override
  String get shiftCloseKeepCounting => 'Keep counting';

  @override
  String get shiftCloseCommit => 'Close and reconcile';

  @override
  String get expensePayOutAction => 'Pay out';

  @override
  String get expensePayOutTitle => 'Pay out from till';

  @override
  String get expensePayOutSubtitle => 'Record money taken from the drawer.';

  @override
  String get expenseAmountLabel => 'Amount (KSh)';

  @override
  String get expenseCategoryLabel => 'Category';

  @override
  String get expenseNoteLabel => 'Note (optional)';

  @override
  String get expenseSaveAction => 'Record payout';

  @override
  String get expenseHistoryAction => 'Expense history';

  @override
  String get expenseHistoryTitle => 'Expenses';

  @override
  String get expenseHistoryEmpty => 'No payouts recorded yet.';

  @override
  String get expenseManagerOnly =>
      'Only the owner or manager can view expenses.';

  @override
  String get expenseHistoryTotal => 'Total paid out';

  @override
  String get tillMovementAction => 'Cash in/drop';

  @override
  String get tillMovementTitle => 'Cash in or drop';

  @override
  String get tillMovementSubtitle =>
      'Record cash entering or leaving this drawer.';

  @override
  String get tillMovementTypeLabel => 'Movement';

  @override
  String get tillCashInAction => 'Cash in';

  @override
  String get tillCashDropAction => 'Cash drop';

  @override
  String get tillMovementSaveAction => 'Record movement';

  @override
  String get shiftCloseCommitting => 'Closing';

  @override
  String get shiftCloseCountedMissing =>
      'Enter what is actually in the drawer.';

  @override
  String get shiftCloseFailed => 'Couldn\'t close the shift. Try again.';

  @override
  String shiftHistoryShiftCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shifts',
      one: '1 shift',
    );
    return '$_temp0';
  }

  @override
  String shiftHistoryOpener(Object amount) {
    return 'Opened with $amount';
  }

  @override
  String get shiftHistoryHiddenOne => 'and 1 earlier shift not shown';

  @override
  String shiftHistoryHiddenMany(Object count) {
    return 'and $count earlier shifts not shown';
  }

  @override
  String get shiftHistoryUnknownCashier => 'Unknown cashier';

  @override
  String shiftReconciliationsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count counts',
      one: '1 count',
    );
    return '$_temp0';
  }

  @override
  String get shiftReconciliationsAllBalanced =>
      'Every count on record balanced';

  @override
  String get shiftReconciliationsDidNotBalance => 'Did not balance';

  @override
  String get shiftReconciliationsAllBalancedChip => 'All balanced';

  @override
  String shiftReconciliationsOutOfCount(Object bad, Object total) {
    return '$bad of $total';
  }

  @override
  String get shiftReconciliationsNoneYet =>
      'No drawer has been counted and reconciled yet.';

  @override
  String shiftReconciliationsCountedOf(Object counted, Object expected) {
    return 'Counted $counted of $expected expected';
  }

  @override
  String get shiftCountSave => 'Save count';

  @override
  String get shiftCountSaving => 'Saving the count';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navDashboardShort => 'Home';

  @override
  String get navSell => 'Sell';

  @override
  String get navSellShort => 'Till';

  @override
  String get navInventory => 'Inventory';

  @override
  String get navInventoryShort => 'Stock';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navAnalyticsShort => 'Reports';

  @override
  String get navSettings => 'Settings';

  @override
  String get navSettingsShort => 'Shop';

  @override
  String get navMore => 'More';

  @override
  String get navMoreShort => 'More';

  @override
  String get navSupport => 'Support';

  @override
  String get navSupportShort => 'Help';

  @override
  String get navOpenBusiness => 'Business';

  @override
  String get navOpenBusinessShort => 'Biz';

  @override
  String get shellRoleOwner => 'Owner';

  @override
  String get shellAccountMenuLabel => 'Account and sign out';

  @override
  String get shellCreditMenuLabel => 'Credit customers';

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsEmpty => 'Nothing needs your attention right now.';

  @override
  String get notificationsLoadFailed =>
      'Notifications are unavailable right now.';

  @override
  String get businessToolsMarketplace => 'Business tools marketplace';

  @override
  String get marketplaceTitle => 'Business tools';

  @override
  String get marketplaceIntro => 'Make your shop more powerful';

  @override
  String get marketplaceDescription =>
      'Connect trusted tools for intelligence, reporting, people, money and customers. Your POS data stays yours.';

  @override
  String get marketplaceComingSoon => 'Coming soon';

  @override
  String get marketplaceStamp => 'COMING SOON';

  @override
  String get actionClose => 'Close';

  @override
  String get shellSignOutTooltip => 'Sign out';

  @override
  String shellSignedInAs(Object role, Object title) {
    return '$title, signed in as $role';
  }

  @override
  String get notFoundTitle => 'Page not found';

  @override
  String get notFoundHeading => 'That link does not go anywhere';

  @override
  String get notFoundBody => 'It may be from an older version of the app.';

  @override
  String notFoundPathLabel(Object path) {
    return 'Requested path: $path';
  }

  @override
  String get notFoundAction => 'Back to the till';

  @override
  String get databaseErrorTitle => 'This app could not open its data';

  @override
  String get databaseErrorBody =>
      'Nothing has been changed or deleted, but the app cannot read your inventory or sales right now.';

  @override
  String get databaseErrorAdvice =>
      'This usually follows a crash or a low-storage event. If you have a recent backup file, reinstalling the app and restoring that backup from Settings is the safest way forward.';

  @override
  String get databaseErrorRetryAction => 'Try again';

  @override
  String get databaseErrorShareAction => 'Copy diagnostics';

  @override
  String get databaseErrorSharedMessage =>
      'Diagnostics copied. Send them to support.';

  @override
  String get configurationErrorTitle => 'This build is not configured';

  @override
  String get configurationErrorBody =>
      'The app cannot reach your shop\'s server, so it cannot issue KRA receipts, take M-Pesa payments or sync.';

  @override
  String get configurationNoticeBody =>
      'This build has no server address, so KRA receipts, M-Pesa payments and syncing will not work. Selling, stock and reports work as usual, on this phone.';

  @override
  String get configurationErrorAdvice =>
      'This is a problem with how the app was built, not with your data. Your sales, stock and settings are safe on this phone.';

  @override
  String configurationErrorDetail(Object detail) {
    return 'Technical detail: $detail';
  }

  @override
  String get configurationErrorShareAction => 'Copy the details';

  @override
  String get configurationErrorSharedMessage =>
      'Details copied. Send them to whoever builds your app releases.';

  @override
  String get databaseErrorRetryFailed =>
      'Still cannot open the data. Free some storage, then try again.';

  @override
  String get sellBrowseProductsAction => 'Browse products';

  @override
  String get sellCompleteTitle => 'Sale recorded';

  @override
  String get sellCompleteFactPaid => 'Paid';

  @override
  String get sellCompleteFactChange => 'Change';

  @override
  String get sellCompleteFactTotal => 'Total';

  @override
  String get sellCompletePaidCash => 'Paid in cash';

  @override
  String get sellCompletePaidMpesa => 'Paid by M-Pesa';

  @override
  String get sellCompletePaidCard => 'Paid by card';

  @override
  String get sellCompletePaidBank => 'Paid by bank transfer';

  @override
  String get sellCompletePaidMobileMoney => 'Paid by mobile money';

  @override
  String get sellCompletePaidOtherGeneric => 'Paid';

  @override
  String sellCompletePaidOther(Object amount, Object method) {
    return '$method · $amount';
  }

  @override
  String get sellCompleteNext => 'Next sale';

  @override
  String get sellCompleteReceiptPending => 'The receipt is still printing.';

  @override
  String get sellCartEmptyHint => 'Tap products to add';

  @override
  String get sellCartEmptyMessage =>
      'Tap a product to add it, or scan its barcode. Nothing is charged until you press Charge.';

  @override
  String get sellCartEmptyTitle => 'The cart is empty';

  @override
  String get sellCartTitle => 'Cart';

  @override
  String sellTileStockCount(Object quantity) {
    return '$quantity in stock';
  }

  @override
  String get sellTileNoVariants => 'No variants yet';

  @override
  String sellTileFromPrice(Object price) {
    return 'From $price';
  }

  @override
  String sellTileSpokenProduct(Object name, Object price, Object stock) {
    return '$name, $price, $stock';
  }

  @override
  String sellTileSpokenVariants(
      Object name, Object price, Object stock, Object variants) {
    return '$name, from $price, $variants, $stock';
  }

  @override
  String get sellTileHintAddsToCart => 'Adds it to the cart';

  @override
  String get sellTileHintChoosesVariant => 'Opens the variants';

  @override
  String sellTileCartCount(Object count) {
    return '$count in the cart';
  }

  @override
  String get sellCatalogueEmptyMessage =>
      'Add products in Inventory and they can be sold here straight away.';

  @override
  String get sellCatalogueEmptyTitle => 'No products yet';

  @override
  String get sellCatalogueLoadFailedDetail =>
      'Selling needs the catalogue. Nothing has been charged.';

  @override
  String get sellCatalogueLoadFailedMessage =>
      'The product catalogue could not be read.';

  @override
  String sellCategorySpoken(Object category, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count products',
      one: '1 product',
    );
    return '$category, $_temp0';
  }

  @override
  String sellChargingAmount(Object amount) {
    return 'Charging $amount…';
  }

  @override
  String get sellCheckAgainAction => 'Check again';

  @override
  String get sellCheckAgainLater => 'Later';

  @override
  String sellCheckingPayment(Object reference) {
    return 'Checking payment $reference…';
  }

  @override
  String sellCheckPhoneForStk(Object phone) {
    return 'Check phone $phone for STK push';
  }

  @override
  String sellChooseServingTitle(Object product) {
    return 'Choose serving · $product';
  }

  @override
  String get sellClearFilterAction => 'Clear the filter';

  @override
  String get sellClearSearchTooltip => 'Clear product search';

  @override
  String get sellCustomerNameOptionalLabel => 'Customer Name (optional)';

  @override
  String sellDecreaseItem(Object item) {
    return 'Decrease $item';
  }

  @override
  String sellDecreaseQuantityOf(Object item) {
    return 'Decrease quantity of $item';
  }

  @override
  String sellIncreaseItem(Object item) {
    return 'Increase $item';
  }

  @override
  String sellIncreaseQuantityOf(Object item) {
    return 'Increase quantity of $item';
  }

  @override
  String get sellMpesaPaymentSuccessful =>
      'M-Pesa payment successful. Sale recorded.';

  @override
  String get sellMpesaPaymentTitle => 'M-Pesa Payment';

  @override
  String get sellNoMatchFilter => 'Nothing matches this filter';

  @override
  String sellNoMatchInCategory(Object category, Object query) {
    return 'Nothing matches \"$query\" in $category';
  }

  @override
  String get sellNoMatchMessage =>
      'Try a shorter name, or clear the filter to see everything in the catalogue.';

  @override
  String sellNoMatchQuery(Object query) {
    return 'Nothing matches \"$query\"';
  }

  @override
  String sellNoVariantsYetTitle(Object product) {
    return '$product has no variants yet';
  }

  @override
  String sellNothingInCategoryYet(Object category) {
    return 'Nothing in $category yet';
  }

  @override
  String get sellOfflinePaymentAction => 'Offline payment';

  @override
  String get sellOfflinePaymentTitle => 'Record offline payment';

  @override
  String get sellOutOfStock => 'Out of stock';

  @override
  String get sellPayAction => 'Pay';

  @override
  String sellPayByMethod(Object method) {
    return 'Pay by $method';
  }

  @override
  String get sellPaymentMethodLabel => 'Payment method';

  @override
  String sellPaymentReceivedSaleRecorded(Object reference) {
    return 'Payment $reference was received. The sale is now recorded.';
  }

  @override
  String get sellPaymentUnconfirmedTitle => 'Payment still unconfirmed';

  @override
  String get sellPhoneNumberLabel => 'Phone Number';

  @override
  String get sellProcessingMpesaTitle => 'Processing M-Pesa Payment';

  @override
  String get sellReceiptDidNotPrint =>
      'The sale is recorded, but the receipt did not print.';

  @override
  String get sellRecordSaleAction => 'Record sale';

  @override
  String sellReferenceDeclined(Object reference) {
    return 'Reference $reference was declined. Safe to retry.';
  }

  @override
  String get sellReferenceLabel => 'Reference (optional)';

  @override
  String sellReferenceValue(Object reference) {
    return 'Reference: $reference';
  }

  @override
  String get sellReloadCatalogueAction => 'Reload the catalogue';

  @override
  String sellRemoveItem(Object item) {
    return 'Remove $item';
  }

  @override
  String sellRemoveLineFromCart(Object item) {
    return 'Remove $item from the cart';
  }

  @override
  String get sellSaleNotRecordedNothingCharged =>
      'Couldn\'t record the sale. Nothing was charged — try again.';

  @override
  String sellSaleTotalLabel(Object amount) {
    return 'Sale total: $amount';
  }

  @override
  String get sellScanBarcode => 'Scan barcode';

  @override
  String get sellScanCameraHint =>
      'Adds one scanned product to the cart as a full bottle';

  @override
  String get sellScanCameraLabel => 'Scan a barcode with the camera';

  @override
  String get sellScanCameraError =>
      'Could not open the camera scanner. Try scanning with the hardware scanner, or pick the product by name.';

  @override
  String get sellPhoneNumberHint => '0712345678';

  @override
  String get sellScanNoProductBarcode =>
      'No product carries that barcode. Add it in Inventory — on the product or on one of its variants — or pick the product by name.';

  @override
  String get sellSearchNameOrCategory => 'Name or category';

  @override
  String get sellSearchProducts => 'Search products';

  @override
  String get sellShotsSection => 'Cups';

  @override
  String sellVariantCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count variants',
      one: '1 variant',
    );
    return '$_temp0';
  }

  @override
  String sellCartItemCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get inventoryAddAnotherVariant => 'Add another variant';

  @override
  String get inventoryAddBarcode => 'Add a barcode';

  @override
  String get inventoryAddFirstVariant => 'Add its first variant';

  @override
  String get inventoryAddProduct => 'Add product';

  @override
  String get inventoryManualRestock => 'Restock manually';

  @override
  String get settingsCreditSection => 'Credit sales';

  @override
  String get settingsCreditOffSummary =>
      'Off — on-account sales are not offered.';

  @override
  String settingsCreditOnSummary(Object limit) {
    return 'On — default limit $limit.';
  }

  @override
  String get settingsCreditEnabledLabel => 'Allow sales on account';

  @override
  String get settingsCreditDefaultLimitLabel => 'Default credit limit (KSh)';

  @override
  String get settingsCreditLimitModeLabel => 'Over-limit sales';

  @override
  String get settingsCreditLimitBlock => 'Require manager approval';

  @override
  String get settingsCreditLimitWarn => 'Warn, then allow';

  @override
  String get settingsCreditCashiersLabel => 'Allow cashiers to sell on account';

  @override
  String get settingsCreditReminderLabel => 'Payment reminder message';

  @override
  String get settingsCreditReminderHelper =>
      'Leave blank to use the default reminder.';

  @override
  String get settingsCreditSaveAction => 'Save credit settings';

  @override
  String get settingsCreditInvalidLimit => 'Enter a limit of 0 or more.';

  @override
  String get settingsCreditSaved => 'Credit settings saved.';

  @override
  String get inventoryEmptyTitle => 'No products yet';

  @override
  String get inventoryEmptyBody =>
      'Add your first product to start tracking stock and sales.';

  @override
  String inventoryAddVariantsFirst(Object name) {
    return 'Add $name\'s variants first — its stock is their total.';
  }

  @override
  String get inventoryAdjustAction => 'Adjust stock';

  @override
  String get inventoryAdjustStockFailed => 'Couldn’t adjust stock. Try again.';

  @override
  String inventoryAdjustStockTitle(Object name) {
    return 'Adjust stock — $name';
  }

  @override
  String get inventoryBarcodeHint => '6001234567892';

  @override
  String get inventoryBarcodeOnOtherProduct =>
      'That barcode is already on another product.';

  @override
  String get inventoryBarcodesHelp =>
      'A code on the product adds the whole product. A code on a variant — entered in that variant\'s own form — adds that variant, at its price and from its stock. Each code can only ever resolve to one of them.';

  @override
  String get inventoryBarcodesSection => 'Barcodes';

  @override
  String inventoryChooseVariantTitle(Object name) {
    return 'Which variant? · $name';
  }

  @override
  String get inventoryDefaultCategory => 'General';

  @override
  String get inventoryDeleteAction => 'Delete';

  @override
  String inventoryDeleteMessage(Object name) {
    return 'Remove $name from inventory? Its past sales stay on record.';
  }

  @override
  String inventoryDeactivatedProduct(Object name) {
    return 'deactivated $name';
  }

  @override
  String get inventoryDeleteTitle => 'Delete product?';

  @override
  String get inventoryDeltaLabel => 'Change (+50 restock, -2 breakage)';

  @override
  String get inventoryEditAction => 'Edit';

  @override
  String get inventoryActionsTooltip => 'Product actions';

  @override
  String get inventoryEditProduct => 'Edit product';

  @override
  String get inventoryExciseStampField => 'Excise stamp batch (optional)';

  @override
  String get inventoryFieldCategory => 'Category';

  @override
  String get inventoryFieldCostPrice => 'Cost price';

  @override
  String get inventoryFieldHalfPrice => 'Half price';

  @override
  String get inventoryFieldHalfPriceOptional => 'Half price (optional)';

  @override
  String get inventoryFieldHalfPriceHelper =>
      'Only products with a half price are sold in halves. Leave it empty and the till will not offer a half.';

  @override
  String get inventoryFieldName => 'Name';

  @override
  String get inventoryFieldQuarterPrice => 'Quarter price';

  @override
  String get inventoryFieldQuarterPriceOptional => 'Quarter price (optional)';

  @override
  String get inventoryFieldQuarterPriceHelper =>
      'Only products with a quarter price are sold in quarters. Leave it empty and the till will not offer a quarter.';

  @override
  String get inventoryPhotoSection => 'Photograph';

  @override
  String get inventoryPhotoHelp =>
      'Shown on the till so a cashier can match the shelf. Not shown anywhere else in the app.';

  @override
  String get inventoryPhotoFromGallery => 'Choose from gallery';

  @override
  String get inventoryPhotoFromCamera => 'Take a photo';

  @override
  String get inventoryPhotoAdd => 'Add a photograph';

  @override
  String get inventoryPhotoRemovedNote =>
      'The photograph will be removed when you save.';

  @override
  String get inventoryPhotoChange => 'Change photograph';

  @override
  String get inventoryPhotoRemove => 'Remove photograph';

  @override
  String get inventoryPhotoAddFailed =>
      'The photograph could not be saved. Check the phone has storage space free, then try again.';

  @override
  String get inventoryPhotoRemoveFailed =>
      'The photograph could not be removed. Try again.';

  @override
  String get inventoryFieldReorderLevel => 'Reorder level';

  @override
  String get inventoryFieldSellPrice => 'Sell price';

  @override
  String get inventoryFieldSizeMl => 'Size (ml)';

  @override
  String get inventoryFieldSizeMlHelper =>
      'Bottle, keg or tank — 330, 500, 50000';

  @override
  String get productUnitPickerLabel => 'How this product is measured';

  @override
  String get productUnitEach => 'Counted';

  @override
  String get productUnitLitre => 'By the litre';

  @override
  String get productUnitMillilitre => 'By the millilitre';

  @override
  String get productUnitCup => 'By the cup';

  @override
  String get productSizeLabelLitre => 'How many ml one litre holds';

  @override
  String get productSizeLabelMillilitre => 'How many ml one unit holds';

  @override
  String get productSizeLabelCup => 'How many ml one cup holds';

  @override
  String get productUnitCupPourHint =>
      'Cups are poured from a bigger container: add that container, then configure its cups in Inventory.';

  @override
  String get inventoryFieldStock => 'Stock';

  @override
  String get inventoryFieldStockQty => 'Stock qty';

  @override
  String inventoryFieldStockQtyUnit(Object unit) {
    return 'Stock qty ($unit)';
  }

  @override
  String inventoryFieldReorderLevelUnit(Object unit) {
    return 'Reorder level ($unit)';
  }

  @override
  String get unitSuffixEach => 'items';

  @override
  String get unitSuffixLitre => 'L';

  @override
  String get unitSuffixMillilitre => 'ml';

  @override
  String get unitSuffixCup => 'cups';

  @override
  String get unitSuffixKilogram => 'kg';

  @override
  String get inventoryFieldTotalStock => 'Total stock (from variants)';

  @override
  String get inventoryGoBack => 'Go back';

  @override
  String get inventoryLowStockLimitTitle => 'Low stock limit';

  @override
  String inventoryLowStockLimitSubtitle(Object limit) {
    return 'Every product warns below $limit. Tap to change.';
  }

  @override
  String inventoryLowStockLimitAudit(num count, Object limit) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count products',
      one: '1 product',
      zero: 'No products',
    );
    return '$_temp0 low-stock limit set to $limit';
  }

  @override
  String inventoryLowStockLimitApplied(num count, Object limit) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count products now warn below $limit',
      one: '1 product now warns below $limit',
      zero: 'No products to set',
    );
    return '$_temp0';
  }

  @override
  String get importsTitle => 'Import problems';

  @override
  String get importsEmptyTitle => 'Nothing waiting on you';

  @override
  String get importsEmptyMessage =>
      'Every row from the last import was either written or answered. Import a spreadsheet to add stock in bulk.';

  @override
  String get importsLoadFailed =>
      'Couldn\'t read the import list. Try again; if it keeps happening, contact support.';

  @override
  String get importsCompleteAction => 'Fill in what\'s missing';

  @override
  String get importsCompleteTitle => 'Finish this row';

  @override
  String get importsPriceLabel => 'This price';

  @override
  String get importSaveFailed =>
      'That row could not be saved. Try again; if it keeps happening, contact support.';

  @override
  String inventoryLowPriceMessage(Object cost, Object name, Object price) {
    return '$name would sell at a loss (KSh $price vs cost KSh $cost). Save anyway?';
  }

  @override
  String get inventoryLowPriceTitle => 'Sell price is below cost';

  @override
  String get inventoryInStock => 'In stock';

  @override
  String get inventoryLowStock => 'low stock';

  @override
  String get inventoryOutOfStock => 'Out of stock';

  @override
  String get inventoryNewVariantName => 'New variant';

  @override
  String get inventoryNoBarcodesYet =>
      'No barcodes yet — this product is sold by name only.';

  @override
  String get inventoryNoVariantsYet => 'no variants yet';

  @override
  String get inventoryReasonLabel => 'Reason';

  @override
  String get inventoryRemoveAction => 'Remove';

  @override
  String get inventoryRemoveVariantBarcodeFreed =>
      'Its barcode is freed so another variant can use it. Sales already recorded keep the name they were sold under.';

  @override
  String get inventoryRemoveVariantStopsSelling =>
      'It stops being offered at the till. Sales already recorded keep the name they were sold under.';

  @override
  String inventoryRemoveVariantTitle(Object name) {
    return 'Remove $name?';
  }

  @override
  String get inventorySaveAction => 'Save';

  @override
  String get inventorySaveAnyway => 'Save anyway';

  @override
  String get inventorySaveBeforeBarcode =>
      'Save the product first, then add its barcode(s).';

  @override
  String get inventorySaveFailed =>
      'Couldn’t save — check the phone has storage space free, then try again.';

  @override
  String inventorySaveProductAndVariants(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Save product and $count variants',
      one: 'Save product and 1 variant',
      zero: 'Save product',
    );
    return '$_temp0';
  }

  @override
  String get inventoryShotCupsSpoken =>
      'Cups. Fixed-size cups of any drink in your inventory.';

  @override
  String get inventoryShotCupsTitle => 'Cups';

  @override
  String get inventorySizeSuggestionsSpoken => 'Sizes you have used before';

  @override
  String get inventorySoldAsVariants => 'Sold as variants';

  @override
  String get inventorySoldAsVariantsOffSubtitle =>
      'For Dark and Regular, or a big cup and a small cup, at different prices';

  @override
  String get inventorySoldAsVariantsOnSubtitle =>
      'The till offers Dark, Regular, Big cup… instead of the whole product';

  @override
  String get inventoryStockCannotGoBelowZero =>
      'Stock cannot go below zero. Check the current quantity and try again.';

  @override
  String get inventoryStockSavedLocally =>
      'Stock updated on this till. The online count will catch up on the next sync.';

  @override
  String get inventoryStockUpdateFailed =>
      'Stock update failed. Refresh the inventory and try again.';

  @override
  String get inventoryThisProduct => 'This product';

  @override
  String inventoryUnnamedVariant(Object position) {
    return 'Give every variant a name — one of them has none (position $position).';
  }

  @override
  String inventoryVariantStockNow(Object count, Object name) {
    return '$name is now $count in stock.';
  }

  @override
  String get inventoryVariantsSection => 'Variants';

  @override
  String get settingsAddShopOnDeviceAction => 'Add another shop on this device';

  @override
  String get settingsAddShopTitle => 'Add another shop';

  @override
  String get settingsAddStaffAction => 'Add staff';

  @override
  String get settingsAutoBackupSync => 'Automatic backup and online sync';

  @override
  String get settingsBackupSection => 'Backup';

  @override
  String get profileTitle => 'Your account';

  @override
  String get profileNoAccountYet => 'No account is set up yet.';

  @override
  String get profileEditAction => 'Edit';

  @override
  String get profileEditTitle => 'Edit your details';

  @override
  String get profileEditNameLabel => 'Your name';

  @override
  String get profileEditNameHelp => 'Shown on the till and on the receipts.';

  @override
  String get profileEditShopNameLabel => 'Shop name';

  @override
  String get profileEditEmailLabel => 'Email';

  @override
  String get profileEditEmailHelp =>
      'Where PIN-recovery and verification codes are sent.';

  @override
  String get profileEditEmailWarning =>
      'Changing the email moves where recovery codes are sent. A new address has to be verified before it can be used to recover the PIN, and until it is, keep the old one working.';

  @override
  String get profileEditSave => 'Save';

  @override
  String get profileEditSaved => 'Your details were saved.';

  @override
  String get profileEditFailed =>
      'Your details could not be saved. Nothing was changed.';

  @override
  String get profilePhotoLabel => 'Photograph';

  @override
  String get profilePhotoHelp =>
      'Shown next to your name. Pick one from the gallery or take a photo.';

  @override
  String get profilePhotoChange => 'Choose';

  @override
  String get profilePhotoSaved => 'Photograph saved.';

  @override
  String get profileEmailLabel => 'Email';

  @override
  String get profileVerifiedLabel => 'Verified';

  @override
  String get profileVerifiedYes => 'Verified';

  @override
  String get profileVerifiedNo => 'Not verified yet';

  @override
  String get profileSinceLabel => 'Selling since';

  @override
  String get profileShopLabel => 'Shop';

  @override
  String get profileBackToSettings => 'Back to settings';

  @override
  String get statusDeletionPending =>
      'Your online account could not be deleted yet. It will be deleted the next time this till can reach the server.';

  @override
  String get statusBackupOverdue =>
      'This phone has not been backed up for a while.';

  @override
  String get statusOffline =>
      'This till is offline. Sales are still being recorded.';

  @override
  String get statusConnecting => 'Reconnecting to the server.';

  @override
  String get importRepairedTitle => 'Row repaired';

  @override
  String get importRepairFailedTitle => 'The row was not repaired';

  @override
  String get profileEditSavedTitle => 'Details saved';

  @override
  String get profileEditFailedTitle => 'The details were not saved';

  @override
  String get inventoryProductSavedTitle => 'Product saved';

  @override
  String get inventoryProductUpdatedTitle => 'Product updated';

  @override
  String get inventoryStockSavedTitle => 'Stock updated';

  @override
  String get settingsBackupsErasedTitle => 'Backups erased';

  @override
  String get settingsBackupsEraseFailedTitle =>
      'Some backups could not be erased';

  @override
  String get settingsMpesaUpdateFailedTitle => 'The setting was not saved';

  @override
  String get settingsIdentityVerifiedTitle => 'Identity verified';

  @override
  String get settingsSyncDoneTitle => 'Sync finished';

  @override
  String get settingsStaffSavedTitle => 'Cashier saved';

  @override
  String get settingsStaffSaveFailedTitle => 'The cashier was not saved';

  @override
  String get settingsStaffRemovedTitle => 'Cashier removed';

  @override
  String get settingsStaffRemoveFailedTitle => 'The cashier was not removed';

  @override
  String get settingsPinResetTitle => 'PIN reset';

  @override
  String get settingsBackupDoneTitle => 'Backup made';

  @override
  String get settingsBackupDone =>
      'The encrypted backup was made and is ready to share.';

  @override
  String get settingsBackupFailedTitle => 'The backup failed';

  @override
  String get settingsBackupFailed =>
      'The backup could not be made. The data on this phone is unchanged, and nothing was shared.';

  @override
  String get settingsExportDoneTitle => 'Export ready';

  @override
  String get settingsExportEncryptedDone =>
      'The encrypted backup file is ready to share.';

  @override
  String get settingsExportInventoryDone =>
      'The inventory workbook is ready to share.';

  @override
  String get settingsExportFailedTitle => 'The export failed';

  @override
  String get settingsExportFailed =>
      'The file could not be made. Nothing was shared.';

  @override
  String get settingsRestoreDoneTitle => 'Backup restored';

  @override
  String get settingsRestoreFailedTitle => 'The backup was not restored';

  @override
  String get settingsImportDoneTitle => 'Import complete';

  @override
  String get settingsImportFailedTitle => 'The import failed';

  @override
  String get settingsUpdateFailedTitle => 'The update was not installed';

  @override
  String get settingsAccountSection => 'Your account';

  @override
  String get settingsProfileRow => 'Your account';

  @override
  String get settingsUpdatesSection => 'App updates';

  @override
  String get settingsUpdatesCheck => 'Check for updates';

  @override
  String settingsUpdatesAvailable(Object version) {
    return 'Version $version is ready';
  }

  @override
  String settingsUpdatesFailed(Object reason) {
    return 'Could not check for updates: $reason';
  }

  @override
  String get settingsUpdatesReasonUnreachable =>
      'the server could not be reached';

  @override
  String get settingsUpdatesReasonMalformed =>
      'the server did not send a release';

  @override
  String settingsUpdatesCurrent(Object version) {
    return 'You are on the newest version ($version)';
  }

  @override
  String get settingsUpdatesUnknownVersion => 'unknown';

  @override
  String get settingsUpdatesInstall => 'Install now';

  @override
  String settingsUpdatesDownloading(Object percent) {
    return 'Downloading $percent%';
  }

  @override
  String get settingsUpdatesDownloadingUnknown => 'Downloading…';

  @override
  String get settingsUpdatesReady => 'Downloaded. Tap install to apply it.';

  @override
  String get settingsUpdatesNoNotes =>
      'No release notes were published for this version.';

  @override
  String get settingsUpdatesRefused =>
      'The phone refused this update. It can only be installed over the same signing key and a higher build number — ask the shop\'s developer.';

  @override
  String get settingsUpdatesPermissionNeeded =>
      'This phone needs permission to install apps. Settings has opened.';

  @override
  String get settingsUpdatesPermissionManual =>
      'This phone needs permission to install apps. Allow it in Settings, then tap install again.';

  @override
  String get settingsUpdatesRestart => 'Restart to update';

  @override
  String settingsUpdatesPromptBody(Object version) {
    return 'Version $version is ready. Your shop\'s data is kept — this updates the app in place instead of replacing it.';
  }

  @override
  String get settingsUpdatesAutoLabel => 'Auto-update when idle';

  @override
  String get settingsUpdatesAutoSubtitle =>
      'Downloads and installs updates while the till is quiet, so the shop never has to stop selling.';

  @override
  String get supportTitle => 'Support';

  @override
  String get supportTicketsSection => 'Support tickets';

  @override
  String get supportTicketsSubtitle =>
      'Tell us what is broken so we can fix it.';

  @override
  String get supportNoTickets => 'No support tickets yet. File one below.';

  @override
  String get supportFileTicketLabel => 'What is wrong?';

  @override
  String get supportTicketHint =>
      'Describe the problem — what you were doing, what happened, and what you expected instead.';

  @override
  String get supportFileTicketAction => 'File ticket';

  @override
  String get supportFeatureRequestsSection => 'Feature requests';

  @override
  String get supportFeatureRequestsSubtitle => 'Tell us what you need next.';

  @override
  String get supportNoRequests => 'No feature requests yet. File one below.';

  @override
  String get supportFileRequestLabel => 'What would you like?';

  @override
  String get supportRequestHint =>
      'Describe the feature — what it should do, and when you would use it.';

  @override
  String get supportFileRequestAction => 'File request';

  @override
  String get supportDescriptionLabel => 'Description';

  @override
  String get supportDescriptionHint => 'More detail helps us fix it faster.';

  @override
  String get settingsCashMethod => 'Cash';

  @override
  String get settingsPrinterRescan => 'Look again';

  @override
  String get settingsPrinterScanFailed =>
      'Could not read the Bluetooth devices. Check Bluetooth is on, then look again.';

  @override
  String get settingsNoPairedPrintersHint =>
      'Pair the printer in this phone\'s Bluetooth settings first, then look again.';

  @override
  String get settingsChoosePrinter => 'Choose printer';

  @override
  String get settingsConnectAction => 'Connect';

  @override
  String get settingsConnectFailed =>
      'Couldn’t connect. Check the identity login and internet connection.';

  @override
  String get settingsConnectMpesaTitle => 'Connect M-Pesa';

  @override
  String get settingsCreateShopFailed =>
      'Couldn’t create the shop. Check the phone has storage free, then try again.';

  @override
  String get settingsDecryptBackupFailed => 'Couldn’t decrypt the backup.';

  @override
  String get settingsEnterStaffName => 'Enter a staff name';

  @override
  String get settingsEraseBackupsConfirm => 'Erase local backups';

  @override
  String get settingsEraseBackupsMessage =>
      'This permanently removes this phone’s backup key and encrypted backup files. Copies already shared to another device or cloud storage are not erased.';

  @override
  String get settingsEraseBackupsTitle => 'Erase encrypted backups?';

  @override
  String get settingsEraseLocalBackupsAction => 'Erase local encrypted backups';

  @override
  String get settingsDeleteAccountAction => 'Delete account';

  @override
  String get accountDeleteLocalAccountsTitle =>
      'Delete the cashier logins on this phone?';

  @override
  String get accountDeleteLocalAccountsMessage =>
      'The cashiers’ sign-in details are removed from this phone, so nobody can sign in to this till afterwards. Their names on past sales stay, because those are the shop’s records.';

  @override
  String get accountDeleteLocalAccountsDelete => 'Delete them';

  @override
  String get accountDeleteLocalAccountsKeep => 'Keep them';

  @override
  String get accountDeleteLocalAccountsRemoved =>
      'The cashier logins on this phone were deleted. Nobody can sign in to this till.';

  @override
  String get accountDeleteLocalAccountsSealed =>
      'The cashier logins on this phone were sealed: they cannot be used, but the records of them were kept.';

  @override
  String settingsBackupsErasedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count backup files were erased.',
      one: 'One backup file was erased.',
      zero: 'No backup files were on this phone.',
    );
    return '$_temp0';
  }

  @override
  String get settingsBackupsEraseFailed =>
      'The backup files could not all be erased. The key is gone, so anything left cannot be read, but there may be a file left on the phone.';

  @override
  String get accountDeleteConfirmTitle => 'Delete this account for good?';

  @override
  String get accountDeleteConfirmMessage =>
      'Your online account and this shop’s record of it are deleted. Everything on this phone that names or contacts a person — your name, your email, your PIN, the cashiers, the till numbers — is overwritten with unreadable data, and the key that would read it back is destroyed. The takings and stock figures themselves are left alone, because those are your books.\n\nAny encrypted backup taken before today is also made unreadable. This cannot be undone.';

  @override
  String get accountDeleteConfirmAction => 'Delete and erase';

  @override
  String get accountDeleteDoneTitle => 'Account deleted';

  @override
  String get accountDeleteDoneRemote =>
      'The online account is deleted on the server as well as on this phone. Keep the receipt below.';

  @override
  String get accountDeleteDoneLocalOnly =>
      'This phone no longer holds any of your details. The server could not be reached, so ask it to finish the deletion when you are back online — the receipt below is what to quote.';

  @override
  String accountDeleteReceipt(Object at, Object id) {
    return 'Deletion reference: $id\nCompleted: $at';
  }

  @override
  String get accountDeleteCompactionPending =>
      'The data is unreadable, but the file was never fully rewritten. Open the app again with free storage to finish the job.';

  @override
  String get accountDeleteErasureFailed =>
      'The account was not deleted because the erasure could not finish. Nothing was changed.';

  @override
  String get settingsForgotPinAction => 'Forgot PIN?';

  @override
  String get pinResetRowSubtitle => 'Email a code and set a new owner PIN';

  @override
  String get pinResetTitle => 'Set a new owner PIN';

  @override
  String pinResetIntro(Object email) {
    return 'We will email a 6-digit code to $email. It proves the phone belongs to you, which is the only way a forgotten PIN can be reset.';
  }

  @override
  String get pinResetSendCode => 'Email me a code';

  @override
  String get pinResetSending => 'Sending…';

  @override
  String get pinResetResend => 'Send another code';

  @override
  String get pinResetSaving => 'Saving…';

  @override
  String pinResetSentTo(Object email) {
    return 'Code sent to $email. Enter it here, then your new PIN. Check spam if you don’t see it.';
  }

  @override
  String get pinResetCodeLabel => 'Code from the email';

  @override
  String get pinResetNewPinLabel => 'New PIN';

  @override
  String get pinResetNewPinAgainLabel => 'New PIN again';

  @override
  String get pinResetPinsDiffer => 'The two PINs do not match.';

  @override
  String get pinResetPinShape => 'A PIN is exactly six digits.';

  @override
  String get pinResetCodeWrong =>
      'That code is not right. Check your email and try again.';

  @override
  String get pinResetOffline =>
      'No connection. A PIN reset needs the server to email you a code, so it cannot run offline.';

  @override
  String get pinResetTimeout => 'The server did not answer in time. Try again.';

  @override
  String get pinResetTooMany =>
      'Too many attempts. Wait a few minutes, then ask for a new code.';

  @override
  String get pinResetNoEmail =>
      'This shop has no email on record, so there is nowhere to send a code. Add and verify an email first.';

  @override
  String get pinResetStartOver => 'That code has expired. Ask for a new one.';

  @override
  String get pinResetServer =>
      'The server refused the reset. Try again shortly.';

  @override
  String get pinResetDone =>
      'Your owner PIN has been changed. Use the new one from now on.';

  @override
  String get settingsExportEncrypted => 'Export encrypted backup (.duka)';

  @override
  String get settingsExportInventory => 'Export inventory (.xlsx)';

  @override
  String get settingsIdentityLinkFailed =>
      'Could not link your online account. Check your connection and sign in with the same email you entered during setup.';

  @override
  String get settingsIdentityLinked =>
      'Online identity linked. M-Pesa and analytics are now available.';

  @override
  String get settingsIdentityVerified =>
      'Signed in. Auto-backups, analytics and auto-update are now on.';

  @override
  String get settingsIdentityNotLinkedMessage =>
      'Selling works fully offline. Verify your email to switch on auto-backups, analytics and auto-update.';

  @override
  String get settingsIdentityNotLinkedTitle =>
      'Verify your email to finish setup';

  @override
  String get settingsVerifyPinTitle => 'Enter your admin PIN';

  @override
  String settingsVerifyPinMessage(Object email) {
    return 'Confirm you are the shop admin with your 6-digit PIN. Your online account is created for $email, and we will send a 6-digit code to that address to prove it is yours.';
  }

  @override
  String get settingsVerifyPinWrong =>
      'That is not the admin PIN for this shop.';

  @override
  String get settingsVerifyPinLabel => '6-digit admin PIN';

  @override
  String get settingsVerifyPinInvalid => 'Enter the 6-digit admin PIN';

  @override
  String get settingsVerifyCodeTitle => 'Enter the code we emailed';

  @override
  String settingsVerifyCodeMessage(Object email, Object minutes) {
    return 'We sent a 6-digit code to $email. It expires in $minutes minutes.\n\nAfter you enter it, sign in with your email and the same 6-digit PIN you use on this till.';
  }

  @override
  String settingsVerifyPinLocked(Object seconds) {
    return 'Too many wrong PINs on this till. Try again in ${seconds}s.';
  }

  @override
  String get settingsVerifyCodeLabel => '6-digit code';

  @override
  String get settingsVerifyCodeInvalid => 'Enter the 6-digit code';

  @override
  String settingsVerifyCodeSent(Object email) {
    return 'Code sent to $email. Check spam if you don’t see it.';
  }

  @override
  String settingsVerifyCodeWrong(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'That code is not right. $count attempts left.',
      one: 'That code is not right. 1 attempt left.',
    );
    return '$_temp0';
  }

  @override
  String get settingsVerifyCodeExpired =>
      'That code has expired. Send a new one and try again.';

  @override
  String get settingsVerifyCodeBurnt =>
      'Too many wrong attempts. Send a new code and try again.';

  @override
  String get settingsVerifyResendAction => 'Send a new code';

  @override
  String get settingsVerifyTooManyCodes =>
      'Too many codes requested. Wait a few minutes before asking for another.';

  @override
  String get settingsVerifyNotConfigured =>
      'This server cannot verify emails yet. Try again later.';

  @override
  String get settingsVerifyEmailFailed =>
      'The email could not be sent. Check your connection and send a new code.';

  @override
  String get settingsVerifyIdentityUnavailable =>
      'Could not reach the account server. Try again when you have signal.';

  @override
  String get settingsVerifyShopMissing =>
      'This account has no shop yet. Finish shop setup first.';

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get diagnosticsRecentTitle => 'Recent failures';

  @override
  String diagnosticsRecentCount(Object cap, num count, Object days) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count failures kept',
      one: '1 failure kept',
    );
    return '$_temp0 — the last $days weeks, newer than $cap rows are not kept';
  }

  @override
  String get diagnosticsEmptyTitle => 'Nothing has gone wrong lately';

  @override
  String get diagnosticsEmptyMessage =>
      'When something fails, the app records what it was doing and keeps it here. The newest failures replace the oldest, so this list never grows without limit.';

  @override
  String get diagnosticsUnreadableTitle => 'The failure log could not be read';

  @override
  String get diagnosticsUnreadableMessage =>
      'The log is on this phone, but it did not open. That is itself worth reporting — refresh to try again, and send this screen to the shop\'s developer.';

  @override
  String get diagnosticsTrailTitle => 'What the shop was doing';

  @override
  String get diagnosticsStackTitle => 'Stack trace';

  @override
  String get diagnosticsCopyReport => 'Copy report';

  @override
  String get diagnosticsLedgerCheckTitle => 'Stock ledger';

  @override
  String get diagnosticsLedgerCheckSubtitle =>
      'Every stock count, checked against the history that produced it.';

  @override
  String get diagnosticsLedgerHealthy => 'Every count agrees with its history.';

  @override
  String get diagnosticsLedgerChecking => 'Checking the stock ledger…';

  @override
  String diagnosticsLedgerDifferences(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count products do not agree',
      one: '1 product does not agree',
    );
    return '$_temp0';
  }

  @override
  String diagnosticsLedgerDifferenceRow(
      Object counted, Object ledger, Object name) {
    return '$name: the till says $counted, the history says $ledger';
  }

  @override
  String get diagnosticsLedgerRepairAction => 'Fix';

  @override
  String diagnosticsLedgerRepaired(Object name) {
    return '$name now agrees with its history.';
  }

  @override
  String diagnosticsLedgerRepairFailed(Object name) {
    return 'Could not correct $name. Try again.';
  }

  @override
  String get diagnosticsClear => 'Clear log';

  @override
  String get diagnosticsClearConfirmTitle => 'Clear the failure log?';

  @override
  String get diagnosticsClearConfirmMessage =>
      'The recorded failures will be deleted from this device. This cannot be undone.';

  @override
  String get diagnosticsReportCopied => 'Report copied to the clipboard.';

  @override
  String get diagnosticsCleared => 'Failure log cleared.';

  @override
  String get diagnosticsRouteUnknown => 'unknown screen';

  @override
  String get diagnosticsActorUnknown => 'unknown user';

  @override
  String get diagnosticsActionUnknown => 'nothing in particular';

  @override
  String diagnosticsEntryContext(Object action, Object actor, Object route) {
    return 'on $route · $actor · $action';
  }

  @override
  String get settingsImportInventory => 'Import inventory (.xlsx)';

  @override
  String get settingsImportStageReading => 'Reading the workbook…';

  @override
  String get settingsImportStageParsing => 'Reading the rows…';

  @override
  String get settingsImportStageWriting => 'Writing the products…';

  @override
  String get settingsImportStageBarcodes => 'Attaching the barcodes…';

  @override
  String get settingsImportStageVariants => 'Attaching the variants…';

  @override
  String get settingsImportStageDone => 'Done.';

  @override
  String settingsImportProgressPercent(Object percent, Object stage) {
    return '$stage $percent%';
  }

  @override
  String get settingsImportWorkbookFailed =>
      'Couldn’t import the workbook. Check the file and try again.';

  @override
  String get importNotOurFormat =>
      'That file isn’t in this app’s inventory format, so nothing was imported. Add a header row to the sheet — Name, Cost price, Selling price, Stock qty — or export a template from Settings and paste your rows into it.';

  @override
  String get settingsIncluded => 'Included';

  @override
  String get settingsInvalidEncryptedBackup =>
      'That encrypted backup is invalid or belongs to another installation.';

  @override
  String get settingsInvalidWorkbook =>
      'That workbook has invalid inventory data. No products were imported.';

  @override
  String get settingsLoadShopsFailed =>
      'Could not read the shops on this device.';

  @override
  String get settingsOneShopOnDevice =>
      'Only one shop is set up on this device. Add another here and you can move between them.';

  @override
  String get settingsCurrentShop => 'Current shop';

  @override
  String get settingsLinkedShop => 'Linked to the backend';

  @override
  String get settingsLocalOnlyShop => 'On this device only';

  @override
  String settingsSwitchedToShop(Object name) {
    return 'Switched to $name. Its stock, sales and staff are kept separate.';
  }

  @override
  String get settingsMpesaMethod => 'M-Pesa';

  @override
  String get settingsMpesaOffSubtitle =>
      'Excluded — turn on to accept M-Pesa. Requires a one-time backend connection.';

  @override
  String get settingsMpesaOnSubtitle =>
      'Included — customers can pay by M-Pesa STK push. Requires internet at checkout.';

  @override
  String get settingsMpesaUpdateFailed =>
      'Couldn’t update M-Pesa setting — check your connection and try again.';

  @override
  String get settingsNoOnlineShops =>
      'No online shops are linked to this identity yet.';

  @override
  String get settingsPairAPrinter => 'Pair a printer';

  @override
  String get settingsPairAPrinterFirst => 'Pair a printer first.';

  @override
  String get settingsPairAnotherPrinter => 'Pair another';

  @override
  String get settingsPaymentChannelId => 'Payment channel ID';

  @override
  String get settingsPaymentMethodsSection => 'Payment methods';

  @override
  String get settingsPinLabel => '4-digit PIN';

  @override
  String get settingsPrintAfterSale => 'Print after every sale';

  @override
  String get settingsPrinterConnectionDropped =>
      'The printer connection dropped. Check the printer is on, then print again.';

  @override
  String get settingsPrinterDisabled => 'Printing is switched off.';

  @override
  String get settingsPrinterNotPaired =>
      'That printer is not paired with this phone. Pair it from the phone\'s Bluetooth settings first.';

  @override
  String settingsPrinterPermissionDenied(Object app) {
    return 'Bluetooth permission was turned off for $app. Open the phone’s app settings and allow Bluetooth.';
  }

  @override
  String settingsPrinterPermissionNeeded(Object app) {
    return '$app needs permission to use Bluetooth. Allow it in Settings, then try again.';
  }

  @override
  String get settingsPrinterSection => 'Receipt printer';

  @override
  String get settingsPrinterUnavailable =>
      'Bluetooth is switched off on this phone, or it has no Bluetooth.';

  @override
  String get settingsPrinterUnreachable =>
      'Could not reach the printer. Check it is switched on and in range, then try again.';

  @override
  String get settingsPrintingEnabled => 'Printing enabled';

  @override
  String get settingsPrintingOnSubtitle => 'This till can print receipts.';

  @override
  String get settingsPrintingPairedOffSubtitle =>
      'Paired, but switched off. Reprints still work.';

  @override
  String get settingsRemoveAction => 'Remove';

  @override
  String get settingsRemoveStaffTitle => 'Remove staff member?';

  @override
  String get settingsResetPinAction => 'Reset PIN';

  @override
  String get settingsRestoreEncrypted => 'Restore encrypted backup';

  @override
  String get settingsRoleCashier => 'Cashier';

  @override
  String get settingsRoleLabel => 'Role';

  @override
  String get settingsRoleManager => 'Manager';

  @override
  String get settingsSaveAction => 'Save';

  @override
  String get settingsSeparateOfflineDataTitle =>
      'Each shop has separate offline data';

  @override
  String get settingsShopNameLabel => 'Shop name';

  @override
  String get settingsShopNotOnDevice => 'Set this shop up on this device first';

  @override
  String get settingsSignInBeforeAddingShop =>
      'Sign in as the shop admin before adding another shop.';

  @override
  String get settingsStaffNameLabel => 'Name';

  @override
  String get settingsStaffRemovedOffline =>
      'Cashier removed locally. Backend access will be updated on the next successful sync.';

  @override
  String get settingsStaffSavedOffline =>
      'Cashier saved offline. It will be linked to the backend on the next successful sync.';

  @override
  String get settingsStaffEmpty => 'No managers or cashiers yet.';

  @override
  String settingsStaffActionsTooltip(Object name) {
    return 'Actions for $name';
  }

  @override
  String settingsStaffNameTaken(Object name) {
    return 'A staff member named \"$name\" already exists';
  }

  @override
  String get settingsAddStaffFailed => 'Couldn’t add staff — try again.';

  @override
  String get settingsResetPinFailed => 'Couldn’t reset PIN — try again.';

  @override
  String get settingsRemoveStaffFailed => 'Couldn’t remove staff — try again.';

  @override
  String settingsRemoveStaffMessage(Object name) {
    return '$name will no longer be able to sign in. Their past sales stay on record.';
  }

  @override
  String get settingsConnectMpesaMessage =>
      'The platform connects this shop to M-Pesa through PayHero. Enter only the shop Till or Paybill number; PayHero credentials stay on the backend. Staff continue using local PINs for the till.';

  @override
  String get settingsPaymentChannelHint =>
      'Enter the shop Till or Paybill number. The platform registers the payment channel for you.';

  @override
  String get settingsStaffSection => 'Managers and cashiers';

  @override
  String get settingsSwitchAction => 'Switch';

  @override
  String get settingsSwitchShopAction => 'Switch linked shop';

  @override
  String get settingsSwitchShopFailed => 'Could not switch shops';

  @override
  String get settingsSyncFailed =>
      'Sync failed — try again when you have signal.';

  @override
  String get settingsSyncNowAction => 'Sync now';

  @override
  String get settingsSyncOfflineExcel =>
      'No internet — saved an Excel file instead. Share it from the prompt that opened.';

  @override
  String get settingsSyncSection => 'Sync — Google Sheets & Excel';

  @override
  String get settingsSyncSheets => 'Synced to Google Sheets just now.';

  @override
  String get settingsSyncing => 'Syncing…';

  @override
  String get settingsTestPrintAction => 'Test print';

  @override
  String get settingsTestReceiptSent => 'Test receipt sent.';

  @override
  String get settingsVerifyAction => 'Verify';

  @override
  String settingsShopReady(Object name) {
    return '$name is ready. Your admin account and PIN carried across.';
  }

  @override
  String settingsPaperRoll(Object size) {
    return '${size}mm roll';
  }

  @override
  String settingsTaxSummary(Object rate, Object till) {
    return 'VAT $rate% · receipts numbered $till-000001';
  }

  @override
  String settingsTaxSummaryWithTin(Object rate, Object till, Object tin) {
    return 'VAT $rate% · TIN $tin · receipts numbered $till-000001';
  }

  @override
  String settingsRestoredProducts(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Restored $count products',
      one: 'Restored 1 product',
    );
    return '$_temp0';
  }

  @override
  String settingsImportedProducts(num products) {
    String _temp0 = intl.Intl.pluralLogic(
      products,
      locale: localeName,
      other: 'Imported $products products',
      one: 'Imported 1 product',
    );
    return '$_temp0';
  }

  @override
  String settingsImportedProductsWithRefused(
      Object detail, num products, Object refused) {
    String _temp0 = intl.Intl.pluralLogic(
      products,
      locale: localeName,
      other: 'Imported $products products.',
      one: 'Imported 1 product.',
    );
    return '$_temp0 $refused: $detail';
  }

  @override
  String settingsBarcodesRefusedList(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count barcodes',
      one: '1 barcode',
    );
    return '$_temp0 were already on another product';
  }

  @override
  String get settingsNoPairedPrinters =>
      'No Bluetooth printers are paired with this phone. Pair one from the phone\'s Bluetooth settings, then try again.';

  @override
  String get settingsPairingCancelled =>
      'Pairing was cancelled. Pair the printer from the phone\'s Bluetooth settings, then try again.';

  @override
  String settingsPrinterPaired(Object name) {
    return '$name paired.';
  }

  @override
  String settingsResetPinTitle(Object name) {
    return 'Reset PIN for $name';
  }

  @override
  String settingsPinResetFor(Object name) {
    return 'PIN reset for $name';
  }

  @override
  String settingsRoleAdminFull(Object role) {
    return '$role (full rights)';
  }

  @override
  String settingsVersionLabel(Object version) {
    return 'v$version';
  }

  @override
  String get settingsYourShopsTitle => 'Your shops';

  @override
  String get settingsBusinessProfile => 'Business profile';

  @override
  String get settingsBusinessProfileChangeTitle => 'Change business profile';

  @override
  String get settingsBusinessProfileChangeWarning =>
      'This changes navigation and terminology for this shop. Existing sales, stock, tax snapshots, cash balances and financial results stay unchanged.';

  @override
  String get settingsBusinessProfileChangeAction => 'Apply profile';

  @override
  String settingsBusinessProfileChanged(Object profile) {
    return 'Business profile changed to $profile';
  }

  @override
  String get settingsBusinessProfilePreviewTitle => 'What will change';

  @override
  String settingsBusinessProfilePreviewNavigation(Object after, Object before) {
    return 'Navigation: $before → $after';
  }

  @override
  String settingsBusinessProfilePreviewTerminology(
      Object after, Object before) {
    return 'Product wording: $before → $after';
  }

  @override
  String get settingsBusinessProfileStock => 'Stock';

  @override
  String get settingsBusinessProfileMoneyFirst => 'Money-first records';

  @override
  String get activityProfileChanged => 'Business profile changed';

  @override
  String transactionsExpenseTitle(Object category) {
    return 'Expense · $category';
  }

  @override
  String get transactionsExpenseSourceTill => 'Till cash';

  @override
  String get transactionsExpenseSourceOther => 'Other funds';

  @override
  String get shotCupsActionsLabel => 'Cup actions';

  @override
  String get shotCupsAddAction => 'Add a cup';

  @override
  String get shotCupsCapacityHelper =>
      'Leave it empty if you do not know the size. With a size, the app works out what each cup cost you to pour.';

  @override
  String get shotCupsCapacityHint => '30';

  @override
  String get shotCupsCapacityLabel => 'Size in ml (optional)';

  @override
  String shotCupsCapacityMax(Object max) {
    return 'Capacity must be $max ml or less.';
  }

  @override
  String get shotCupsCapacityPositive => 'The size cannot be less than zero.';

  @override
  String shotCupsCapacityValue(Object capacity) {
    return '$capacity ml';
  }

  @override
  String get shotCupsCapacityWholeMl =>
      'Capacity must be whole millilitres, for example 30 or 45.';

  @override
  String shotCupsCardName(Object capacity, Object label) {
    return '$label · $capacity ml';
  }

  @override
  String shotCupsCardSpoken(Object detail, Object name, Object price) {
    return '$name, $detail, $price';
  }

  @override
  String shotCupsCardSpokenInactive(Object detail, Object name, Object price) {
    return '$name, $detail, $price, not sold';
  }

  @override
  String get shotCupsChooseDrink => 'Choose the drink this cup is poured from.';

  @override
  String get shotCupsDefaultName => 'Small cup';

  @override
  String get shotCupsEditAction => 'Edit';

  @override
  String get shotCupsEmptyMessageNoPermission =>
      'No cups have been set up for this shop.';

  @override
  String get shotCupsEmptyMessageOwner =>
      'Add one to sell fixed-size cups of any drink in your inventory.';

  @override
  String get shotCupsEmptyTitle => 'No cups yet';

  @override
  String get shotCupsLoadFailed => 'Couldn’t load the cups. Try again.';

  @override
  String get shotCupsNameAtTillLabel => 'Name at the till';

  @override
  String get shotCupsNameHelper => 'What the cashier taps';

  @override
  String get shotCupsNameHint => 'Small cup, Big cup';

  @override
  String get shotCupsNameRequired =>
      'Give the cup a name, like Small cup or Big cup.';

  @override
  String get shotCupsNotSold => 'Not sold';

  @override
  String shotCupsPerBottle(Object count) {
    return '$count cups per bottle';
  }

  @override
  String get shotCupsPouredFromLabel => 'Poured from';

  @override
  String get shotCupsPriceHelper => 'For one cup';

  @override
  String get shotCupsPriceInvalid => 'Price must be a number, 0 or more.';

  @override
  String get shotCupsPriceLabel => 'Price (KSh)';

  @override
  String get shotCupsRetryLoading => 'Try loading again';

  @override
  String get shotCupsSaveFailed => 'Couldn’t save the cup. Try again.';

  @override
  String get shotCupsStopSellingAction => 'Stop selling';

  @override
  String shotCupsStopSellingMessage(Object product) {
    return '$product cups stop appearing at the till. Sales already recorded are untouched.';
  }

  @override
  String shotCupsStopSellingTitle(Object name) {
    return 'Stop selling $name?';
  }

  @override
  String get shotCupsTitle => 'Cups';

  @override
  String get taxSettingsAdminOnly =>
      'Only the shop admin can change tax settings.';

  @override
  String taxSettingsVatRateLine(Object percent) {
    return 'VAT rate $percent%';
  }

  @override
  String taxSettingsVatRateSpoken(Object percent) {
    return 'VAT rate $percent percent';
  }

  @override
  String taxSettingsWorkedExample(Object net, Object vat) {
    return 'A KSh 100 sale carries KSh $vat VAT, leaving KSh $net net.';
  }

  @override
  String get taxSettingsPricesIncludeVatSubtitle =>
      'On: you type the shelf price and VAT is extracted from it. Off: you type the net price and VAT is added on top.';

  @override
  String taxSettingsTillCodeHelp(Object tillCode) {
    return 'Receipts are numbered $tillCode-000001, and KRA needs that number to match the sequence it has on file. Give each till its own code.';
  }

  @override
  String get taxSettingsEtimsOnSubtitle =>
      'On — every sale is filed with KRA. Sales keep working with no signal; receipts upload as soon as there is a connection.';

  @override
  String get taxSettingsEtimsOffSubtitle =>
      'Off — sales are recorded and VAT reports remain available. KRA eTIMS is not activated.';

  @override
  String get taxSettingsTinNotRegisteredHelp =>
      'Receipts cannot be issued until this shop\'s KRA PIN is registered. Until then, sales are recorded but no tax invoice is issued.';

  @override
  String get taxSettingsWaitForReceiptsSubtitle =>
      'Queued automatically after every sale while online. Sales never wait for it.';

  @override
  String get taxSettingsTillCodeDialogHelp =>
      'Letters and digits only. Every till in a shop needs its own code, because KRA rejects two tills issuing the same receipt number.';

  @override
  String get taxSettingsKraPinDialogHelp =>
      'Enter the PIN exactly as printed on this shop\'s KRA certificate, including the P0 prefix. A PIN issued to the wrong business puts invoices on someone else\'s return.';

  @override
  String get taxSettingsSaveFailed =>
      'Couldn\'t save. Check the phone has storage free.';

  @override
  String get taxSettingsApplyAction => 'Apply';

  @override
  String get taxSettingsChangeAction => 'Change';

  @override
  String get taxSettingsEtimsOff => 'eTIMS receipts switched off';

  @override
  String get taxSettingsEtimsOn => 'eTIMS receipts switched on';

  @override
  String get taxSettingsEtimsSection => 'Tax reporting';

  @override
  String get taxSettingsEtimsUpdateFailed =>
      'Couldn’t update eTIMS. Check your connection and try again.';

  @override
  String get taxSettingsEtimsNotLinked =>
      'Link this shop to the backend before switching eTIMS on.';

  @override
  String get taxSettingsIssueEtimsTitle => 'Issue tax receipts';

  @override
  String get taxSettingsKraPinTitle => 'KRA taxpayer PIN';

  @override
  String get taxSettingsKraUnreachable =>
      'Couldn’t reach KRA. Check the shop is linked and you have a connection, then try again.';

  @override
  String get taxSettingsKraUnreachableRetry =>
      'Couldn’t reach KRA. Try again when you have a connection.';

  @override
  String get taxSettingsNotActivatedStatus => 'KRA eTIMS not activated';

  @override
  String get taxSettingsNotActivatedSubtitle =>
      'Risiti by PesaStack Limited is the planned provider. Activation stays off until the shop is onboarded and approved.';

  @override
  String get taxSettingsPricesIncludeVat => 'Prices include VAT';

  @override
  String get taxSettingsReceiptNumberingSection => 'Receipt numbering';

  @override
  String get taxSettingsRegisterAction => 'Register';

  @override
  String get taxSettingsRegisterPinFirst =>
      'Register your KRA taxpayer PIN first.';

  @override
  String get taxSettingsRegisteredDevice => 'Registered device';

  @override
  String get taxSettingsSaved => 'Saved';

  @override
  String get taxSettingsTillCode => 'Till code';

  @override
  String get taxSettingsTillCodeRequired =>
      'Enter at least one letter or digit';

  @override
  String get taxSettingsTinLabel => 'TIN (PIN)';

  @override
  String get taxSettingsTinNotRegistered => 'TIN not registered';

  @override
  String get taxSettingsTinRegisteredHelp =>
      'Invoices are issued against this PIN.';

  @override
  String get taxSettingsTinTooShort => 'A TIN is at least 4 characters';

  @override
  String get taxSettingsTinInvalid =>
      'A KRA PIN is A or P, nine digits, then one letter.';

  @override
  String get taxSettingsTitle => 'Tax settings';

  @override
  String get taxSettingsVatExempt =>
      'Exempt — receipts omit the VAT line entirely.';

  @override
  String get taxSettingsVatSection => 'Value Added Tax';

  @override
  String get taxSettingsWaitForReceipts => 'Wait for receipts to be issued';

  @override
  String get variantAddTitle => 'Add variant';

  @override
  String get variantBarcodeHelper =>
      'Scanning this adds this variant, not the product';

  @override
  String get variantBarcodeHint => '6001234567892';

  @override
  String get variantBarcodeLabel => 'Barcode (optional)';

  @override
  String variantCostPriceHelper(Object amount) {
    return 'Empty keeps $amount';
  }

  @override
  String get variantCostPriceLabel => 'Cost price';

  @override
  String variantCostPriceNotANumber(Object amount) {
    return 'Cost price must be a number, or empty to use $amount';
  }

  @override
  String get variantCostPriceNotNegative => 'Cost price must be 0 or more';

  @override
  String get variantCountableNote =>
      'Countable — no serving size. One bottle is one Dark.';

  @override
  String get variantEditTitle => 'Edit variant';

  @override
  String get variantNameHint => 'Dark, Regular, Big cup';

  @override
  String get variantNameLabel => 'Name';

  @override
  String get variantNameRequired =>
      'Give the variant a name, like Dark or Big cup';

  @override
  String variantNameTooLong(Object max) {
    return 'Name must be $max characters or fewer';
  }

  @override
  String get variantReorderLevelHelper => 'Warn at or below';

  @override
  String get variantReorderLevelLabel => 'Reorder level';

  @override
  String get variantReorderLevelNotNegative =>
      'Reorder level must be 0 or more';

  @override
  String get variantSaveAction => 'Save variant';

  @override
  String get variantSellPriceLabel => 'Sell price';

  @override
  String get variantSellPriceNotANumber => 'Selling price must be a number';

  @override
  String get variantSellPriceNotNegative => 'Selling price must be 0 or more';

  @override
  String get variantSizeHelper => 'Millilitres or litres — 500ml, 0.5L, 1.5 L.';

  @override
  String get variantSizeLeaveBlankHelper =>
      'Leave blank if it isn\'t sold by volume';

  @override
  String get variantSizeHintLitre => '0.5L';

  @override
  String get variantSizeHintMillilitre => '500ml';

  @override
  String get variantSizeInvalid =>
      'Size must be a number, optionally with ml or L — for example 500ml';

  @override
  String get variantSizeLabel => 'Serving size';

  @override
  String get variantSizeRequired => 'Enter the serving size, for example 500ml';

  @override
  String get variantSizeSuggestionsSpoken => 'Cup sizes you have used before';

  @override
  String get variantSkuHelper => 'Your own reference for this variant';

  @override
  String get variantSkuLabel => 'Stock-keeping code (optional)';

  @override
  String get variantStartingStockHelper => 'How many you have now';

  @override
  String get variantStartingStockLabel => 'Starting stock';

  @override
  String get variantUnitCup => 'Per cup';

  @override
  String get variantUnitEach => 'Each (countable)';

  @override
  String get variantUnitLabel => 'Measured in';

  @override
  String get variantUnitLitre => 'Per litre';

  @override
  String get variantUnitMillilitre => 'Per millilitre';

  @override
  String chooserSignedInShop(Object shop) {
    return 'Signed-in shop: $shop';
  }

  @override
  String get chooserHeading => 'Choose how you want to start';

  @override
  String get chooserHasShopWarning =>
      'This device already runs a shop. Setting up again adds a second one, on the same admin account and the same PIN.';

  @override
  String get chooserSignInAction => 'Sign in';

  @override
  String get chooserSignInAsStaffAction => 'Sign in as staff';

  @override
  String get chooserSetupAnother => 'Set up another shop on this device';

  @override
  String get chooserSetupFirst => 'Set up a shop on this device';

  @override
  String get chooserSignInHelp =>
      'Cashiers, managers and admins all sign in with the PIN their shop gave them.';

  @override
  String get loginRoleAdmins => 'Admins';

  @override
  String get loginRoleManagers => 'Managers';

  @override
  String get loginRoleCashiers => 'Cashiers';

  @override
  String loginRoleAccountsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
      zero: 'No accounts',
    );
    return '$_temp0';
  }

  @override
  String get chooserSetupHelp =>
      'A shop admin sets this device up once. After that, everyone signs in with the PIN they are given. No internet is needed.';

  @override
  String get chartNothingToShow => 'Nothing to show yet.';

  @override
  String chartSpokenNoValues(Object title) {
    return '$title. No values.';
  }

  @override
  String chartSpokenPeak(num count, Object peak, Object title, Object value) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count values',
      one: '1 value',
    );
    return '$title. $_temp0. Highest is $peak at $value.';
  }

  @override
  String chartSpokenSelected(Object label, Object title, Object value) {
    return '$title. Selected $label. $value.';
  }

  @override
  String chartSpokenBar(Object label, Object value) {
    return '$label, $value';
  }

  @override
  String get variantAllSizesLabel => 'All sizes';

  @override
  String get variantOneVariantLabel => 'One variant';

  @override
  String get backupLaterAction => 'Later';

  @override
  String get backupNowAction => 'Back up now';

  @override
  String get backupFailedMessage =>
      'Backup could not be completed. Check storage and try again.';

  @override
  String get scanTitle => 'Scan barcode';

  @override
  String get scanHoldInsideFrame => 'Hold the barcode inside the frame';

  @override
  String get scanUnavailableTitle => 'The camera is not available';

  @override
  String get scanUnavailableMessage =>
      'You can still sell this product. Search for it by name on the Sell screen, or use a Bluetooth or USB barcode scanner, which types the code straight into the till.';

  @override
  String get scanBackToSelling => 'Back to selling';

  @override
  String get scanRetryCamera => 'Try camera again';

  @override
  String get scanPointAtBarcode => 'Point the camera at the barcode';

  @override
  String scanCodesRead(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count codes read',
      one: '1 code read',
    );
    return '$_temp0';
  }

  @override
  String get scanDone => 'Done';

  @override
  String get scanEnterCodeManually => 'Enter code manually';

  @override
  String get scanFlashOnTooltip => 'Turn the flash on';

  @override
  String get scanFlashOffTooltip => 'Turn the flash off';

  @override
  String get scanPermissionDeniedTitle => 'Camera access is off';

  @override
  String get scanPermissionDeniedMessage =>
      'The camera needs permission to read a barcode. Turn camera access on for this app in your phone\'s settings, then try again.';

  @override
  String get scanManualTitle => 'Enter barcode';

  @override
  String get scanManualLabel => 'Barcode';

  @override
  String get scanManualHint => 'Type the digits printed under the barcode';

  @override
  String get scanManualAdd => 'Add';

  @override
  String get scanManualInvalidCode =>
      'That is not a barcode this till can read';

  @override
  String signOutTitleNamed(Object name) {
    return 'Sign out $name';
  }

  @override
  String get signOutTitle => 'Sign out';

  @override
  String get signOutDetail => 'The PIN pad comes back for the next person.';

  @override
  String signOutCartWarningTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You have $count items in the cart',
      one: 'You have 1 item in the cart',
    );
    return '$_temp0';
  }

  @override
  String get signOutCartWarningDetail =>
      'Nothing has been charged, and signing out clears the cart.';

  @override
  String get signOutShiftWarningTitle => 'Your shift is still open';

  @override
  String get signOutShiftWarningDetail =>
      'The cash you started with is still counted against your shift. You can sign out and reconcile later, but the shift stays open until someone closes it.';

  @override
  String get signOutStayAction => 'Stay signed in';

  @override
  String get signOutConfirmAction => 'Sign out';

  @override
  String signOutWarningSpoken(Object detail, Object title) {
    return '$title. $detail';
  }

  @override
  String get sellScanHintSearchProducts => 'Search products...';

  @override
  String get sellEnterValidPhone => 'Enter a valid phone number';

  @override
  String get sellTotalOnly => 'Total:';

  @override
  String sellScanVariantOnlyMessage(Object product) {
    return '$product is sold as variants, so its own barcode is not enough. Scan one of its variant barcodes, or tap the product to choose.';
  }

  @override
  String sellScanVariantOutOfStockMessage(Object variant) {
    return '$variant is out of stock.';
  }

  @override
  String get sellNoVariantsYetHint =>
      'Add them in Inventory, for example Dark, Regular or Big cup, and they will appear here.';

  @override
  String sellPourOptionTitle(Object label, Object ml) {
    return '$label · $ml ml';
  }

  @override
  String get settingsBackupsErased =>
      'Local encrypted backups and their key were erased.';

  @override
  String get settingsPaymentChannelIdRequired =>
      'Enter a numeric Till or Paybill number';

  @override
  String get settingsCloseAction => 'Close';

  @override
  String inventoryRemoveTitle(Object product) {
    return 'Remove $product from inventory?';
  }

  @override
  String get inventoryCostPriceNotANumber => 'Cost price must be a number';

  @override
  String get inventorySellPriceNotANumber => 'Sell price must be a number';

  @override
  String get inventoryStockNotANumber => 'Stock must be a number';

  @override
  String get inventoryNoVariantsHelper =>
      'No variants yet. The till will ask for one instead of selling the whole product.';

  @override
  String get inventoryStockIsDerived =>
      'The variants\' total, kept in step for you';

  @override
  String dashboardStaffNameSince(Object staffName, Object startTime) {
    return '$staffName, since $startTime';
  }

  @override
  String dashboardSalesToday(Object scopeLabel) {
    return 'Sales today · $scopeLabel';
  }

  @override
  String dashboardSee(Object totalCount) {
    return 'See all $totalCount';
  }

  @override
  String get dashboardSalesLabel => 'Sales';

  @override
  String get dashboardProfitLabel => 'Profit';

  @override
  String get dashboardAverageSaleLabel => 'Average sale';

  @override
  String dashboardLowStockNoun(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'products low',
      one: 'product low',
    );
    return '$_temp0';
  }

  @override
  String get dashboardExpectedInDrawer => 'Expected in drawer';

  @override
  String get dashboardNoShiftMessage =>
      'No shift open. Sales still record, but they will not appear in a shift report.';

  @override
  String get dashboardOpenShiftAction => 'Open';

  @override
  String dashboardOpenShiftSpoken(Object expected, Object since) {
    return 'Open shift since $since. Expected in drawer $expected. Open the shift.';
  }

  @override
  String get dashboardReorderSection => 'Reorder';

  @override
  String dashboardUnitsInStock(Object qty) {
    return '$qty in stock';
  }

  @override
  String analyticsAgainstDaysBefore(Object days) {
    return 'against the $days days before';
  }

  @override
  String dashboardId(Object id) {
    return '$id';
  }

  @override
  String loginName(Object name, Object roleLabel) {
    return '$name, $roleLabel';
  }

  @override
  String loginFilledPINDigitsEntered(Object filled, Object length) {
    return '$filled of $length PIN digits entered';
  }

  @override
  String loginDigit(Object digit) {
    return 'Digit $digit';
  }

  @override
  String fieldRequired(Object label) {
    return '$label is required';
  }

  @override
  String get loginSignInAction => 'Sign in';

  @override
  String get approvalTitle => 'Manager approval';

  @override
  String get approvalWrongPin => 'That PIN is not the one on file. Try again.';

  @override
  String get approvalNoManagers =>
      'Nobody can approve this yet: add a manager or use the owner sign-in.';

  @override
  String get approvalPinLabel => 'Your 6-digit PIN';

  @override
  String get approvalConfirmAction => 'Approve';

  @override
  String get roleNameOwner => 'Owner';

  @override
  String get roleNameManager => 'Manager';

  @override
  String get roleNameCashier => 'Cashier';

  @override
  String get sellPaymentOnAccount => 'On account';

  @override
  String get sellCreditNoCustomer => 'Tap to choose the customer';

  @override
  String get sellCreditPickCustomer => 'Who takes this on account?';

  @override
  String sellCreditOverLimit(Object name, Object total) {
    return '$name would owe $total.';
  }

  @override
  String sellCreditOverLimitAsk(Object name, Object total) {
    return '$name would owe $total.';
  }

  @override
  String get customerAddInlineAction => 'Add a new customer';

  @override
  String get customerSavedTitle => 'Customer saved';

  @override
  String get customerAddedMessage => 'The customer is on the list.';

  @override
  String get customerEditAction => 'Edit';

  @override
  String get customersTitle => 'Customers';

  @override
  String get creditOwedToYou => 'Owed to you';

  @override
  String creditOwedByCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count customers owe',
      one: 'One customer owes',
      zero: 'No one owes anything',
    );
    return '$_temp0';
  }

  @override
  String get creditAging7 => '0–7 days';

  @override
  String get creditAging30 => '8–30 days';

  @override
  String get creditAging60 => '31–60 days';

  @override
  String get creditAgingOver => '60+ days';

  @override
  String get customersFilterOwes => 'Owes money';

  @override
  String get customersSortName => 'By name';

  @override
  String get customerSearchHint => 'Search by name or number';

  @override
  String get customersEmptyTitle => 'No customers yet';

  @override
  String get customersEmptyMessage =>
      'Sell on account and the till keeps the balance here instead of on paper.';

  @override
  String get customersNoMatchesTitle => 'No matches';

  @override
  String get customersNoMatchesMessage => 'Nobody matches that search.';

  @override
  String customerOwesChip(Object amount) {
    return 'Owes $amount';
  }

  @override
  String customerCreditChip(Object amount) {
    return 'Credit with them $amount';
  }

  @override
  String get customerAddAction => 'Add customer';

  @override
  String get customerNameLabel => 'Customer name';

  @override
  String get customerLimitLabel => 'Credit limit (KSh)';

  @override
  String get customerLimitHelper => 'Blank uses the shop default.';

  @override
  String get customerLimitInvalid => 'A limit is a number of shillings.';

  @override
  String get customerNotesLabel => 'Notes';

  @override
  String get customerSaveAction => 'Save customer';

  @override
  String get customerBalanceOwedHeading => 'Owed to the shop';

  @override
  String get customerBalanceCreditHeading => 'In credit with the shop';

  @override
  String get customerBalanceClearHeading => 'Nothing owed';

  @override
  String customerBalanceLimitHeading(Object headroom, Object limit) {
    return 'Limit $limit. Room $headroom.';
  }

  @override
  String get customerAddPayment => 'Add payment';

  @override
  String get customerRemindAction => 'Remind';

  @override
  String get customerStatementAction => 'Statement';

  @override
  String get customerDeactivateAction => 'Remove';

  @override
  String customerDeactivateError(Object message) {
    return '$message';
  }

  @override
  String creditDeactivateFailed(Object message) {
    return '$message';
  }

  @override
  String get customerReminderFailed =>
      'There is no app that could open the message.';

  @override
  String get creditHistoryLabel => 'History';

  @override
  String get creditHistoryEmptyTitle => 'Nothing on this account yet';

  @override
  String get creditHistoryEmptyMessage =>
      'A sale on account or a first payment starts the history.';

  @override
  String get creditEntryCharge => 'Bought on account';

  @override
  String get creditEntryPayment => 'Paid';

  @override
  String get creditEntryAdjustment => 'Corrected';

  @override
  String get creditEntryWriteoff => 'Written off';

  @override
  String get creditEntryReturn => 'Returned';

  @override
  String customerStatementTitle(Object name) {
    return 'Statement — $name';
  }

  @override
  String customerStatementBalance(Object balance) {
    return 'Balance: $balance';
  }

  @override
  String get customerStatementShareHint =>
      'Copy the text, then paste it wherever the customer will read it.';

  @override
  String get customerCopyStatement => 'Copy';

  @override
  String creditPaymentOwes(Object amount) {
    return 'Currently owes $amount';
  }

  @override
  String get creditPaymentAmountLabel => 'The amount being paid';

  @override
  String get creditPaymentAmountHelper => 'The full balance is pre-filled.';

  @override
  String get creditPaymentAmountInvalid => 'A payment is more than zero.';

  @override
  String get creditPaymentCash => 'Cash';

  @override
  String get creditPaymentMpesa => 'M-Pesa';

  @override
  String get creditPaymentCodeLabel => 'M-Pesa code';

  @override
  String get creditPaymentConfirmAction => 'Take the payment';

  @override
  String creditPaymentTaken(Object amount, Object name) {
    return '$name paid $amount.';
  }

  @override
  String get creditRepaymentTakenTitle => 'Payment taken';

  @override
  String get activityCreditRepayment => 'Credit payment taken';

  @override
  String get activityCreditAdjusted => 'Credit account adjusted';

  @override
  String get loginPinLabel => 'PIN';

  @override
  String get analyticsYourSalesTitle => 'Your sales';

  @override
  String get receiveTitle => 'Receive stock';

  @override
  String get receiveSubtitle => 'Record what arrived and what you paid for it.';

  @override
  String get receiveSupplierLabel => 'Supplier';

  @override
  String get receiveNoSupplier => 'No supplier';

  @override
  String get receiveSupplierRefLabel => 'Invoice or delivery note number';

  @override
  String get receiveSupplierRefHint => 'The number on the supplier\'s paper.';

  @override
  String get receiveLinesLabel => 'What arrived';

  @override
  String get receiveAddProductAction => 'Add a product';

  @override
  String get receiveQtyLabel => 'How many';

  @override
  String get receiveUnitCostLabel => 'Cost each (KSh)';

  @override
  String receiveLineTotal(Object total) {
    return 'Line total: $total';
  }

  @override
  String get receiveTotalLabel => 'What the delivery cost';

  @override
  String get receivePostAction => 'Post it';

  @override
  String get receiveRemoveLineAction => 'Remove this line';

  @override
  String get receiveSearchLabel => 'Search the catalogue';

  @override
  String receiveAlreadyOn(Object count) {
    return 'Already on this delivery: $count';
  }

  @override
  String get receiveNoLines => 'Add at least one thing that arrived.';

  @override
  String get receiveFailed =>
      'The delivery could not be recorded. Nothing has changed.';

  @override
  String get receiveDone =>
      'The stock is on the shelf and the costs are up to date.';

  @override
  String get receiveAddSupplierAction => 'Add a supplier';

  @override
  String get receiveDraftRestored =>
      'A half-finished delivery was brought back.';

  @override
  String get receiveDraftDiscarded =>
      'The half-finished delivery was thrown away.';

  @override
  String get receiveDraftDiscardAction => 'Discard';

  @override
  String get receiveDraftDiscardTitle => 'Discard this half-finished delivery?';

  @override
  String get receiveDraftDiscardMessage =>
      'What you scanned in goes away for good. The stock and the costs are untouched.';

  @override
  String get receiveDraftDiscardConfirm => 'Discard it';

  @override
  String get receiveDraftAction => 'Resume delivery';

  @override
  String receiveQtyValue(Object qty) {
    return '$qty';
  }

  @override
  String get receiveDeliveriesAction => 'Deliveries';

  @override
  String get receiveHistoryTitle => 'Deliveries';

  @override
  String get receiveHistoryEmpty =>
      'No deliveries recorded yet. Receiving stock gets you one here.';

  @override
  String receiveReceiptCost(Object total) {
    return 'Cost $total';
  }

  @override
  String get receiveViewAction => 'View';

  @override
  String get supplierAddTitle => 'Add a supplier';

  @override
  String get supplierAddSubtitle =>
      'The name of the shop or person you buy from, and the number to order on.';

  @override
  String get supplierNameLabel => 'Supplier name';

  @override
  String get supplierNameTooShort => 'Enter the supplier\'s name.';

  @override
  String get supplierNameAlreadyOnList =>
      'That supplier is already on the list.';

  @override
  String get supplierPhoneLabel => 'Phone number';

  @override
  String get supplierPhoneHelper => 'For ordering later. 07…, 01… or 254…';

  @override
  String get supplierPhoneInvalid =>
      'That is not a Kenyan number. Use 07…, 01…, +254… or 254…';

  @override
  String get supplierSaveAction => 'Save supplier';

  @override
  String supplierSaveFailed(Object message) {
    return '$message';
  }

  @override
  String get receiveVoidAction => 'Void delivery';

  @override
  String get receiveVoidTitle => 'Void this delivery?';

  @override
  String get receiveVoidMessage =>
      'The stock it brought goes back off the shelf, and its cost comes off the history. This cannot be undone.';

  @override
  String get receiveVoidConfirm => 'Void delivery';

  @override
  String get receiveVoided =>
      'The delivery was voided. The stock went back off the shelf.';

  @override
  String receiveVoidFailed(Object message) {
    return '$message';
  }

  @override
  String get receiveVoidedBy => 'Voided';

  @override
  String get transactionsReturnedBadge => 'Returned';

  @override
  String get transactionsPartlyReturnedBadge => 'Partly returned';

  @override
  String get returnTitle => 'Return items';

  @override
  String get returnHistoryLabel => 'Already returned';

  @override
  String get returnSubtitle =>
      'Choose what is coming back, say why, and choose how the money goes back.';

  @override
  String get returnReasonLabel => 'Why is it coming back?';

  @override
  String get returnReasonHint =>
      'For example: the customer changed their mind.';

  @override
  String get returnMethodLabel => 'How should the money go back?';

  @override
  String get returnMethodCash => 'Cash';

  @override
  String get returnMethodMpesa => 'M-Pesa';

  @override
  String get returnRefundLabel => 'Money to give back';

  @override
  String get returnConfirmAction => 'Give it back';

  @override
  String get returnNoLines => 'Choose at least one thing to give back.';

  @override
  String get returnReasonRequired => 'Say why it is coming back.';

  @override
  String get returnFailed =>
      'The return could not be recorded. Nothing has changed.';

  @override
  String get returnNoShiftOpen =>
      'Open a shift first, so the money can come out of the drawer.';

  @override
  String get returnUnverifiedPayment =>
      'That payment was never confirmed, so it cannot be given back yet.';

  @override
  String get returnMoreThanSold =>
      'More was returned than was sold on that line.';

  @override
  String get returnLineGone => 'That line is no longer on the sale.';

  @override
  String get returnLineAllReturned => 'All returned';

  @override
  String returnLineRemaining(Object qty) {
    return '$qty left';
  }

  @override
  String get returnRestockLabel => 'Put it back on the shelf';

  @override
  String get returnWriteOffLabel => 'Write it off (damaged or expired)';

  @override
  String get returnLessAction => 'Return less';

  @override
  String get returnMoreAction => 'Return more';

  @override
  String get returnDone => 'Returned. The money is on its way back.';

  @override
  String get analyticsShiftsSection => 'Shifts';

  @override
  String get analyticsShiftsCount => 'Shifts';

  @override
  String analyticsShiftsClosed(Object closed) {
    return '$closed closed';
  }

  @override
  String get analyticsShiftsExpected => 'Cash expected';

  @override
  String get analyticsShiftsCounted => 'Cash counted';

  @override
  String get analyticsNoShifts => 'No shifts in this period';

  @override
  String get analyticsNoShiftsHint =>
      'When a shift is opened and counted, it appears here with what the drawer should have held and what was actually in it.';

  @override
  String get loginChooseShopTitle => 'Which shop are you opening?';

  @override
  String loginChooseShopSubtitle(Object count) {
    return 'This phone has $count shops. Choose the one you are working in.';
  }

  @override
  String get loginChooseShopAction => 'Choose a different shop';

  @override
  String loginCurrentShopLabel(Object shop) {
    return 'Now signing in to $shop';
  }

  @override
  String get backToPinPadAction => 'Back to PIN pad';

  @override
  String get staffLoginTitle => 'Sign in as staff';

  @override
  String get staffUsernameLabel => 'Username';

  @override
  String get staffPasswordLabel => 'Password';

  @override
  String get loginWrongCredentials => 'Wrong username or password';

  @override
  String get loginNetworkError => 'Could not reach the shop server. Try again.';

  @override
  String get permissionsTitle => 'Set up your till';

  @override
  String get permissionsSubtitle =>
      'These two let the till do its job. You can skip either one and change it later in Settings.';

  @override
  String get permissionsCameraTitle => 'Camera';

  @override
  String get permissionsCameraWhy =>
      'Scan barcodes with the handset camera, and photograph a product for its tile.';

  @override
  String get permissionsBluetoothTitle => 'Bluetooth';

  @override
  String get permissionsBluetoothWhy =>
      'Send receipts to a Bluetooth receipt printer.';

  @override
  String get permissionsAllow => 'Allow';

  @override
  String get permissionsAllowed => 'Allowed';

  @override
  String get permissionsOpenSettings => 'Open Settings';

  @override
  String get permissionsContinue => 'Continue';

  @override
  String get permissionsOptionalNote =>
      'None of these are required. A till with a barcode scanner and no camera can still sell everything.';

  @override
  String get permissionsMatrixTitle => 'Permissions';

  @override
  String get permissionsMatrixOwnerOnly =>
      'Only the owner can change permissions.';

  @override
  String get permissionsMatrixRolePermissions => 'Role permissions';

  @override
  String get permissionsMatrixManager => 'Manager';

  @override
  String get permissionsMatrixCashier => 'Cashier';

  @override
  String get permissionsMatrixStaffOverrides => 'Staff overrides';

  @override
  String get permissionsMatrixStaffMember => 'Staff member';

  @override
  String get permissionsMatrixNoOverride => 'No individual override';

  @override
  String get permissionsMatrixIndividualOverride => 'Individual override';

  @override
  String get permissionsMatrixRoleDefault => 'Uses role default';

  @override
  String get permissionsMatrixReset => 'Reset to role default';

  @override
  String get permissionsMatrixAllow => 'Allow';

  @override
  String get permissionsMatrixApproval => 'Approval';

  @override
  String get permissionsMatrixDeny => 'Deny';

  @override
  String get blackbeeSeedTitle => 'Seed BlackBee products';

  @override
  String get blackbeeSeedAdded => 'Added';

  @override
  String get blackbeeSeedPriceRequired => 'Price and selling price required';

  @override
  String get incomingPaymentsTitle => 'Incoming M-Pesa';

  @override
  String get incomingPaymentsManagerOnly =>
      'Only a manager can view incoming payments.';

  @override
  String get incomingPaymentsUnclaimed => 'Unclaimed';

  @override
  String get incomingPaymentsClaimed => 'Claimed';

  @override
  String get incomingPaymentsIgnored => 'Ignored';

  @override
  String get incomingPaymentsDisputed => 'Disputed';

  @override
  String get incomingPaymentsNewNotice =>
      'New unclaimed M-Pesa payment received.';

  @override
  String get incomingPaymentsLoadFailed =>
      'Incoming payments could not be loaded.';

  @override
  String get incomingPaymentsSetAsideTitle => 'Set payment aside';

  @override
  String get incomingPaymentsReason => 'Reason';

  @override
  String get incomingPaymentsSetAsideAction => 'Set aside';

  @override
  String get incomingPaymentsEmpty => 'No payments here.';

  @override
  String get incomingPaymentsSetAsideFailed =>
      'The payment could not be set aside.';

  @override
  String onboardingImportedProducts(Object products) {
    return 'Imported $products products.';
  }

  @override
  String ownerLabelRequired(Object label) {
    return '$label is required';
  }

  @override
  String reportsShowingSales(Object length, Object unfilteredCount) {
    return 'Showing $length of $unfilteredCount sales.';
  }

  @override
  String reportsChange(Object amount) {
    return 'change $amount';
  }

  @override
  String reportsStaffName(Object amount, Object detail, Object staffName) {
    return '$staffName, $detail, $amount';
  }

  @override
  String reportsExpectedTill(Object amount) {
    return 'Expected in till $amount';
  }

  @override
  String taxVatRatePercent(Object vatRatePercent) {
    return '$vatRatePercent%';
  }

  @override
  String taxTaxpayerPIN(Object tin) {
    return 'Taxpayer PIN $tin';
  }

  @override
  String inventoryStockqtyStock(Object stockqty) {
    return '$stockqty in stock';
  }

  @override
  String inventoryNameStock(Object amount, Object name, Object stockqty) {
    return '$name, $amount, $stockqty in stock';
  }

  @override
  String inventoryBarcodeAlready(Object name) {
    return 'That barcode is already on $name.';
  }

  @override
  String inventoryEdit(Object name) {
    return 'Edit $name';
  }

  @override
  String inventoryBarcodeAlreadyUsedAnother(Object code) {
    return 'Barcode $code is already used by another product or variant.';
  }

  @override
  String inventoryBarcodeAlready2(Object code, Object name) {
    return 'Barcode $code is already on $name.';
  }

  @override
  String inventoryLabelMustNumberEmpty(Object label) {
    return '$label must be a number, or empty if not sold in portions';
  }

  @override
  String inventoryLabelMust0(Object label) {
    return '$label must be 0 or more';
  }

  @override
  String inventoryRemove(Object barcode) {
    return 'Remove $barcode';
  }

  @override
  String inventoryQuantity(Object quantity) {
    return '$quantity';
  }

  @override
  String dashboardGreetingAnonymous(Object greeting) {
    return '$greeting.';
  }

  @override
  String dashboardGreetingNamed(Object greeting, Object name) {
    return '$greeting, $name.';
  }

  @override
  String get dashboardScopeShop => 'the whole shop';

  @override
  String get dashboardScopeOwn => 'just you';

  @override
  String get dashboardGreetingMorning => 'Good morning';

  @override
  String get dashboardGreetingAfternoon => 'Good afternoon';

  @override
  String get dashboardGreetingEvening => 'Good evening';

  @override
  String get dashboardSalesByHour => 'Sales by hour';

  @override
  String dashboardPeakHourSpoken(Object amount, Object hour) {
    return 'Busiest at $hour, $amount.';
  }

  @override
  String get dashboardNoSalesTitle => 'No sales today';

  @override
  String get dashboardNoSalesTodayBody =>
      'That\'s normal if you haven\'t opened yet.';

  @override
  String get dashboardNoSalesFirstBody =>
      'Sales will appear here as soon as the first sale goes through the till.';

  @override
  String get liveStatusConnected => 'Live';

  @override
  String liveStatusUpdated(Object when) {
    return 'Updated $when';
  }

  @override
  String get liveStatusJustNow => 'just now';

  @override
  String liveStatusMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0 ago';
  }

  @override
  String liveStatusHours(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return '$_temp0 ago';
  }

  @override
  String get liveStatusConnecting => 'Connecting…';

  @override
  String get liveStatusReconnecting => 'Reconnecting…';

  @override
  String get dashboardAllClear => 'All clear';

  @override
  String analyticsTransactionCaption(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions',
      one: '1 transaction',
    );
    return '$_temp0';
  }

  @override
  String analyticsMarginCaption(Object margin) {
    return '$margin% margin';
  }

  @override
  String get analyticsAvgBasketCaption => 'per sale';

  @override
  String get analyticsSalesLabel => 'Sales';

  @override
  String analyticsTopProductsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count products sold',
      one: '1 product sold',
    );
    return '$_temp0';
  }

  @override
  String get saleDetailsTitle => 'Sale details';

  @override
  String get saleDetailsWhen => 'When';

  @override
  String get saleDetailsWhere => 'Where';

  @override
  String get saleDetailsHow => 'How it was paid';

  @override
  String get saleDetailsWho => 'Who sold it';

  @override
  String get saleDetailsWhat => 'What was sold';

  @override
  String get saleDetailsNoItems => 'No items were recorded on this sale.';

  @override
  String saleDetailsReference(Object reference) {
    return 'Reference $reference';
  }

  @override
  String saleDetailsTendered(Object change, Object tendered) {
    return 'Tendered $tendered · change $change';
  }

  @override
  String saleDetailsQuantity(Object quantity) {
    return '$quantity ×';
  }

  @override
  String get transactionsTitle => 'Transactions';

  @override
  String transactionsSubtitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sales in the last 14 days',
      one: '1 sale in the last 14 days',
    );
    return '$_temp0';
  }

  @override
  String get transactionsEmptyTitle => 'No sales yet';

  @override
  String get transactionsEmptyMessage =>
      'Every sale rung up at this till is listed here, with who sold it.';

  @override
  String get transactionsEmptyOwnTitle => 'Nothing sold yet today';

  @override
  String get transactionsEmptyOwnMessage =>
      'You have not rung up any sales on this till yet. Sign in as a manager or owner to see the whole shop.';

  @override
  String get transactionsLoadFailed => 'That list could not be loaded.';

  @override
  String transactionsSoldBy(Object name) {
    return 'Sold by $name';
  }

  @override
  String transactionsAuditBy(Object name) {
    return 'Logged as $name';
  }

  @override
  String transactionsMethod(Object method) {
    return '$method';
  }

  @override
  String transactionsItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'Nothing',
    );
    return '$_temp0';
  }

  @override
  String transactionsMinutesAgo(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: 'Just now',
    );
    return '$_temp0';
  }

  @override
  String transactionsHoursAgo(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: 'An hour ago',
    );
    return '$_temp0';
  }

  @override
  String transactionsOn(Object day, Object month) {
    return '$day/$month';
  }

  @override
  String get dashboardTransactionsLabel => 'Transactions';

  @override
  String get analyticsTopProductsEmpty => 'Nothing sold in this period.';

  @override
  String get analyticsProfitLabel => 'Profit';

  @override
  String get analyticsNetProfitLabel => 'Net profit';

  @override
  String get analyticsNetProfitCaption => 'After posted expenses';

  @override
  String get analyticsAvgBasketLabel => 'Avg basket';

  @override
  String analyticsSortedBy(Object direction, Object label) {
    return '$label, sorted $direction';
  }

  @override
  String analyticsNotSorted(Object label) {
    return '$label column, not sorted';
  }

  @override
  String get analyticsSortedAscending => 'ascending';

  @override
  String get analyticsSortedDescending => 'descending';

  @override
  String analyticsRowSpokenFull(Object margin, Object product, Object profit,
      Object revenue, Object units) {
    return '$product, $units units, $revenue revenue, $profit profit, $margin margin';
  }

  @override
  String analyticsRowSpokenCompact(Object margin, Object profit, Object units) {
    return '$units units · $profit profit · $margin margin';
  }

  @override
  String get analyticsTransactionsLabel => 'Transactions';

  @override
  String get analyticsPaymentMethodsSection => 'Payment methods';

  @override
  String get analyticsNothingTaken => 'Nothing taken in this period.';

  @override
  String get analyticsPaymentMixTotal => 'Total';

  @override
  String get analyticsPaymentMethodCash => 'Cash';

  @override
  String get analyticsPaymentMethodMpesa => 'M-Pesa';

  @override
  String get analyticsPaymentMethodMobileMoney => 'Mobile money';

  @override
  String get analyticsPaymentMethodCard => 'Card';

  @override
  String get analyticsPaymentMethodBankTransfer => 'Bank transfer';

  @override
  String analyticsPaymentRowSpoken(
      Object amount, num count, Object label, Object share) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sales',
      one: '1 sale',
    );
    return '$label, $share of takings, $amount across $_temp0';
  }

  @override
  String attentionItemsToFix(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count to fix',
      one: '1 to fix',
    );
    return '$_temp0';
  }

  @override
  String attentionCountBadge(Object count) {
    return '$count';
  }

  @override
  String attentionSpoken(Object detail, Object label) {
    return '$label. $detail';
  }

  @override
  String get attentionSectionTitleNeedsAttention => 'Needs attention';

  @override
  String get attentionDismissAction => 'Dismiss';

  @override
  String attentionKraRefused(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count receipts',
      one: '1 receipt',
    );
    return 'KRA refused $_temp0';
  }

  @override
  String get attentionKraRefusedDetail =>
      'The shop details KRA is using need correcting.';

  @override
  String get attentionKraRefusedFixAction => 'Fix details';

  @override
  String get attentionKraRefusedRetryAction => 'Try again';

  @override
  String attentionKraPending(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count receipts',
      one: '1 receipt',
    );
    return 'Waiting on KRA for $_temp0';
  }

  @override
  String get attentionKraPendingDetail =>
      'These are recorded locally. They will issue on their own.';

  @override
  String get attentionKraRetryAction => 'Retry now';

  @override
  String get attentionKraRetryFailed =>
      'Could not reach KRA. The receipts stay queued and will go up on the next connection.';

  @override
  String attentionUnverifiedPayments(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payments',
      one: '1 payment',
    );
    return '$_temp0 not confirmed';
  }

  @override
  String get attentionUnverifiedPaymentsDetail =>
      'Taken while offline. Check each one against the till roll.';

  @override
  String attentionImportProblems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rows',
      one: '1 row',
    );
    return '$_temp0 failed to import';
  }

  @override
  String get attentionImportProblemsDetail =>
      'Fill in what the file was missing and they are imported.';

  @override
  String get attentionImportProblemsAction => 'Finish now';

  @override
  String get analyticsChartTitleSalesByDay => 'Sales by day';

  @override
  String get loginNoAccountsYetTitle => 'This till has no accounts yet';

  @override
  String reportsTransactionCaption(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions',
      one: '1 transaction',
    );
    return '$_temp0';
  }

  @override
  String get activityTitle => 'Activity';

  @override
  String activitySummary(num entries, num shops) {
    String _temp0 = intl.Intl.pluralLogic(
      shops,
      locale: localeName,
      other: '$shops shops',
      one: '1 shop',
    );
    String _temp1 = intl.Intl.pluralLogic(
      entries,
      locale: localeName,
      other: '$entries changes',
      one: '1 change',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get activityViewMerged => 'Everything';

  @override
  String get activityViewByShop => 'By shop';

  @override
  String get activityEmptyTitle => 'No activity yet';

  @override
  String get activityEmptyMessage =>
      'Changes to stock, prices, staff, backups and settings will appear here for every shop on this phone.';

  @override
  String get activityLoadFailed =>
      'Could not read the activity log for your shops.';

  @override
  String get activityShopEmpty => 'Nothing yet in this shop.';

  @override
  String get activityShopUnreadable => 'Unreadable';

  @override
  String get activityShopUnreadableDetail =>
      'This shop\'s activity log could not be read on this phone. Its changes are still recorded; the log simply cannot be shown here.';

  @override
  String get activityProductCreated => 'Product added';

  @override
  String get activityProductUpdated => 'Product changed';

  @override
  String get activityBarcodeAdded => 'Barcode added';

  @override
  String get activityBarcodeRemoved => 'Barcode removed';

  @override
  String get activityBarcodeKindChanged => 'Barcode label changed';

  @override
  String get activityStockAdjusted => 'Stock adjusted';

  @override
  String get activitySaleRecorded => 'Sale recorded';

  @override
  String get activityShotCupSold => 'Cup sold';

  @override
  String get activityStaffAdded => 'Staff added';

  @override
  String get activityStaffRemoved => 'Staff removed';

  @override
  String get activityStaffPinReset => 'PIN reset';

  @override
  String get activityPaymentChanged => 'Payment method changed';

  @override
  String get activityPrinterPaired => 'Printer paired';

  @override
  String get activityPrinterSaved => 'Printer settings saved';

  @override
  String get activityTaxChanged => 'Tax settings changed';

  @override
  String get activitySyncChanged => 'Backup sync settings changed';

  @override
  String get activityBackupExported => 'Backup exported';

  @override
  String get activityBackupRestored => 'Backup restored';

  @override
  String get activityBackupErased => 'Backup erased';

  @override
  String get activityShopSwitched => 'Switched shop';

  @override
  String get activityShopCreated => 'Shop created';

  @override
  String get activityShiftOpened => 'Shift opened';

  @override
  String get activityShiftClosed => 'Shift closed';

  @override
  String get activityIdentityLinked => 'Online account linked';

  @override
  String get activityProductPhotoSet => 'Product photo added';

  @override
  String get activityProductPhotoRemoved => 'Product photo removed';

  @override
  String get activityOwnerPinReset => 'Owner PIN reset';

  @override
  String get activityAccountDeleted => 'Account deleted and data erased';

  @override
  String get activityVariantAdded => 'Variant added';

  @override
  String get activityVariantUpdated => 'Variant changed';

  @override
  String get activityVariantRemoved => 'Variant removed';

  @override
  String reportsStaffRowSpoken(
      num count, Object name, Object profit, Object total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions',
      one: '1 transaction',
    );
    return '$name, $_temp0, taking $total, profit $profit';
  }

  @override
  String get portfolioTitle => 'All shops';

  @override
  String get portfolioOpenAction => 'How all my shops are doing';

  @override
  String get portfolioRangeWeek => '7 days';

  @override
  String get portfolioRangeLabel => 'Date range';

  @override
  String get portfolioRangeCurrent => 'current range';

  @override
  String get portfolioRangeMonth => '30 days';

  @override
  String get portfolioRangeQuarter => '90 days';

  @override
  String get portfolioSharedTitle => 'Who\'s taking what';

  @override
  String get portfolioShopsTitle => 'Shops';

  @override
  String get portfolioTotalRevenue => 'Total takings';

  @override
  String get portfolioProfit => 'Profit';

  @override
  String get portfolioTransactions => 'Sales';

  @override
  String get portfolioAvgBasket => 'Avg basket';

  @override
  String portfolioTopShop(Object amount, Object shop) {
    return 'Busiest: $shop at $amount';
  }

  @override
  String get portfolioEmptyTitle => 'No shops to report yet';

  @override
  String get portfolioEmptyMessage =>
      'Add a shop on this device, or check the internet connection and try again.';

  @override
  String get portfolioFailureMessage =>
      'Couldn\'t load the shop figures. This view needs a connection.';

  @override
  String portfolioShopRowSpoken(
      num count, Object profit, Object revenue, Object share, Object shop) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions',
      one: '1 transaction',
    );
    return '$shop, $revenue takings, $profit profit, $_temp0, $share of all shops';
  }

  @override
  String get productSizeLabelKilogram => 'How many litres the tank holds (ml)';

  @override
  String get productUnitKilogram => 'Tank (kg)';

  @override
  String get variantUnitKilogram => 'Tank (kg)';

  @override
  String get tankFormTitle => 'Add a tank';

  @override
  String get tankFormSubtitle =>
      'A tank is a big container you pour drinks from. It can hold beer, soda or anything else you sell by the cup. Write what is in it and how you sell it. You can add as many tanks as you want.';

  @override
  String get tankFieldName => 'What is in the tank?';

  @override
  String get tankFieldNameHint =>
      'Write the name of the drink. For example: Tusker.';

  @override
  String get tankFieldCapacityL => 'How much the tank holds (litres)';

  @override
  String get tankFieldCapacityLHint =>
      'Write a number. A big drum holds 50 litres — write 50.';

  @override
  String get tankFieldTankCount => 'How many full tanks you have now';

  @override
  String get tankFieldTankCountHint =>
      'Write a number, like 1 or 2. Use 0 if the delivery has not arrived yet.';

  @override
  String get tankFieldTankCost => 'What one full tank cost you (KSh)';

  @override
  String get tankFieldTankCostHint =>
      'The money you paid for the whole tank. We use it to work out the profit on every cup.';

  @override
  String get tankCapacityInvalid =>
      'Write how much the tank holds. Only numbers, like 50.';

  @override
  String get tankCountRequired =>
      'Write how many tanks you have. Use 0 if none have arrived yet.';

  @override
  String get tankNameRequired => 'Write what is in the tank.';

  @override
  String get tankAddAction => 'Save this tank';

  @override
  String get tankPriceInvalid =>
      'Write what one full tank cost you. Only numbers.';

  @override
  String get tankSaveFailed =>
      'That tank could not be saved. Your numbers are still here — try again.';

  @override
  String get tankAddEntry => 'Add a tank';

  @override
  String get tankServingsTitle => 'How do you sell it?';

  @override
  String get tankServingsHint =>
      'Write each cup you sell. For example a small cup and a big cup.';

  @override
  String tankServingLabel(Object n) {
    return 'Cup $n';
  }

  @override
  String get tankFieldServingName => 'What do you call it?';

  @override
  String get tankFieldServingNameHint => 'For example: Small cup, Big cup.';

  @override
  String get tankFieldServingMl => 'How much is in one cup (ml)';

  @override
  String get tankFieldServingMlHint =>
      'For example: 330. Leave it empty if you do not know.';

  @override
  String get tankFieldServingPrice => 'Price for one cup (KSh)';

  @override
  String get tankFieldServingPriceHint => 'What you sell one cup for.';

  @override
  String get tankServingAdd => 'Add another cup';

  @override
  String get tankServingRemove => 'Remove this cup';

  @override
  String get tankServingNameRequired => 'Write what you call this cup.';

  @override
  String get tankServingPriceInvalid =>
      'Write the price for one cup. Only numbers.';

  @override
  String get tankServingSizeInvalid =>
      'Write how much is in one cup, or leave it empty.';

  @override
  String get tankServingTooBig => 'That cup is bigger than the tank.';

  @override
  String get tankServingMinOne => 'Write at least one cup you sell.';

  @override
  String tankCreated(Object name) {
    return '$name is added. You can now sell it in the cups you set.';
  }

  @override
  String get actionTryAgain => 'Try again';

  @override
  String get actionBack => 'Back';

  @override
  String get actionSkip => 'Skip';

  @override
  String get actionSendCopy => 'Send a copy';

  @override
  String get loginWhoAreYou => 'Who are you?';

  @override
  String get supportMarkResolved => 'Mark as solved';

  @override
  String get analyticsReorderInInventory => 'Ask for more in Stock';

  @override
  String get reportsShiftAndTillSection => 'Money in the till';

  @override
  String inventoryWhichVariant(Object name) {
    return 'Which size of $name?';
  }

  @override
  String inventoryRemoveConfirm(Object name) {
    return 'Remove $name?';
  }

  @override
  String get servingAllInCart => 'Everything left is already in the cart';

  @override
  String servingFractionLeft(Object count) {
    return 'Only $count of a bottle is left';
  }

  @override
  String sellAllVariantInCart(Object name) {
    return 'All of $name is already in the cart.';
  }

  @override
  String sellNoVariantLeft(Object name) {
    return 'There is no $name left. Take some out of the cart first.';
  }

  @override
  String sellNotEnoughForShot(Object name) {
    return 'There is not enough $name left for another cup. Take some out of the cart first.';
  }

  @override
  String sellNotEnoughLeft(Object name) {
    return 'There is not enough $name left. Take some out of the cart first.';
  }

  @override
  String shotNoVolume(Object name) {
    return '$name has no size written, so a cup cannot be taken from it';
  }

  @override
  String shotNoneLeft(Object name) {
    return 'There is no $name left';
  }

  @override
  String get shotCupNoSize =>
      'This cup has no size, so the container will not go down when you sell it';

  @override
  String shotCupTooBig(Object ml) {
    return 'This cup is bigger than the container ($ml ml)';
  }

  @override
  String shotCountLeft(Object count) {
    return '$count cups left in the container';
  }

  @override
  String get reportsPrinterOffPairFirst =>
      'Printing is switched off. Join a printer in Settings first.';

  @override
  String get reportsPrinterOff => 'Printing is switched off.';

  @override
  String get reportsSendingToPrinter => 'Sending the receipt to the printer…';

  @override
  String get reportsReceiptReprinted => 'The receipt printed again.';

  @override
  String reportsPrintFailedWith(Object advice) {
    return 'Could not print. $advice';
  }

  @override
  String get reportsNoSalesByCashier =>
      'Nothing on this till was sold by that person.';

  @override
  String get reportsCashierReportWaiting =>
      'Once a shift is opened and a sale is rung up, this report has something to show.';

  @override
  String get shiftNeedsStaffEntry =>
      'A shift needs a worker. Add yourself in Settings, then open the shift again.';

  @override
  String sellTileStockCountLow(Object quantity) {
    return '$quantity in stock · running low';
  }

  @override
  String get sellNoStockLeft => 'There is none left';

  @override
  String get portionFullLabel => 'Full bottle';

  @override
  String get portionHalfLabel => 'Half';

  @override
  String get portionQuarterLabel => 'Quarter';

  @override
  String get supportStatusOpen => 'Open';

  @override
  String get supportStatusInProgress => 'Being worked on';

  @override
  String get supportStatusResolved => 'Done';

  @override
  String get reportsNoSalesTitle => 'No sales written yet';

  @override
  String get reportsOpenTillReport => 'Open the till report';

  @override
  String get reportsClearSearch => 'Clear the search';

  @override
  String get dashboardCouldNotLoad => 'Could not read today\'s numbers.';

  @override
  String get dashboardStillWorksDetail =>
      'The till still works. Pull to try again, or look at the data in Settings.';

  @override
  String get analyticsReportingPeriod => 'Shown for';

  @override
  String get analyticsNothingToCompare => 'nothing to compare against';

  @override
  String get analyticsNoChange => 'no change';

  @override
  String portfolioShiftsCounted(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shifts counted',
      one: '1 shift counted',
    );
    return '$_temp0';
  }

  @override
  String portfolioShiftsOpenNow(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open now',
      one: '1 open now',
    );
    return '$_temp0';
  }

  @override
  String portfolioDrawerShort(Object amount) {
    return 'drawer short $amount';
  }

  @override
  String portfolioDrawerOver(Object amount) {
    return 'drawer over $amount';
  }

  @override
  String get portfolioShiftsNone => 'no shifts yet';

  @override
  String get sellOutOfStockHint => 'Tap to see why it cannot be sold';

  @override
  String get sellNoPriceSetYet =>
      'This item has no price and no cup to sell by yet. Set a price in Stock.';

  @override
  String get loginNotInThisShop =>
      'That person is not in this shop. Pick the shop they work in.';

  @override
  String get analyticsMarginLabel => 'Margin';

  @override
  String get inventoryRepackAction => 'Repack stock';

  @override
  String get inventoryRepackTitle => 'Repack stock';

  @override
  String get inventoryRepackSourceProduct => 'Source product';

  @override
  String get inventoryRepackSourceQuantity => 'Source quantity used';

  @override
  String get inventoryRepackSourceHelp => 'For example, 10 kg of bulk sugar';

  @override
  String get inventoryRepackOutputProduct => 'Output product';

  @override
  String get inventoryRepackOutputQuantity => 'Output quantity made';

  @override
  String get inventoryRepackOutputHelp => 'For example, 20 packets of 500 g';

  @override
  String get inventoryRepackCancel => 'Cancel';

  @override
  String get inventoryRepackRecord => 'Record repack';

  @override
  String get inventoryRepackSaved =>
      'Repack recorded. Stock sync will include both movements.';

  @override
  String get inventoryRepackInsufficientStock =>
      'Repack cannot use more stock than is available.';

  @override
  String get inventoryRepackFailed => 'Repack could not be recorded.';

  @override
  String get drinksAnalyticsTitle => 'Drinks operations';

  @override
  String get drinksAnalyticsLitresSold => 'Litres sold';

  @override
  String get drinksAnalyticsPourSales => 'Pour sales';

  @override
  String get drinksAnalyticsMeasuredLines => 'Measured servings';

  @override
  String get drinksAnalyticsOpenTabs => 'Open tabs';

  @override
  String get drinksAnalyticsTankBalance => 'Tank balance';

  @override
  String get drinksAnalyticsWaste => 'Waste/spillage';

  @override
  String get drinksAnalyticsDipVariance => 'Dip variance';

  @override
  String get drinksAnalyticsDipBelow => 'below expected';

  @override
  String get drinksAnalyticsDipAbove => 'above expected';

  @override
  String get drinksAnalyticsNoTankData => 'No tank balance recorded';

  @override
  String drinksAnalyticsLitres(Object amount) {
    return '$amount L';
  }
}
