import 'package:sqflite/sqflite.dart';

/// Local, tenant-scoped metadata for sale-evidence photos.
///
/// The photo is staged locally only while offline; the durable binary belongs
/// in R2. Keeping this row in the workspace database makes it part of normal
/// encrypted backup/import and gives the sync layer an idempotent retry record.
class SaleEvidenceRepository {
  SaleEvidenceRepository._();

  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sale_evidence (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL,
      local_path TEXT,
      remote_key TEXT,
      remote_url TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL,
      uploaded_at TEXT
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_evidence_sale ON sale_evidence (sale_id, id)');
  }
}
