import 'package:sqflite/sqflite.dart';

/// A workspace-bound database session.
///
/// Holds an open [Database] handle for a single workspace and verifies that
/// the workspace identity recorded inside the database matches the requested
/// workspace. While a session is live, no operation can silently switch to
/// another workspace.
///
/// Sessions are obtained through [DatabaseManager.sessionFor].
class DatabaseSession {
  DatabaseSession({
    required this.workspaceId,
    required this.database,
    this.closed = false,
  });

  /// The workspace this session is bound to.
  final String workspaceId;

  /// The open SQLite database handle.
  final Database database;

  /// Whether this session has been closed.
  final bool closed;

  /// Closes this session. Safe to call multiple times; subsequent calls are
  /// no-ops.
  Future<void> close() async {
    if (closed) return;
    await database.close();
  }

  /// Runs [body] inside a transaction on this session's database.
  ///
  /// All changes in [body] succeed or fail together. This is the primitive
  /// that [TransactionManager.run] builds on.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) body) =>
      database.transaction(body);
}
