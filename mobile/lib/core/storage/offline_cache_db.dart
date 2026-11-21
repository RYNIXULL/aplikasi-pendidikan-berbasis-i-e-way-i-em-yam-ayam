import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class CachedMaterialRecord {
  const CachedMaterialRecord({
    required this.materialId,
    required this.classroomId,
    required this.title,
    required this.contentType,
    required this.payloadJson,
    required this.cachedAt,
  });

  final String materialId;
  final String classroomId;
  final String title;
  final String contentType;
  final Map<String, dynamic> payloadJson;
  final DateTime cachedAt;
}

class OfflineCacheDatabase {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'edu_ai_offline_cache.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cached_materials (
            material_id TEXT PRIMARY KEY,
            classroom_id TEXT NOT NULL,
            title TEXT NOT NULL,
            content_type TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            cached_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_progress_sync (
            material_id TEXT PRIMARY KEY,
            completion_percentage INTEGER NOT NULL,
            time_spent_delta INTEGER NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> upsertMaterial(CachedMaterialRecord record) async {
    final db = await _open();
    await db.insert(
      'cached_materials',
      {
        'material_id': record.materialId,
        'classroom_id': record.classroomId,
        'title': record.title,
        'content_type': record.contentType,
        'payload_json': jsonEncode(record.payloadJson),
        'cached_at': record.cachedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CachedMaterialRecord?> getMaterial(String materialId) async {
    final db = await _open();
    final rows = await db.query(
      'cached_materials',
      where: 'material_id = ?',
      whereArgs: [materialId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CachedMaterialRecord(
      materialId: row['material_id'] as String,
      classroomId: row['classroom_id'] as String,
      title: row['title'] as String,
      contentType: row['content_type'] as String,
      payloadJson: jsonDecode(row['payload_json'] as String) as Map<String, dynamic>,
      cachedAt: DateTime.parse(row['cached_at'] as String),
    );
  }

  Future<void> enqueueProgressSync({
    required String materialId,
    required int completionPercentage,
    required int timeSpentDelta,
  }) async {
    final db = await _open();
    await db.insert(
      'pending_progress_sync',
      {
        'material_id': materialId,
        'completion_percentage': completionPercentage,
        'time_spent_delta': timeSpentDelta,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> getPendingProgress() async {
    final db = await _open();
    return db.query('pending_progress_sync');
  }

  Future<void> clearPendingProgress(String materialId) async {
    final db = await _open();
    await db.delete('pending_progress_sync', where: 'material_id = ?', whereArgs: [materialId]);
  }
}
