// Read-only access to a shop's database file, for the screens that look at
// shops other than the open one (cross-shop activity, the portfolio).
//
// WHY THIS EXISTS
// Production shop databases are encrypted with SQLCipher, each under its own
// key in the device keystore (see `WorkspaceDatabase`). The cross-shop readers
// opened those files with plain sqflite and no password, which cannot read an
// encrypted file: every shop came back "unreadable", and the screens showed
// nothing. Debug builds and tests use plain files, which is why nothing caught
// it. Every reader now goes through here, so there is one place that knows how
// a shop file is opened.

import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher_pkg;

import '../../../db/database_helper.dart';
import '../../../models/models.dart';
import 'workspace_database.dart';

class ShopFileReader {
  const ShopFileReader._();

  /// Whether this shop's file exists on this device at all.
  static Future<bool> exists(String workspaceKey) async =>
      File(await DatabaseHelper.databasePathFor(workspaceKey)).exists();

  /// Opens [workspaceKey]'s file on its OWN read-only connection.
  ///
  /// Its own connection (`singleInstance: false`) so that closing it cannot
  /// close the app's connection to the shop that is open. The caller closes it.
  static Future<Database> openReadOnly(String workspaceKey) async {
    final String path = await DatabaseHelper.databasePathFor(workspaceKey);
    // Same switch the app's own opens use: plain files in debug and tests,
    // SQLCipher otherwise.
    if (kDebugMode) {
      return databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
    }
    final String? key = await WorkspaceDatabase.readWorkspaceKey(workspaceKey);
    return sqlcipher_pkg.databaseFactory.openDatabase(
      path,
      options: sqlcipher_pkg.SqlCipherOpenDatabaseOptions(
        readOnly: true,
        singleInstance: false,
        password: key,
      ),
    );
  }

  /// One sale, with its lines, read from [workspaceKey]'s file.
  ///
  /// How a sale from ANOTHER shop is looked at without moving the till to that
  /// shop. Null when the sale is no longer there.
  static Future<Sale?> saleById(String workspaceKey, int saleId) async {
    final Database db = await openReadOnly(workspaceKey);
    try {
      final List<Map<String, Object?>> rows = await db
          .query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (rows.isEmpty) return null;
      final Sale sale = Sale.fromMap(Map<String, dynamic>.from(rows.first));
      final List<Map<String, Object?>> items = await db.query('sale_items',
          where: 'sale_id = ?', whereArgs: [saleId], orderBy: 'id');
      return Sale(
        id: sale.id,
        staffName: sale.staffName,
        buyerName: sale.buyerName,
        buyerTin: sale.buyerTin,
        total: sale.total,
        profit: sale.profit,
        createdAt: sale.createdAt,
        paymentMethod: sale.paymentMethod,
        paymentReference: sale.paymentReference,
        amountTendered: sale.amountTendered,
        changeGiven: sale.changeGiven,
        items: items
            .map((row) => SaleItem.fromMap(Map<String, dynamic>.from(row)))
            .toList(),
      );
    } finally {
      await db.close();
    }
  }
}
