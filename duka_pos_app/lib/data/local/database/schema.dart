import 'package:sqflite/sqflite.dart';

import '../repositories/audit_log_repository.dart';
import '../repositories/crash_log_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/drinks_repository.dart';
import '../repositories/fashion_repository.dart';
import '../repositories/finance_repository.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/job_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/sales_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/staff_repository.dart';
import '../synchronization/sync_conflict_repository.dart';

/// Single source of truth for schema creation on a fresh database.
///
/// Every `CREATE TABLE IF NOT EXISTS` lives in exactly one repository's
/// `createTable` static and is invoked from here. `_onCreate` is called by
/// [DatabaseManager._onCreate] once this file is wired into
/// [DatabaseHelper.createSchema] (Phase 4). Until every domain table has a
/// matching `createTable`, [DatabaseHelper.createSchema] keeps delegating to
/// the historical `_onCreate` so fresh-install and upgraded schemas stay
/// equivalent.
///
/// Tables are created with `IF NOT EXISTS` and in an order that respects
/// foreign-key parents before children, though foreign-key enforcement is
/// disabled for production until legacy rebuilds are verified.
Future<void> onCreate(Database db, int version) async {
  await StaffRepository.createTable(db);
  await SettingsRepository.createTable(db);
  await InventoryRepository.createTable(db);
  await FinanceRepository.createTable(db);
  await SalesRepository.createTable(db);
  await CustomerRepository.createTable(db);
  await JobRepository.createTable(db);
  await DrinksRepository.createTable(db);
  await FashionRepository.createTable(db);
  await AuditLogRepository.createTable(db);
  await CrashLogRepository.createTable(db);
  await NotificationRepository.createTable(db);
  await SyncConflictRepository.createTable(db);
}
