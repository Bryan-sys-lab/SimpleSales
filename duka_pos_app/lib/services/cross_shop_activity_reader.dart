import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../models/audit_log.dart';
import '../profile/shop_profile.dart';
import '../utils/money.dart';
import 'cross_shop_activity.dart';
import 'workspace_service.dart';

/// Filters shared by the local and remote activity readers.
class CrossShopActivityFilters {
  const CrossShopActivityFilters({
    required this.from,
    required this.to,
    this.workspaceKey,
    this.profile,
    this.paymentMethod,
    this.type,
    this.status,
    this.cursor,
  });

  final DateTime from;
  final DateTime to;
  final String? workspaceKey;
  final ShopProfile? profile;
  final String? paymentMethod;
  final String? type;
  final String? status;
  final String? cursor;
}

/// Reads each local shop through an independent read-only connection.
class CrossShopActivityReader {
  const CrossShopActivityReader._();

  static Future<CrossShopActivityPage> readLocal(
    CrossShopActivityFilters filters, {
    int limitPerShop = 200,
  }) async {
    final events = await DatabaseHelper.instance.withWorkspaceGate(
      () => _readLocalHoldingGate(filters, limitPerShop),
    );
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final cursor = _parseCursor(filters.cursor);
    final page = events
        .where((event) => _afterCursor(event, cursor))
        .take(limitPerShop)
        .toList();
    return CrossShopActivityPage(
      events: page,
      nextCursor: page.length == limitPerShop && page.isNotEmpty
          ? CrossShopActivityPage.cursorFor(page.last)
          : null,
    );
  }

  static Future<List<CrossShopActivity>> _readLocalHoldingGate(
    CrossShopActivityFilters filters,
    int limitPerShop,
  ) async {
    final shops = await WorkspaceServiceShops.localShops();
    final events = <CrossShopActivity>[];
    for (final shop in shops) {
      if (filters.workspaceKey != null &&
          filters.workspaceKey != shop.workspaceKey) {
        continue;
      }
      Database? db;
      try {
        final path = await DatabaseHelper.databasePathFor(shop.workspaceKey);
        if (!await File(path).exists()) {
          continue;
        }
        db = await openDatabase(path, readOnly: true, singleInstance: false);
        var profile = ShopProfile.duka;
        try {
          final rows =
              await db.query('shop_profile', columns: ['profile'], limit: 1);
          if (rows.isNotEmpty) {
            profile = ShopProfile.fromWire(rows.first['profile'] as String?);
          }
        } catch (_) {}
        if (filters.profile != null && filters.profile != profile) {
          continue;
        }

        final sales = filters.type != null && filters.type != 'sale'
            ? const <Map<String, Object?>>[]
            : await db.query(
                'sales',
                where:
                    'created_at >= ? AND created_at < ?${filters.paymentMethod == null ? '' : ' AND payment_method = ?'}',
                whereArgs: <Object?>[
                  filters.from.toIso8601String(),
                  filters.to.toIso8601String(),
                  if (filters.paymentMethod != null) filters.paymentMethod,
                ],
                orderBy: 'created_at DESC, id DESC',
                limit: limitPerShop + 1,
              );
        for (final row in sales) {
          final event = CrossShopActivity(
            eventId: 'local-sale:${shop.workspaceKey}:${row['id']}',
            sourceId: '${row['id']}',
            sourceType: 'sale',
            tenantId: shop.tenantId ?? shop.workspaceKey,
            shopName: shop.shopName,
            businessProfile: profile,
            createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            type: 'sale',
            status: (row['payment_verified'] as num?)?.toInt() == 0
                ? 'unverified'
                : 'completed',
            amount: Money.fromMinor((row['total'] as num?)?.toInt() ?? 0),
            profit: Money.fromMinor((row['profit'] as num?)?.toInt() ?? 0),
            paymentMethod: row['payment_method'] as String? ?? 'cash',
            actor: row['staff_name'] as String?,
            workspaceKey: shop.workspaceKey,
          );
          if (_matches(event, filters)) events.add(event);
        }

        if (filters.type == null || filters.type == 'activity') {
          final rows = await db.query(
            'audit_log',
            where: 'created_at >= ? AND created_at < ?',
            whereArgs: [
              filters.from.toIso8601String(),
              filters.to.toIso8601String()
            ],
            orderBy: 'created_at DESC, id DESC',
            limit: limitPerShop + 1,
          );
          for (final row in rows) {
            final entry = AuditLogEntry.fromMap(Map<String, dynamic>.from(row));
            final event = CrossShopActivity(
              eventId: 'local-activity:${shop.workspaceKey}:${entry.id}',
              sourceId: entry.entityId ?? '${entry.id ?? ''}',
              sourceType: entry.entity.wire,
              tenantId: shop.tenantId ?? shop.workspaceKey,
              shopName: shop.shopName,
              businessProfile: profile,
              createdAt: DateTime.tryParse(entry.createdAt) ??
                  DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
              type: 'activity',
              status: 'recorded',
              amount: Money.zero,
              actor: entry.actorName,
              detail:
                  '${entry.action.wire}${entry.detail == null ? '' : ' — ${entry.detail}'}',
              workspaceKey: shop.workspaceKey,
            );
            if (_matches(event, filters)) events.add(event);
          }
        }
      } catch (_) {
        // An unreadable local file is not permission to fabricate an empty feed.
      } finally {
        await db?.close();
      }
    }
    return events;
  }

  static bool _matches(
      CrossShopActivity event, CrossShopActivityFilters filters) {
    if (filters.status != null && event.status != filters.status) {
      return false;
    }
    if (filters.paymentMethod != null &&
        event.paymentMethod != filters.paymentMethod) {
      return false;
    }
    return true;
  }

  static ({DateTime at, String id})? _parseCursor(String? cursor) {
    if (cursor == null) return null;
    final separator = cursor.indexOf('|');
    if (separator < 1 || separator == cursor.length - 1) return null;
    final at = DateTime.tryParse(cursor.substring(0, separator));
    if (at == null) return null;
    return (at: at, id: cursor.substring(separator + 1));
  }

  static bool _afterCursor(
    CrossShopActivity event,
    ({DateTime at, String id})? cursor,
  ) {
    if (cursor == null) return true;
    final eventAt = event.createdAt;
    if (eventAt.isBefore(cursor.at)) return true;
    if (eventAt.isAfter(cursor.at)) return false;
    return event.eventId.compareTo(cursor.id) < 0;
  }
}
