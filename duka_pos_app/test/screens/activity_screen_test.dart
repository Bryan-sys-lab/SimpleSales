// The owner's activity view: every shop's changes, in one screen.
//
// What this suite pins is the presentation of the cross-shop reader —
// specifically the four states and the two views, rendered from a constructed
// value so no database has to be seeded to check the layout.
//
// The states matter because they answer three different questions and an owner
// who cannot tell them apart learns nothing:
//
//   * EMPTY — no shop has anything recorded. That is a new device, not a fault.
//   * UNAVAILABLE — the read itself failed. Something IS wrong and retrying
//     might fix it.
//   * BY-SHOP with an unreadable shop — the shop is fine but its log could not
//     be read on this phone. Reporting that as "nothing happened in this shop"
//     is the lie this suite exists to prevent.
//
// `loadAppFonts` is not optional: under Ahem every glyph is a fixed em-square,
// so the 2.0x half of the matrix would pass vacuously.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/audit_log.dart';
import 'package:duka_pos/screens/activity_screen.dart';
import 'package:duka_pos/services/cross_shop_audit_reader.dart';
import 'package:duka_pos/ui/components/states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

AuditLogEntry _entry(
  AuditAction action, {
  String detail = '',
  String actor = 'Amina',
  String createdAt = '2026-01-01T10:00:00.000Z',
}) =>
    AuditLogEntry(
      action: action,
      entity: AuditEntity.settings,
      actorName: actor,
      detail: detail.isEmpty ? null : detail,
      createdAt: createdAt,
    );

ShopActivity _shop(
  String name, {
  List<AuditLogEntry> entries = const <AuditLogEntry>[],
  bool failed = false,
}) =>
    ShopActivity(
      shopName: name,
      workspaceKey: name.replaceAll(' ', '_'),
      entries: entries,
      failed: failed,
    );

ActivitySnapshot _snapshot(List<ShopActivity> perShop) =>
    ActivitySnapshot(perShop: perShop);

Widget _panel(
  ActivitySnapshot snapshot, {
  ActivityView view = ActivityView.merged,
}) =>
    Scaffold(
      body: ActivityPanel(
        snapshot: snapshot,
        view: view,
        onViewChanged: (ActivityView _) {},
        onRetry: () async {},
      ),
    );

