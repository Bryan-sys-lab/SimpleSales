import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';
import '../../../models/models.dart';
import '../../../models/stock_movement.dart';

/// Repository for products and inventory.
///
/// Manages persistence of products, variants, packs, barcodes, and stock
/// movements. Operations that touch multiple tables (e.g. recording a stock
/// movement and updating the product balance together) use transaction-aware
/// variants so the operation is atomic.
class InventoryRepository {
  InventoryRepository._();
  static final InventoryRepository instance = InventoryRepository._();

  // ── Transaction-aware variants ─────────────────────────────────────

  /// Writes a stock movement within an existing transaction.
  Future<void> writeStockMovementInTransaction(
    Transaction txn, {
    required int productId,
    required int? variantId,
    required int movementType,
    required int delta,
    required String? balanceAfter,
    required String reason,
    required String staffName,
    required int? staffId,
    required String createdAt,
  }) async {
    await txn.insert('stock_movements', {
      'product_id': productId,
      'variant_id': variantId,
      'movement_type': movementType,
      'delta': delta,
      'balance_after': balanceAfter,
      'reason': reason,
      'staff_name': staffName,
      'staff_id': staffId,
      'created_at': createdAt,
    });
  }

  // ── Product queries ────────────────────────────────────────────────

  Future<List<Product>> getProducts({bool activeOnly = true}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('products',
        where: activeOnly ? 'active = 1' : null, orderBy: 'name');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  Future<Product?> getProductById(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('products',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<Product?> getProductByRemoteId(String remoteId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('products',
        where: 'remote_id = ?', whereArgs: [remoteId], limit: 1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<double?> openingStockQtyForProduct(int productId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'stock_movements',
      columns: ['balance_after'],
      where:
          'product_id = ? AND variant_id IS NULL AND movement_type = ?',
      whereArgs: [productId, StockMovementType.opening.wire],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['balance_after'] as num?)?.toDouble();
  }

  Future<Map<int, double?>> openingStockQtyForProducts(
      List<int> productIds) async {
    if (productIds.isEmpty) return <int, double?>{};
    final db = await DatabaseHelper.instance.database;
    final placeholders = List.filled(productIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''SELECT product_id, balance_after
         FROM stock_movements
         WHERE product_id IN ($placeholders)
           AND variant_id IS NULL
           AND movement_type = ?
         ORDER BY id ASC''',
      [...productIds, StockMovementType.opening.wire],
    );
    final result = <int, double?>{};
    for (final id in productIds) {
      result[id] = null;
    }
    for (final row in rows) {
      final id = row['product_id'] as int;
      if (!result.containsKey(id)) continue;
      result[id] = (row['balance_after'] as num?)?.toDouble();
    }
    return result;
  }

  Future<void> deactivateProduct(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('products', {'active': 0},
        where: 'id = ?', whereArgs: [id]);
  }
}
