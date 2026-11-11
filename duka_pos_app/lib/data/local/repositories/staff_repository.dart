import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';
import '../../../models/models.dart';

/// Repository for staff and permissions.
///
/// Manages persistence of staff records, PIN hashes, roles, and permission
/// overrides. Staff operations that touch multiple tables (e.g.
/// `deleteStaffWithTombstone`, which updates sales and stock adjustments
/// alongside the staff row) use transaction-aware variants so the operation
/// is atomic.
class StaffRepository {
  StaffRepository._();
  static final StaffRepository instance = StaffRepository._();

  // ── Transaction-aware variants ─────────────────────────────────────

  /// Deactivates a staff member within an existing transaction.
  Future<void> deactivateStaffInTransaction(Transaction txn, int id) async {
    await txn.update('staff', {'active': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Resets a staff PIN hash within an existing transaction.
  Future<void> resetStaffPinInTransaction(Transaction txn, int id,
      String pinHash) async {
    await txn.update('staff', {'pin_hash': pinHash},
        where: 'id = ?', whereArgs: [id]);
  }

  // ── Public methods ─────────────────────────────────────────────────

  Future<List<Staff>> getStaff({bool activeOnly = true}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('staff',
        where: activeOnly ? 'active = 1' : null, orderBy: 'name');
    return rows.map((r) => Staff.fromMap(r)).toList();
  }

  Future<String?> staffPinHash(int staffId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('staff',
        columns: <String>['pin_hash'],
        where: 'id = ? AND active = 1',
        whereArgs: [staffId],
        limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['pin_hash'] as String?;
  }

  Future<int> addStaff(Staff staff) async {
    final db = await DatabaseHelper.instance.database;
    final values = staff.toMap()..remove('id');
    return db.insert('staff', values);
  }

  Future<void> setStaffRemoteId(int id, String remoteId) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('staff', {'remote_id': remoteId},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateStaffPin(int id, String pinHash) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('staff', {'pin_hash': pinHash},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deactivateStaff(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await deactivateStaffInTransaction(txn, id);
    });
  }

  Future<void> resetStaffPin(int id, String pinHash) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await resetStaffPinInTransaction(txn, id, pinHash);
    });
  }

  Future<void> deleteStaffWithTombstone(Staff staff) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      const deletedLabel = 'Deleted cashier';
      final originalName = staff.name;
      await txn.update('staff', {'active': 0, 'name': deletedLabel},
          where: 'id = ?', whereArgs: [staff.id]);

      for (final table in ['sales', 'stock_adjustments']) {
        await txn.rawUpdate(
            'UPDATE $table SET staff_name = ? WHERE staff_id = ?',
            [deletedLabel, staff.id]);
        if (originalName.isNotEmpty && originalName != deletedLabel) {
          final nameMatches = await txn.rawQuery(
              'SELECT COUNT(*) AS c FROM staff WHERE name = ?', [originalName]);
          if ((nameMatches.first['c'] as int? ?? 0) == 1) {
            await txn.rawUpdate(
                'UPDATE $table SET staff_name = ? WHERE staff_id IS NULL AND staff_name = ?',
                [deletedLabel, originalName]);
          }
        }
      }

      await txn.insert(
          'staff_deletion_tombstones',
          {
            'staff_id': staff.id,
            'remote_id': staff.remoteId,
            'deleted_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> mergeRemoteStaff({
    required String remoteId,
    required String name,
    String? username,
    required String role,
    required bool active,
  }) async {
    if (remoteId.trim().isEmpty) {
      throw ArgumentError.value(remoteId, 'remoteId');
    }
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'staff',
      {
        'name': name,
        if (username != null && username.trim().isNotEmpty)
          'username': username.trim(),
        'role': role,
        'active': active ? 1 : 0,
      },
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  Future<Staff> mergeAuthenticatedStaff({
    required String remoteId,
    required String username,
    required String name,
    required String role,
    required String pinHash,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'staff',
      where: 'remote_id = ? OR username = ?',
      whereArgs: [remoteId, username],
      limit: 1,
    );
    int id;
    if (existing.isEmpty) {
      id = await db.insert('staff', {
        'name': name,
        'username': username,
        'pin_hash': pinHash,
        'active': 1,
        'remote_id': remoteId,
        'role': role,
      });
    } else {
      id = (existing.first['id'] as num).toInt();
      await db.update(
        'staff',
        {
          'name': name,
          'username': username,
          'pin_hash': pinHash,
          'active': 1,
          'remote_id': remoteId,
          'role': role,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    final row =
        await db.query('staff', where: 'id = ?', whereArgs: [id], limit: 1);
    return Staff.fromMap(row.single);
  }
}
