// PIN rules for SimpleSales Authentication V2.
//
// ## V2 STAFF PIN
//
// Staff PINs are six digits in V2. New PINs, resets, and changes require six
// digits. During migration, login accepts a legacy four-digit PIN or a V2
// six-digit PIN so existing staff can sign in before migrating.
//
// The OWNER's PIN is an ADMIN PIN and it is SIX digits.
library;

/// The lengths a PIN can be, and the rules that go with them.
class PinRules {
  const PinRules._();

  /// V2 staff PIN length for new/reset/changed PINs.
  static const int staffLength = 6;

  /// Maximum staff PIN length accepted during login migration.
  static const int staffLoginMaxLength = 6;

  /// Legacy staff PIN length accepted during migration.
  static const int staffLegacyLength = 4;

  /// The owner's admin PIN: six digits.
  static const int adminLength = 6;

  /// A V2 staff PIN is six digits.
  static final RegExp staffPattern = RegExp(r'^\d{6}$');

  /// Login accepts legacy 4-digit or V2 6-digit staff PINs during migration.
  static final RegExp staffLoginPattern = RegExp(r'^(?:\d{4}|\d{6})$');

  /// An admin PIN is six digits, and only digits.
  static final RegExp adminPattern = RegExp(r'^\d{6}$');

  /// Whether [pin] is a well-formed V2 staff PIN for create/change/reset.
  static bool isStaffPin(String pin) => staffPattern.hasMatch(pin);

  /// Whether [pin] is acceptable for staff login during migration.
  static bool isStaffLoginPin(String pin) => staffLoginPattern.hasMatch(pin);

  /// Whether [pin] is a well-formed admin PIN.
  static bool isAdminPin(String pin) => adminPattern.hasMatch(pin);
}
