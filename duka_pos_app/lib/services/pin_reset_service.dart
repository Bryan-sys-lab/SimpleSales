import '../db/database_helper.dart';
import '../models/audit_log.dart';
import '../services/app_state.dart';
import 'audit_actor.dart';
import 'auth_service.dart';
import 'backend_service.dart';
import 'package:flutter/foundation.dart' show immutable;

/// What a completed PIN reset produced.
@immutable
class PinResetOutcome {
  const PinResetOutcome({required this.maskedEmail});

  /// The address the code went to, so the owner can be told where to look.
  ///
  /// Masked before the app holds it: a screen the owner is asked to read out
  /// loud should not be showing their address in clear.
  final String maskedEmail;
}

/// Resets a forgotten owner PIN using a code the backend emails.
///
/// ## Why the reset cannot work offline
///
/// A purely local reset — "answer a question, type a new PIN" — would be an
/// authentication bypass wearing a recovery costume: anyone holding an unlocked
/// phone could set the owner PIN and walk into the owner session, the backups
/// and the online account. So the reset is gated on something only the real
/// owner has, which is the address the account was verified with.
///
/// That also means a shop that is offline, or that never verified its identity,
/// cannot reset this way. That is the honest failure: the alternative is a PIN
/// that protects nothing.
///
/// The new hash is made on this device and never leaves it. The backend issues
/// the challenge and checks the code; it cannot know a PBKDF2 hash it never saw,
/// and sending it one would put a password-equivalent on a server.
class PinResetService {
  PinResetService._();

  /// Sends a reset code, and says where it went.
  ///
  /// The address is taken from the owner row on this device, so the caller
  /// never has to ask for one: a reset the owner has to retype the address for
  /// is a reset that fails for the person who most needs it.
  ///
  /// Throws [PinResetException] with the cause.
  static Future<PinResetOutcome> requestCode() async {
    final owner = await DatabaseHelper.instance.getOwner();
    final email = owner?.email.trim() ?? '';
    if (email.isEmpty) {
      // No address on the account means there is nothing to send the code to.
      throw const PinResetException(PinResetFailure.emailUnknown);
    }
    final challengeId = await BackendService.requestPinReset(email: email);
    // Kept on the device, not only in a server session, so the confirm step can
    // prove it is answering the challenge this owner was actually sent —
    // otherwise a code from an earlier attempt could be redeemed later.
    await DatabaseHelper.instance.setSetting(_challengeKey, challengeId);
    return PinResetOutcome(maskedEmail: maskEmail(email));
  }

  /// Completes the reset and installs the new PIN.
  ///
  /// Returns false when the code was refused, so the caller can count the
  /// attempt; throws [PinResetException] for the offline and rate-limited
  /// cases, which need different words on screen.
  ///
  /// [newPin] must be four digits and is refused before the network is touched:
  /// a PIN that is not the shape the pad accepts would lock the owner straight
  /// back out on the next unlock.
  static Future<bool> confirm({
    required String code,
    required String newPin,
    required AppState state,
  }) async {
    if (!RegExp(r'^\d{4}$').hasMatch(newPin)) {
      throw StateError('A PIN is exactly four digits');
    }
    final owner = await DatabaseHelper.instance.getOwner();
    final email = owner?.email.trim() ?? '';
    if (email.isEmpty) {
      throw const PinResetException(PinResetFailure.emailUnknown);
    }
    final challengeId = await _recallChallenge();
    if (challengeId == null) {
      // The challenge expired, or the app restarted since it was asked for.
      throw const PinResetException(PinResetFailure.challengeMissing);
    }

    final accepted = await BackendService.confirmPinReset(
      email: email,
      challengeId: challengeId,
      code: code,
    );
    if (!accepted) return false;

    // Installed only after the server accepted the code, so a wrong code
    // cannot be used to change the PIN it was protecting.
    await installPin(newPin);
    // The code has now been spent, so it must not stay redeemable.
    await forgetChallenge();
    // Attributed by the caller, which holds the session — the same rule every
    // other audit row follows. A reset is exactly the kind of action an audit
    // log exists to record: the session's own credential just changed.
    await recordActionAudit(
      state,
      action: AuditAction.ownerPinReset,
      entity: AuditEntity.owner,
      entityId: 'id-1',
      detail: 'owner PIN reset from a mailed code',
    );
    return true;
  }

  /// Writes the new owner PIN.
  ///
  /// Public so a test can assert the stored hash really changed, and so the
  /// dialog can install it in the one place the owner is watching.
  static Future<void> installPin(String pin) async {
    final hash = await AuthService.hashPin(pin);
    await DatabaseHelper.instance.updateOwnerPin(hash);
  }

  /// Masks an address for display.
  ///
  /// The local part keeps its first character and its length is hidden, so the
  /// owner can recognise their address without the shop around them reading it.
  /// The domain is kept whole, which is what someone checking a typo actually
  /// looks at.
  static String maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return email;
    final local = email.substring(0, at);
    final shown = local.substring(0, local.length < 2 ? local.length : 1);
    return '$shown***${email.substring(at)}';
  }

  /// Clears the remembered challenge.
  ///
  /// Called by the dialog when the owner backs out as well as after a success:
  /// a reset code left redeemable by the next person at the counter is a code
  /// with a lifetime nobody agreed to.
  static Future<void> forgetChallenge() =>
      DatabaseHelper.instance.setSetting(_challengeKey, '');

  static Future<String?> _recallChallenge() async {
    final stored = await DatabaseHelper.instance.getSetting(_challengeKey);
    if (stored == null || stored.trim().isEmpty) return null;
    return stored;
  }

  /// Where the challenge id is kept between the two steps.
  ///
  /// In the shop's own database rather than in SharedPreferences so it is
  /// covered by the same backup and the same per-shop scoping as everything
  /// else about this shop — a reset challenge belonging to shop A must not be
  /// redeemable from shop B on the same device.
  static const _challengeKey = 'pin_reset_challenge_v1';
}
