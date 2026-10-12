// The recorder's own logic: the trail, and the report it builds.
//
// The interesting part of an observability system is not the hook — it is
// whether the thing it writes can answer the question that will be asked
// later. A trail that remembers nothing, or a report that hides the route, is a
// recorder that produces text nobody can act on. Both are testable without a
// phone and without a database, so both are tested here.

import 'package:duka_pos/models/crash_log.dart';
import 'package:duka_pos/services/failure_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the trail', () {
    test('keeps the newest events, oldest dropped', () {
      final trail = BreadcrumbTrail();
      for (int i = 0; i < 25; i += 1) {
        trail.jot('event $i');
      }
      expect(trail.length, breadcrumbLimit);
      expect(trail.crumbs.first, 'event 15');
      expect(trail.crumbs.last, 'event 24');
    });

    test('gives a copy, not a handle on its own list', () {
      // The trail is written on every navigation and read on every failure; a
      // caller that could add to it would make the log a lie.
      final trail = BreadcrumbTrail();
      trail.jot('a');
      trail.jot('b');
      expect(() => trail.crumbs.add('c'), throwsUnsupportedError);
      expect(trail.crumbs, <String>['a', 'b']);
    });

    test('clears', () {
      final trail = BreadcrumbTrail();
      trail.jot('a');
      trail.clear();
      expect(trail.length, 0);
      expect(trail.crumbs, isEmpty);
    });

    test('takes the capacity it is given', () {
      final trail = BreadcrumbTrail(3);
      trail.jot('1');
      trail.jot('2');
      trail.jot('3');
      trail.jot('4');
      expect(trail.crumbs, <String>['2', '3', '4']);
    });

    test('records a nothing jab, which is still information', () {
      final trail = BreadcrumbTrail();
      trail.jot('');
      expect(trail.crumbs, <String>['']);
    });

    test('a trail with ten events is one screen of text', () {
      // The trail is read in a log line; anything longer and the line above it
      // is the only part anyone sees.
      final trail = BreadcrumbTrail();
      for (int i = 0; i < breadcrumbLimit; i += 1) {
        trail.jot('opened the sell screen and printed a receipt');
      }
      expect(trail.crumbs.join(' > ').length, lessThan(600));
    });
  });

  group('an entry', () {
    test('reads back what was written, trail and all', () {
      final entry = CrashLogEntry(
        kind: CrashKind.crash,
        message: 'Null check operator used on a null value',
        stack: '#0 main.dart:12',
        route: '/sell',
        actorName: 'Amina',
        action: 'printReceipt',
        breadcrumbs: const <String>['opened app', 'opened sell', 'printed'],
        at: '2026-10-10T09:00:00.000',
      );
      final row = entry.toMap();
      expect(row['kind'], 'crash');
      expect(row['created_at'], '2026-10-10T09:00:00.000');
      final back = CrashLogEntry.fromMap(row);
      expect(back.message, entry.message);
      expect(back.route, '/sell');
      expect(back.actorName, 'Amina');
      expect(back.action, 'printReceipt');
      expect(back.breadcrumbs, hasLength(3));
      expect(back.breadcrumbs.first, 'opened app');
    });

    test('reads a row from an older shape without the trail column', () {
      // Forward compatibility: a log written before breadcrumbs existed is
      // still a log, and an empty trail beats a crash reading it.
      final entry = CrashLogEntry.fromMap(<String, Object?>{
        'id': 7,
        'kind': 'error',
        'message': 'Sync failed',
        'stack': null,
        'route': null,
        'actor_name': null,
        'action': null,
        'breadcrumbs': null,
        'created_at': '2026-01-01T00:00:00.000',
      });
      expect(entry.id, 7);
      expect(entry.breadcrumbs, isEmpty);
      expect(entry.kind, CrashKind.error);
    });

    test('a missing created_at survives as an empty string', () {
      final entry = CrashLogEntry.fromMap(<String, Object?>{
        'kind': 'warning',
        'message': 'Queued while offline',
      });
      expect(entry.at, isEmpty);
      expect(entry.kind, CrashKind.warning);
    });

    test('the wire values are stable, single words', () {
      // The admin dashboard reads these by value, so "crash" must never become
      // "Crash" or "app_crashed".
      expect(CrashKind.values.map((kind) => kind.wire),
          <String>['crash', 'error', 'warning']);
      for (final kind in CrashKind.values) {
        // Escaped for the analyser's dollar-sign rule, not for the regex.
        expect(kind.wire, matches(RegExp(r'^[a-z]+$')));
      }
    });
  });
}
