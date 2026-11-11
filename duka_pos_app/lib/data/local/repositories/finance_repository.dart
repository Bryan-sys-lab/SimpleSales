import '../../../db/database_helper.dart';
import '../../../utils/money.dart';

/// Repository for finance: expenses, payments, ledger.
///
/// Manages persistence of expense records, expense payments, and financial
/// events. Operations that touch multiple tables (e.g. recording an expense
/// and appending its financial event together) use transaction-aware variants
/// so the operation is atomic.
class FinanceRepository {
  FinanceRepository._();
  static final FinanceRepository instance = FinanceRepository._();

  // ── Public methods ─────────────────────────────────────────────────

  Future<int> recordExpense({
    required String uuid,
    required int categoryId,
    required Money amount,
    required String paidFrom,
    required String staffName,
    int? staffId,
    String? note,
    String? photoPath,
    int? approvedBy,
  }) async {
    return DatabaseHelper.instance.recordExpense(
      uuid: uuid,
      categoryId: categoryId,
      amount: amount,
      paidFrom: paidFrom,
      staffName: staffName,
      staffId: staffId,
      note: note,
      photoPath: photoPath,
      approvedBy: approvedBy,
    );
  }

  Future<int> recordExpensePayment({
    required String uuid,
    required int expenseId,
    required Money amount,
    required String paymentMethod,
    String? reference,
    int? shiftId,
  }) async {
    return DatabaseHelper.instance.recordExpensePayment(
      uuid: uuid,
      expenseId: expenseId,
      amount: amount,
      paymentMethod: paymentMethod,
      reference: reference,
      shiftId: shiftId,
    );
  }

  Future<void> voidExpense(int expenseId) async {
    return DatabaseHelper.instance.voidExpense(expenseId);
  }

  Future<List<Map<String, dynamic>>> getExpenses({int? shiftId}) async {
    final db = await DatabaseHelper.instance.database;
    if (shiftId != null) {
      return db.query('expenses',
          where: 'shift_id = ?', whereArgs: [shiftId],
          orderBy: 'created_at DESC');
    }
    return db.query('expenses', orderBy: 'created_at DESC');
  }
}
