library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A [SharedPreferences]-backed store for a list of JSON values under one key.
///
/// Each [T] is encoded with [toMap] + [jsonEncode] and stored as one entry in
/// the string list under [key]. Entries are decoded independently, so a single
/// corrupt row is skipped on [load] instead of poisoning the whole list: the
/// serialization/corruption policy lives here, in one place.
class JsonPrefsStore<T> {
  /// Creates a store backed by [prefs], keyed under [key].
  ///
  /// [fromMap] decodes one entry; [toMap] encodes one entry.
  JsonPrefsStore({
    required Future<SharedPreferences> prefs,
    required this.key,
    required T Function(Map<String, dynamic>) fromMap,
    required Map<String, Object?> Function(T) toMap,
  })  : _prefsFuture = prefs,
        _fromMap = fromMap,
        _toMap = toMap;

  final Future<SharedPreferences> _prefsFuture;
  final String key;
  final T Function(Map<String, dynamic>) _fromMap;
  final Map<String, Object?> Function(T) _toMap;

  /// Loads every entry under [key], decoding each with [fromMap].
  ///
  /// Entries that fail to decode (bad JSON, wrong shape, or [fromMap] throwing)
  /// are silently skipped. Never throws.
  Future<List<T>> load() async {
    final prefs = await _prefsFuture;
    final result = <T>[];
    for (final raw in prefs.getStringList(key) ?? <String>[]) {
      try {
        result.add(_fromMap(jsonDecode(raw) as Map<String, dynamic>));
      } on Object {
        // A corrupt entry is skipped, not fatal.
      }
    }
    return result;
  }

  /// Encodes every item with [toMap] + [jsonEncode] and writes the list under
  /// [key], replacing whatever was there before.
  Future<void> save(List<T> items) async {
    final prefs = await _prefsFuture;
    await prefs.setStringList(
      key,
      items.map((item) => jsonEncode(_toMap(item))).toList(),
    );
  }
}
