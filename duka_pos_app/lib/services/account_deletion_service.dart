import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart'
    show compute, immutable, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../db/database_helper.dart';
import '../models/audit_log.dart';
import 'audit_actor.dart';
import 'auth_service.dart';
import 'backend_service.dart';
import 'encrypted_backup_service.dart';
import 'oidc_service.dart';
import 'product_image_store.dart';
import 'staff_credential_cache.dart';
import 'workspace_service.dart';

/// How an attempt to delete the shop's online account ended.
///
/// A sealed set rather than a bool: "the PIN was wrong" and "the server was
/// unreachable" need different words on screen, and collapsing them into
/// `false` makes the UI guess.
enum AccountDeletionFailure {
  /// The admin PIN did not match, so nothing was touched.
  wrongPin,

  /// Too many wrong PINs: the till-wide lockout is running.
  lockedOut,

  /// The local erasure could not be completed, so nothing was destroyed.
  localErasureFailed,
}

/// Proof that an account was deleted, for the owner to keep.
///
/// The one artefact of a deletion that is deliberately NOT erased: without it
/// a shop that deleted its account has nothing to show a customer, an auditor
/// or the shop's own records office. It carries no personal data — no name, no
/// email, no tenant — only that the deletion happened and when.
@immutable
class AccountDeletionReport {
  const AccountDeletionReport({
    required this.deletionId,
    required this.completedAt,
    required this.remoteDeleted,
    required this.compacted,
    this.localAccountsDeleted = false,
  });

  /// A random identifier, so two deletions are distinguishable.
  final String deletionId;

  /// When the local erasure finished, in UTC.
  final DateTime completedAt;

  /// Whether the server confirmed it too.
  final bool remoteDeleted;

  /// Whether the file was fully compacted afterwards.
  ///
  /// False means the data is unreadable but the file was never rewritten, so
  /// plaintext may still sit in free pages — a materially different situation
  /// from a clean erasure, and reported rather than hidden.
  final bool compacted;

  /// Whether the local cashier logins were DELETED, rather than only sealed.
  ///
  /// Sealing makes them unusable; deleting removes the rows, and with them the
  /// PIN hashes that would otherwise still sit in the file. The owner chooses
  /// this, because the two are not the same promise: a till whose cashiers can
  /// still sign in is a till somebody else can use.
  final bool localAccountsDeleted;
}

/// Thrown when a deletion cannot start, before anything has been erased.
class AccountDeletionException implements Exception {
  const AccountDeletionException(this.reason, [this.cause]);

  final AccountDeletionFailure reason;
  final Object? cause;

  @override
  String toString() => 'AccountDeletionException($reason)';
}

/// What crosses the isolate boundary for the erasure key derivation.
///
/// Plain data only: a `SecretKey` is a handle on the isolate that made it.
@immutable
class ErasureKeyRequest {
  const ErasureKeyRequest(this.salt, this.pin, this.iterations);

  final List<int> salt;
  final String pin;
  final int iterations;
}

/// Deletes a shop's online account, and makes the data it held unusable.
///
/// ## Why the erasure is cryptographic, not just a delete
///
/// A `DELETE` leaves the row's bytes in the database file until something
/// overwrites that page, and the encrypted backups this app already makes are
/// copies of exactly those bytes. So "we deleted the account" would still leave
/// a readable copy in every backup taken before the deletion — which is the
/// situation the owner is asking to escape.
///
/// So the deletion goes the other way round:
///
///  1. Every personal field is overwritten with AES-256-GCM ciphertext under a
///     key derived from the admin PIN.
///  2. The key material is destroyed, so the ciphertext cannot be decrypted by
///     anyone, including a later restore of an older backup.
///  3. The database is `VACUUM`ed, which rewrites the file without the pages
///     that held the original values. Without this step the plaintext is still
///     sitting in free pages, so this is not optional.
///  4. The encryption key for the local backup files is deleted too, which is
///     what makes already-written `.duka` files unreadable.
///
/// What survives is the ledger's financial figures — the takings, the stock,
/// the tax rates — because those are the shop's books rather than its people.
/// Every field that names or contacts a person is destroyed.
class AccountDeletionService {
  AccountDeletionService._();

