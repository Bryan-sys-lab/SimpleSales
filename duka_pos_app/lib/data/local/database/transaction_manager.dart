import 'package:sqflite/sqflite.dart';

import 'database_session.dart';

/// Transaction manager for atomic business operations.
///
/// Wraps a body in a single SQLite transaction so that all changes succeed or
/// fail together. Used by repositories and use cases to guarantee that a
/// complete business operation (sale, return, expense, stock adjustment, job
/// completion) is atomic.
///
/// A repository should never independently commit half of a larger business
/// operation — the transaction manager is the single write path for composed
/// operations.
class TransactionManager {
  TransactionManager._();
  static final TransactionManager instance = TransactionManager._();

  /// Runs [body] inside a transaction on [session].
  ///
  /// All database changes in [body] are committed together, or rolled back on
  /// any failure. Returns the value produced by [body].
  ///
  /// Example:
  /// ```dart
  /// await transactionManager.run(session, (txn) async {
  ///   await salesRepository.recordSaleInTransaction(txn, command: cmd);
  ///   await inventoryRepository.decrementStockInTransaction(txn, ...);
  ///   await financeRepository.appendEventInTransaction(txn, ...);
  /// });
  /// ```
  Future<T> run<T>(
    DatabaseSession session,
    Future<T> Function(Transaction txn) body,
  ) async {
    return session.transaction(body);
  }
}