/// Two shops, one row each, so both the merged and the grouped view have
/// something to render.
ActivitySnapshot get _twoShops => _snapshot(<ShopActivity>[
      _shop('Amina Duka', entries: <AuditLogEntry>[
        _entry(AuditAction.backupErased,
            detail: 'from shop A', createdAt: '2026-01-01T09:00:00.000Z'),
      ]),
      _shop('Njeri Shop', entries: <AuditLogEntry>[
        _entry(AuditAction.taxSettingsChanged,
            detail: 'VAT 16%', createdAt: '2026-01-01T11:00:00.000Z'),
      ]),
    ]);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  group('the four states', () {
    testWidgets('an empty device says nothing has happened yet',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(const ActivitySnapshot(perShop: <ShopActivity>[])),
      );

      expect(find.text(l10n.activityEmptyTitle), findsOneWidget);
      expect(find.text(l10n.activityEmptyMessage), findsOneWidget);
      tester.expectNoOverflow('activity empty');
    });

    testWidgets('a failed read offers a retry, not a shrug', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: Scaffold(
          body: ErrorStateView(
            message: l10n.activityLoadFailed,
            onRetry: () {},
          ),
        ),
      );

      // The state must be distinguishable from "nothing happened": a dead end
      // is how a transient failure becomes an uninstall.
      expect(find.text(l10n.activityLoadFailed), findsOneWidget);
      tester.expectNoOverflow('activity failed');
    });

    testWidgets('an unreadable shop is marked, not silently empty',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(
          _snapshot(<ShopActivity>[
            _shop('Amina Duka', entries: <AuditLogEntry>[
              _entry(AuditAction.backupErased, detail: 'local backups'),
            ]),
            _shop('Njeri Shop', failed: true),
          ]),
          view: ActivityView.byShop,
        ),
      );

      // The failing shop is NAMED as failing. Reporting it as "nothing yet in
      // this shop" would tell the owner the shop is clean when it is merely
      // unreadable.
      expect(find.text(l10n.activityShopUnreadable), findsOneWidget);
      expect(find.text(l10n.activityShopUnreadableDetail), findsOneWidget);
      tester.expectNoOverflow('activity unreadable shop');
    });

    testWidgets('a shop with no rows says so distinctly', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(
          _snapshot(<ShopActivity>[
            _shop('Amina Duka'),
            _shop('Njeri Shop', entries: <AuditLogEntry>[
              _entry(AuditAction.staffAdded, detail: 'Joseph'),
            ]),
          ]),
          view: ActivityView.byShop,
        ),
      );

      expect(find.text(l10n.activityShopEmpty), findsOneWidget);
      expect(find.text(l10n.activityShopUnreadable), findsNothing);
    });
  });

  group('the two views', () {
    testWidgets('the merged view carries the shop on every row',
        (tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(home: _panel(_twoShops, view: ActivityView.merged));

      // The shop is a COLUMN on the row's second line, not a heading above it:
      // in a merged feed each row has to say where it came from, or an owner
      // reading "backup erased" cannot tell which shop it happened in.
      expect(find.textContaining('Amina Duka'), findsOneWidget);
      expect(find.textContaining('Njeri Shop'), findsOneWidget);
      tester.expectNoOverflow('activity merged');
    });

    testWidgets('the by-shop view groups rows under their shop',
        (tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(home: _panel(_twoShops, view: ActivityView.byShop));

      // A shop's name is its NAME, in its own case — not an upper-cased eyebrow.
      // SectionHeader upper-cases its label, so this screen renders its own.
      expect(find.text('Amina Duka'), findsOneWidget);
      expect(find.text('Njeri Shop'), findsOneWidget);
      // The merged view's per-row shop column is not repeated here.
      expect(find.textContaining('Amina Duka · Amina'), findsNothing);
      tester.expectNoOverflow('activity by shop');
    });

    testWidgets('the view switch only appears with more than one shop',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(
          _snapshot(<ShopActivity>[
            _shop('Amina Duka', entries: <AuditLogEntry>[
              _entry(AuditAction.backupErased, detail: 'x'),
            ]),
          ]),
        ),
      );

      // A single-shop owner has nothing to switch between, and an affordance
      // that answers a question they never asked is noise on a screen they use.
      expect(find.text(l10n.activityViewMerged), findsNothing);
      expect(find.text(l10n.activityViewByShop), findsNothing);
    });
  });

  group('the row itself', () {
    testWidgets('a row carries the action, the detail, the actor and the time',
        (tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: _panel(
          _snapshot(<ShopActivity>[
            _shop('Amina Duka', entries: <AuditLogEntry>[
              _entry(AuditAction.backupErased,
                  detail: 'local encrypted backups', actor: 'Amina'),
            ]),
          ]),
        ),
      );

      // The sentence, the appended detail, and the actor line.
      expect(find.textContaining(l10n.activityBackupErased), findsOneWidget);
      expect(find.textContaining('local encrypted backups'), findsOneWidget);
      expect(find.textContaining('Amina'), findsOneWidget);
      tester.expectNoOverflow('activity row');
    });

    testWidgets('a long detail wraps rather than truncating', (tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: _panel(
          _snapshot(<ShopActivity>[
            _shop('Amina Duka', entries: <AuditLogEntry>[
              _entry(AuditAction.stockAdjusted,
                  detail: 'Kes 200 Item, +24 units, '
                      'restocked after the wholesaler delivery',
                  actor: 'Amina'),
            ]),
          ]),
        ),
      );

      // No ellipsis and no clamp: the full sentence has to be readable, and a
      // cut-off reason is a reason nobody can act on.
      expect(find.textContaining('restocked after the wholesaler delivery'),
          findsOneWidget);
      tester.expectNoOverflow('activity long detail');
    });

    testWidgets('the summary counts every shop and every row', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(
          _snapshot(<ShopActivity>[
            _shop('Amina Duka', entries: <AuditLogEntry>[
              _entry(AuditAction.backupErased, detail: 'x'),
              _entry(AuditAction.taxSettingsChanged, detail: 'VAT 16%'),
            ]),
            _shop('Njeri Shop', entries: <AuditLogEntry>[
              _entry(AuditAction.staffAdded, detail: 'Joseph'),
            ]),
          ]),
        ),
      );

      // "{shops} shops, {entries} changes": two shops, three entries. The
      // generated parameters are ordered alphabetically — `entries` first,
      // `shops` second — so this is a THREE-then-TWO call.
      //
      // These were transposed, which printed "2 shops, 3 changes" for a device
      // holding three changes across two shops.
      expect(find.text(l10n.activitySummary(3, 2)), findsOneWidget);
    });
  });

  group('the device x scale x brightness matrix', () {
    for (final Device device in <Device>[Device.compact, Device.small]) {
      for (final double scale in <double>[1.0, 2.0]) {
        for (final Brightness brightness in <Brightness>[
          Brightness.light,
          Brightness.dark,
        ]) {
          final String where = '${device.name} x$scale $brightness';
          testWidgets('fits $where', (tester) async {
            tester.useDevice(device);
            await tester.pumpApp(
              home: _panel(_twoShops),
              textScaler: TextScaler.linear(scale),
              brightness: brightness,
            );
            tester.expectNoOverflow('activity $where');
          });
        }
      }
    }
  });
}
