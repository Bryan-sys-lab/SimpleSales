// How long a PIN is, and whose it is.
//
// ## TWO PINS, TWO LENGTHS
//
// A STAFF PIN is four digits. It is typed forty times a day at a counter by
// someone whose hands are busy, and four digits is as long as a PIN can be
// before it stops being quick.
//
// The OWNER's PIN is an ADMIN PIN and it is SIX digits. Always six — there is
// no four-digit owner PIN, no second kind of owner PIN, and nothing to
// choose. It is typed rarely — to sign in, and to prove ownership before an
// account is deleted or a setting is changed — and it guards the things that
// matter most. The backend's own PIN reset already demands six digits for
// exactly this reason, and the sheet that asks for the admin PIN has always
// asked for six.
//
// ## WHY THE OWNER'S SIGN-IN PIN IS ALSO SIX
//
// Because there is only one owner PIN, and the till asks for it in two
// places: at sign-in, and in Settings to prove ownership. If the sign-in pad
// took four and the proof sheet took six, an owner would be unable to use
// their own till — which is exactly the bug this file exists to remove: the
// setup screen asked for a four-digit PIN, the proof sheet asked for six, and
// account deletion was impossible because nobody had a PIN that satisfied
// both.
//
// The shop's cashiers keep their four-digit PINs. The owner's is longer
// because it is asked for less often and guards more.
library;

/// The lengths a PIN can be, and the rules that go with them.
class PinRules {
  const PinRules._();

  /// A staff member's PIN: four digits.
  static const int staffLength = 4;

  /// The owner's admin PIN: six digits.
  static const int adminLength = 6;

  /// A staff PIN is four digits, and only digits.
  static final RegExp staffPattern = RegExp(r'^\d{4}$');

  /// An admin PIN is six digits, and only digits.
  static final RegExp adminPattern = RegExp(r'^\d{6}$');

  /// Whether [pin] is a well-formed staff PIN.
  static bool isStaffPin(String pin) => staffPattern.hasMatch(pin);

  /// Whether [pin] is a well-formed admin PIN.
  static bool isAdminPin(String pin) => adminPattern.hasMatch(pin);
}
