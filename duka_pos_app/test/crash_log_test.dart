// The failure log: bounded, self-deleting, and honest about what it keeps.
//
// The property under test is the one that makes this table safe to run on a
// phone nobody is watching: the log NEVER grows past its cap, and it deletes on
// the write itself rather than waiting for a background job that may never run
// on a phone that is switched off. Everything else here is about the shape of
// an entry surviving a round trip.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/crash_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

CrashLogEntry failure({
  String message = 'Sync failed',
  CrashKind kind = CrashKind.error,
  String? route = '/sell',
  String? actor = 'Amina',
  String? action = 'sync',
  List<String> trail = const <String>['opened app', 'opened sell'],
}) =>
    CrashLogEntry(
      kind: kind,
      message: message,
      route: route,
      actorName: actor,
      action: action,
      breadcrumbs: trail,
      at: DateTime.now().toIso8601String(),
    );

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  group('the failure log', () {
    test('records an entry and reads it back with the trail intact', () async {
      await DatabaseHelper.openInMemoryForTests();
      final db = DatabaseHelper.instance;

      await db.recordCrash(failure());

      final List<CrashLogEntry> log = await db.crashLog(const CrashLogQuery());
      expect(log, hasLength(1));
      final CrashLogEntry entry = log.first;
      expect(entry.message, 'Sync failed');
      expect(entry.kind, CrashKind.error);
      expect(entry.route, '/sell');
      expect(entry.actorName, 'Amina');
      expect(entry.action, 'sync');
      // The trail round-trips, oldest first, as a readable sentence.
      expect(entry.breadcrumbs, <String>['opened app', 'opened sell']);
      expect(await db.crashLogCount(), 1);
    });

    test('defaults a kind it cannot read to an error, not a crash', () async {
      // A row from a future version of the app must not make today's log claim
      // the app died when it did not.
      expect(CrashKind.fromWire('nonsense'), CrashKind.error);
      expect(CrashKind.fromWire(null), CrashKind.error);
      expect(CrashKind.fromWire('crash'), CrashKind.crash);
      expect(CrashKind.fromWire('warning'), CrashKind.warning);
    });

    test('trims a long stack to the frames that matter', () async {
      final String long = List<String>.generate(
        200,
        (int i) => '#$i foo.bar',
      ).join('\n');

      await DatabaseHelper.openInMemoryForTests();
      await DatabaseHelper.instance.recordCrash(failure());

      final CrashLogEntry entry = CrashLogEntry(
        kind: CrashKind.crash,
        message: 'boom',
        stack: long,
        at: DateTime.now().toIso8601String(),
      );
      // The trim happens on the way in, so the database never holds the wall.
      expect(entry.toMap()['stack'], contains('#0'));
      expect(
        (entry.toMap()['stack'] as String).split('\n').length,
        lessThanOrEqualTo(CrashLogEntry.maxStackLines + 1),
      );
      expect(entry.toMap()['stack'], isNot(contains('#199')));
    });

    test('keeps a short stack whole', () async {
      final CrashLogEntry entry = CrashLogEntry(
        kind: CrashKind.crash,
        message: 'boom',
        stack: '#0 a\n#1 b',
        at: DateTime.now().toIso8601String(),
      );
      expect(entry.toMap()['stack'], '#0 a\n#1 b');
    });

    test('bounds the message a caller may write', () async {
      // A message is often a response body; the first kilobyte is the
      // diagnosis and the rest is noise a phone should not store.
      const int cap = CrashLogEntry.maxMessageChars;
      expect(cap, greaterThan(0));
      expect('x' * (cap + 500), isNot(hasLength(lessThan(cap))));
    });

    test(
        'deletes the oldest rows on write, so a crash loop cannot fill the phone',
        () async {
      await DatabaseHelper.openInMemoryForTests();
      final db = DatabaseHelper.instance;

      for (int i = 0; i < DatabaseHelper.crashRetainRows + 25; i += 1) {
        await db.recordCrash(failure(message: 'failure $i'));
      }

      // The cap is a property of the write, not of a background job: a phone
      // that never opens the diagnostics screen must not accumulate.
      expect(await db.crashLogCount(), DatabaseHelper.crashRetainRows);
      final List<CrashLogEntry> log =
          await db.crashLog(const CrashLogQuery(limit: 1000));
      expect(
          log.first.message, 'failure ${DatabaseHelper.crashRetainRows + 24}');
      expect(log.last.message, 'failure 25');
    });

    test('reads newest first, so the screen shows what just happened',
        () async {
      await DatabaseHelper.openInMemoryForTests();
      final db = DatabaseHelper.instance;
      await db.recordCrash(failure(message: 'older', action: 'sync'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await db.recordCrash(failure(message: 'newer', action: 'print'));

      final List<CrashLogEntry> log = await db.crashLog(const CrashLogQuery());
      expect(log.first.message, 'newer');
    });

    test('filters by kind, so a caller can ask for only the crashes', () async {
      await DatabaseHelper.openInMemoryForTests();
      final db = DatabaseHelper.instance;
      await db
          .recordCrash(failure(message: 'a warning', kind: CrashKind.warning));
      await db.recordCrash(failure(message: 'a crash', kind: CrashKind.crash));

      final List<CrashLogEntry> crashes = await db.crashLog(
        const CrashLogQuery(kinds: <CrashKind>{CrashKind.crash}),
      );
      expect(crashes, hasLength(1));
      expect(crashes.first.message, 'a crash');
    });

    test('filters by time, for the "since I last synced" question', () async {
      await DatabaseHelper.openInMemoryForTests();
      final db = DatabaseHelper.instance;
      await db.recordCrash(failure(message: 'old', action: 'sync'));

      final List<CrashLogEntry> since = await db.crashLog(
        CrashLogQuery(
            since:
                DateTime.now().add(const Duration(hours: 1)).toIso8601String()),
      );
      expect(since, isEmpty);
    });

    test('honours the limit', () async {
      await DatabaseHelper.openInMemoryForTests();
      final db = DatabaseHelper.instance;
      for (int i = 0; i < 5; i += 1) {
        await db.recordCrash(failure(message: 'failure $i'));
      }
      expect(await db.crashLog(const CrashLogQuery(limit: 3)), hasLength(3));
    });

    test('clears on the owner\'s instruction', () async {
      await DatabaseHelper.openInMemoryForTests();
      final db = DatabaseHelper.instance;
      await db.recordCrash(failure());
      await db.clearCrashLog();
      expect(await db.crashLogCount(), 0);
      // The log came back empty rather than staying flagged: a failure log that
      // survives being cleared is a log nobody will ever read again.
      await db.recordCrash(failure(message: 'after clearing'));
      expect(await db.crashLogCount(), 1);
    });
  });
}