  /// Per-shop salt for the erasure key, in the OS keystore.
  ///
  /// Destroyed at the end of a successful deletion, which is what makes the
  /// ciphertext above permanently unreadable.
  static const _saltKey = 'duka_pin_erasure_salt_v1';

  /// Iterations for the erasure key. Deliberately the same order as
  /// [AuthService.defaultIterations] so a PIN takes comparable work to use for
  /// either purpose — an erasure key that is cheap to derive is also cheap to
  /// brute-force by anyone who obtained a backup file.
  static const _iterations = 150000;

  /// Not `const`, unlike the backup service's cipher: the cryptography package's
  /// factory is not const-constructible.
  static final AesGcm _cipher = AesGcm.with256bits();

  /// The keystore. Injectable so a test can substitute an in-memory one.
  @visibleForTesting
  static FlutterSecureStorage? storageForTest;

  static FlutterSecureStorage get _storage =>
      storageForTest ?? const FlutterSecureStorage();

  /// Deletes the account behind [pin], and erases what the shop held.
  ///
  /// The PIN is verified locally FIRST and the till-wide lockout is honoured,
  /// so a phone left unlocked on a counter cannot be wiped by someone who does
  /// not know the admin PIN. Nothing is erased unless that check passes.
  static Future<AccountDeletionReport> deleteAccount({
    required String pin,
    bool deleteLocalAccounts = false,
  }) async {
    if (pin.trim().isEmpty) {
      throw const AccountDeletionException(AccountDeletionFailure.wrongPin);
    }
    if (await AuthService.isTillLockedOut()) {
      throw const AccountDeletionException(AccountDeletionFailure.lockedOut);
    }

    final owner = await DatabaseHelper.instance.getOwner();
    // A till that was never set up has nothing to delete.
    if (owner == null) {
      throw const AccountDeletionException(AccountDeletionFailure.wrongPin);
    }
    if (!await AuthService.verifyPin(pin, owner.pinHash)) {
      // The same key the login pad and the settings dialogs count against, so
      // this is not a fourth private PIN budget to guess against.
      await AuthService.recordFailure(AuthService.ownerLockoutKey);
      throw const AccountDeletionException(AccountDeletionFailure.wrongPin);
    }

    // A new deletion attempt supersedes any earlier pending one: the local
    // data is about to be destroyed, so there is nothing left to retry.
    await _clearPendingDeletion();

    final salt = await _erasureSalt();
    final derived = await compute(
      _deriveErasureKey,
      ErasureKeyRequest(salt, pin.trim(), _iterations),
    );

    // Pre-erasure compaction, fatal on failure. Reclaims free pages BEFORE the
    // ciphertext is written — the ciphertext is longer than the plaintext it
    // replaces, so a full disk cannot leave the file with nowhere to grow.
    // On failure nothing is overwritten, the PIN still works, and the deletion
    // can simply be retried.
    try {
      await (await DatabaseHelper.instance.database).execute('VACUUM');
    } on Object catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailure.localErasureFailed,
        error,
      );
    }

    final String deletionId;
    try {
      deletionId = await _eraseLocalData(
        derived,
        deleteLocalAccounts: deleteLocalAccounts,
      );
    } on Object catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailure.localErasureFailed,
        error,
      );
    }

    // The key material is destroyed HERE, the moment the ciphertext has
    // committed.
    //
    // Destroying first means the window is the instant between the transaction
    // committing and the delete returning, which no remote call can straddle.
    //
    // It must not THROW, though: by this point the data is already erased, so
    // a failure in the cleanup would abort the deletion halfway and leave the
    // owner with a blanked app, no receipt and no explanation — which is
    // exactly the failure this ordering was written to avoid.
    await _destroyKeyMaterial();

    // Follow-up compaction. Checkpoint the WAL first so the VACUUM can actually
    // reclaim the pages that held the now-ciphertext values; without it the
    // plaintext can linger in WAL frames.
    try {
      await (await DatabaseHelper.instance.database)
          .execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } on Object catch (_) {
      // WAL checkpoint is best-effort; VACUUM still rewrites the main file.
    }
    try {
      await (await DatabaseHelper.instance.database).execute('VACUUM');
      _compactionCompleted = true;
    } on Object catch (_) {
      _compactionCompleted = false;
    }

    // The remote account is deleted after the data is unrecoverable, so a
    // failure to reach the server leaves the owner already protected rather than
    // still online while the owner is told it is gone. The failure is recorded
    // as pending so it can be retried on launch.
    //
    // The SESSION is still alive here, and that is deliberate: the delete
    // request carries the bearer token, and a deletion sent without it is a
    // request the server is entitled to refuse. The session is torn down
    // locally AFTER the request, not before it.
    var remoteDeleted = false;
    try {
      remoteDeleted = await _deleteRemoteAccount(email: owner.email);
    } catch (_) {
      remoteDeleted = false;
      // Persist a pending-deletion record so the next launch retries until the
      // online account is gone — required for Play Store data-deletion compliance.
      try {
        await _savePendingDeletion(owner.email);
      } catch (_) {
        // Secure storage failure must not mask the fact the local erasure done.
      }
    }

    // The session goes LAST, and LOCALLY.
    //
    // Locally, because ending the provider's session means opening the system
    // browser at the provider's logout page, which lands the owner on a LOGIN
    // screen — with a "Register" option — in the middle of deleting the
    // account they are trying to close. An app that is erasing itself must not
    // answer that with a sign-up form.
    //
    // Last, because the delete request above needs the token.
    await _clearSessionLocally();

    return AccountDeletionReport(
      deletionId: deletionId,
      completedAt: DateTime.now().toUtc(),
      remoteDeleted: remoteDeleted,
      compacted: _compactionCompleted,
      localAccountsDeleted: deleteLocalAccounts,
    );
  }

  /// Tears down the session without opening the provider's logout page.
  ///
  /// Best effort: the account is already deleted and the local data is already
  /// unreadable, so a failure here cannot brick anything — it can only leave a
  /// token on a device whose account no longer exists.
  static Future<void> _clearSessionLocally() async {
    try {
      await OidcService.clearLocalSession();
    } catch (_) {
      // Nothing here may throw. The deletion has already happened.
    }
  }

  /// The deletion id, which is also the row written to the audit log so the
  /// action itself is still logged after everything else is gone.
  ///
  /// The list of columns is DECLARED rather than pattern-matched on purpose.
  ///
  /// A schema walk matching `*_name`/`*_email` would be shorter and would miss
  /// nothing new — but it would also have to guess about `role`, and it hides
  /// the list, which is the one thing a reviewer of an erasure path wants to
  /// read. So the columns are written out, and `account_deletion_test.dart`
  /// walks the real schema after a deletion asserting that no column in ANY
  /// table still holds one of the plaintext values. A column added later that
  /// is not declared here fails that test rather than surviving quietly.
  static Future<String> _eraseLocalData(
    List<int> keyBytes, {
    required bool deleteLocalAccounts,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final key = await _cipher.newSecretKeyFromBytes(keyBytes);
    final now = DateTime.now().toUtc().toIso8601String();
    final deletionId = _newDeletionId(now);

    await db.transaction((txn) async {
      await _eraseColumn(txn, 'owner', 'name', key);
      await _eraseColumn(txn, 'owner', 'email', key);
      await _eraseColumn(txn, 'owner', 'shop_name', key);
      await _eraseColumn(txn, 'owner', 'pin_hash', key);

      await _eraseColumn(txn, 'staff', 'name', key);
      await _eraseColumn(txn, 'staff', 'pin_hash', key);
      await _eraseColumn(txn, 'staff', 'username', key);

      // AND THEN THE LOGINS THEMSELVES, when the owner asked for it.
      //
      // Sealing the columns above makes the logins unusable: the PIN hash is
      // ciphertext and the credential cache is destroyed with the key material.
      // But the ROWS are still there, and a row that says "there was a cashier
      // here" is a fact the owner asked to have erased.
      //
      // So the rows go too. The delete happens after the sealing, not instead
      // of it: a `DELETE` leaves the bytes in the file until something
      // overwrites that page, and the vacuum that follows this transaction is
      // what reclaims them. Doing both means the row is gone AND the bytes it
      // left behind are unreadable in the window before the vacuum.
      if (deleteLocalAccounts) {
        await txn.delete('staff');
      }

      // Names denormalised onto the ledger rows when the sale was written —
      // and onto the other three tables that record the same person. `shifts`
      // and `stock_adjustments` were both missed by the first version of this
      // list, so a deleted shop still had its cashiers' names on every shift
      // and every stock adjustment.
      await _eraseColumn(txn, 'sales', 'staff_name', key);
      await _eraseColumn(txn, 'sales', 'payment_reference', key);
      await _eraseColumn(txn, 'shifts', 'staff_name', key);
      await _eraseColumn(txn, 'stock_adjustments', 'staff_name', key);
      await _eraseColumn(txn, 'stock_adjustments', 'reason', key);
      await _eraseColumn(txn, 'pending_payments', 'phone_number', key);
      await _eraseColumn(txn, 'pending_payments', 'staff_name', key);
      await _eraseColumn(txn, 'pending_payments', 'cart_json', key);

      // The tombstone itself records the remote id of the deleted cashier;
      // seal it too so a deleted account leaves no trace of who was removed.
      await _eraseColumn(txn, 'staff_deletion_tombstones', 'remote_id', key);

      // Both logs name people in every row.
      await _eraseColumn(txn, 'audit_log', 'actor_name', key);
      await _eraseColumn(txn, 'audit_log', 'detail', key);
      await _eraseColumn(txn, 'crash_log', 'actor_name', key);
      await _eraseColumn(txn, 'crash_log', 'message', key);

      // Shop configuration that identifies the business: the KRA TIN, the
      // till code, and any email the owner typed into settings.
      for (final keyName in const <String>[
        'tin',
        'till_code',
        'owner_email',
        'shop_email',
      ]) {
        await _eraseSetting(txn, keyName, key);
      }

      // The deletion itself, which is the only row written in this direction.
      //
      // Written through the model rather than raw SQL so it carries the same
      // wire values the reader expects, and so it survives the `VACUUM` that
      // follows as an ordinary row.
      await txn.insert(
        'audit_log',
        AuditActor.deleted()
            .entry(
              AuditAction.accountDeleted,
              AuditEntity.account,
              entityId: deletionId,
              detail:
                  'online account deleted; personal data erased on this device',
            )
            .toMap(),
      );
    });

    // Follow-up compaction, which is best-effort rather than fatal.
    //
    // By this point the columns are already ciphertext and the key material is
    // about to be destroyed, so a failure here cannot brick anything: the
    // pre-erasure compaction above already guaranteed disk headroom, and the
    // key material is still alive until this point returns. All a failure
    // leaves behind is plaintext in un-vacuumed free pages, which no reader can
    // reach through SQL, and which the receipt below names so the shop can
    // re-run it.
    try {
      await db.execute('VACUUM');
      _compactionCompleted = true;
    } on Object catch (_) {
      _compactionCompleted = false;
    }

    return deletionId;
  }

  /// True when the post-erasure compaction succeeded.
  ///
  /// Reported on the receipt because "the data is unreadable but the file was
  /// never fully rewritten" is a materially different situation from a clean
  /// erasure, and the only person who can act on it is the owner.
  static bool _compactionCompleted = true;

  /// Whether the last deletion left the file fully compacted.
  @visibleForTesting
  static bool get compactionCompleted => _compactionCompleted;

  /// Overwrites one TEXT column in [table] with ciphertext under [key].
  ///
  /// Row by row, by primary key. A single `UPDATE ... WHERE column = ?` would
  /// look tidier and is wrong: two rows that share a value would both be
  /// rewritten by the first pass, and the second pass would then match nothing
  /// — so the count of rows sealed would depend on how often the value
  /// repeated, which is exactly the kind of thing that makes an erasure look
  /// complete when it is not.
  ///
  /// Each row is sealed on its own even when the values match, so the ciphertext
  /// does not advertise which rows held the same name.
  ///
  /// A NULL or empty column is skipped: a blank phone number is not personal
  /// data, and encrypting nothing would only move nothing around.
  static Future<void> _eraseColumn(
    DatabaseExecutor txn,
    String table,
    String column,
    SecretKey key,
  ) async {
    if (!await _hasColumn(txn, table, column)) return;
    final pk = await _primaryKey(txn, table);
    if (pk == null) return;

    final rows = await txn.query(
      table,
      columns: <String>[pk, column],
      where: '$column IS NOT NULL AND $column != \'\'',
    );
    for (final row in rows) {
      final current = row[column] as String?;
      final id = row[pk];
      if (current == null || current.isEmpty || id == null) continue;
      await txn.update(
        table,
        <String, Object?>{column: await _seal(current, key)},
        where: '$pk = ?',
        whereArgs: <Object?>[id],
      );
    }
  }

  static Future<void> _eraseSetting(
    DatabaseExecutor txn,
    String keyName,
    SecretKey key,
  ) async {
    final rows = await txn.query('shop_settings',
        columns: <String>['key', 'value'],
        where: 'key = ?',
        whereArgs: <Object?>[keyName]);
    if (rows.isEmpty) return;
    final value = rows.first['value'] as String?;
    if (value == null || value.isEmpty) return;
    await txn.update(
      'shop_settings',
      <String, Object?>{'value': await _seal(value, key)},
      where: 'key = ?',
      whereArgs: <Object?>[keyName],
    );
  }

  /// Whether [table] has a column called [column].
  ///
  /// An upgraded device may be missing a column this service knows about —
  /// `owner.email` only exists from v9 — and the erasure still has to succeed
  /// on a database shaped slightly differently. Skipping is correct: there is
  /// nothing there to erase.
  static Future<bool> _hasColumn(
    DatabaseExecutor txn,
    String table,
    String column,
  ) async {
    final rows = await txn.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }

  /// The column that addresses one row, or null when there is no primary key.
  ///
  /// Every table this erases touches has one, and a table without one would
  /// make a per-row update impossible rather than merely awkward.
  static Future<String?> _primaryKey(
    DatabaseExecutor txn,
    String table,
  ) async {
    final rows = await txn.rawQuery('PRAGMA table_info($table)');
    for (final row in rows) {
      if (row['pk'] == 1) return row['name'] as String?;
    }
    return null;
  }

  /// Encrypts [plaintext] into a self-describing marker.
  ///
  /// The `erased:` prefix is what makes the erasure legible later: a row that
  /// says `erased:Ag...` is unambiguous, whereas random base64 might be a
  /// barcode a shop is supposed to have.
  static Future<String> _seal(String plaintext, SecretKey key) async {
    final box = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: _cipher.newNonce(),
    );
    final joined = <int>[...box.nonce, ...box.cipherText, ...box.mac.bytes];
    return 'erased:${base64Url.encode(joined)}';
  }

  static String _newDeletionId(String now) {
    final random = Random.secure();
    return 'del-${now.replaceAll(':', '')}'
        '-${base64Url.encode(List<int>.generate(6, (_) => random.nextInt(256)))}';
  }

  static Future<List<int>> _erasureSalt() async {
    final existing = await _storage.read(key: _saltKey);
    if (existing != null) return base64Url.decode(existing);
    // Generated rather than fixed, so two shops on one device do not share a
    // salt — a shared salt would let a backup of one shop's ciphertext be
    // attacked with a key derived from the other shop's PIN.
    final salt = _cipher.newNonce();
    await _storage.write(key: _saltKey, value: base64UrlEncode(salt));
    return salt;
  }

  /// Destroys every piece of key material this device holds, and drops the
  /// session that would keep the shop able to reach the deleted account.
  ///
  /// This is the step that makes the erasure permanent rather than reversible:
  /// with the erasure salt and the backup key gone, the ciphertext written
  /// above and every `.duka` file already written are both permanently
  /// unreadable — by this device, by a later restore, and by anyone who took a
  /// copy.
  ///
  /// ## WHY IT MUST NOT THROW
  ///
  /// By the time this runs, the personal data is ALREADY erased. A failure
  /// here used to abort the whole deletion: the owner was left with a till
  /// that could no longer sign anybody in, no receipt, and an error saying
  /// "nothing was changed" — which was a lie, because everything had been.
  ///
  /// So every step here is best-effort and the whole thing is wrapped. The
  /// erasure has happened; the cleanup cannot un-happen it.
  ///
  /// ## THE SESSION
  ///
  /// The session is cleared for the same reason the key material is destroyed:
  /// without it the shop still holds a valid bearer token and a tenant binding
  /// for an account that no longer exists, `isBackendLinked` stays true, and
  /// the six-hourly auto-sync keeps posting the shop's inventory and staff
  /// under it. A deleted account must be unreachable, not merely unlinked.
  ///
  /// It is cleared LOCALLY — see [_clearSessionLocally] — and not by ending the
  /// provider's session, which would open a browser.
  static Future<void> _destroyKeyMaterial() async {
    try {
      await _storage.delete(key: _saltKey);
    } on Object catch (_) {
      // Best effort. The salt's absence is what makes the ciphertext
      // unreadable, but a keystore that refuses a delete cannot be allowed to
      // undo the erasure that has already happened.
    }
    // The offline staff credential cache holds a PBKDF2 hash of every staff PIN
    // PLUS each username in the clear, in the OS keystore. `login_screen`
    // verifies against it as a fallback after `AuthService.verifyPin` fails, so
    // a cache entry survives the erasure of `staff.pin_hash` and still unlocks
    // the till. It is also, by its own doc, meant to be "cleared on sign-out" —
    // which nothing did, so it was a live credential store no path cleaned.
    // The erasure now names it, and the sign-out clearing it claims is a
    // separate gap for the owner session.
    try {
      await StaffCredentialCache.clearAll();
    } on Object catch (_) {
      // Best effort, as above.
    }
    // Also destroys the key the local encrypted backups were written with,
    // which is what makes those files unreadable too.
    try {
      await EncryptedBackupService.cryptographicEraseLocalBackups();
    } on Object catch (_) {
      // Best effort. The backups are unreadable without the key either way.
    }

    // Erase every product photograph and the account avatar: a deleted account
    // leaves no photographs behind, in any workspace.
    try {
      final activeKey = await WorkspaceService.activeWorkspaceKey();
      await ProductImageStore.deleteAllForWorkspace(activeKey);
    } catch (_) {
      // Best effort — the account is already erased; leftover photos are
      // unreadable without the key anyway.
    }

    try {
      await WorkspaceService.register(
        workspaceKey: await WorkspaceService.activeWorkspaceKey(),
        tenantId: null,
        shopName: (await WorkspaceService.activeShopName()) ?? 'Shop',
      );
    } catch (_) {
      // Best effort, as above.
    }
  }

  static Future<bool> _deleteRemoteAccount({required String email}) async {
    if (email.trim().isEmpty) return false;
    final response = await BackendService.deleteRequest('auth/account', {
      'email': email.trim(),
    });
    return response;
  }

  static const _pendingDeletionKey = 'duka_pending_account_deletion';

  /// Persists an email whose remote account deletion failed, so the next launch
  /// can retry until the server confirms it — required for Play Store
  /// data-deletion compliance.
  static Future<void> _savePendingDeletion(String email) async {
    await _storage.write(key: _pendingDeletionKey, value: email.trim());
  }

  /// Clears any earlier pending-deletion record. A new deletion attempt
  /// supersedes the old one because the local data is about to be destroyed.
  ///
  /// Best effort, and it happens BEFORE anything is erased: a keystore that
  /// refuses a delete must not stop the owner from deleting their account.
  static Future<void> _clearPendingDeletion() async {
    try {
      await _storage.delete(key: _pendingDeletionKey);
    } on Object catch (_) {
      // Nothing here may throw. The deletion has not started yet, and refusing
      // to clear an old record is not a reason to refuse the new one.
    }
  }

  /// The email of an account whose remote deletion is still pending, or null.
  static Future<String?> pendingDeletionEmail() async {
    return _storage.read(key: _pendingDeletionKey);
  }

  /// Retries the remote deletion of a pending account. Returns true when the
  /// server confirms, and clears the pending record on success.
  static Future<bool> retryPendingDeletion() async {
    final email = await pendingDeletionEmail();
    if (email == null || email.trim().isEmpty) return false;
    try {
      final ok = await _deleteRemoteAccount(email: email);
      if (ok) {
        await _storage.delete(key: _pendingDeletionKey);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }
}

/// Derives the erasure key from the PIN.
///
/// Top-level and plugin-free so it runs inside `compute`: PBKDF2 at 150k
/// iterations takes long enough to matter, and running it on the UI thread
/// would drop frames on the floor phones this app targets.
Future<List<int>> _deriveErasureKey(ErasureKeyRequest request) async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: request.iterations,
    bits: 256,
  );
  final secretKey = await pbkdf2.deriveKeyFromPassword(
    password: request.pin,
    nonce: request.salt,
  );
  return secretKey.extractBytes();
}
