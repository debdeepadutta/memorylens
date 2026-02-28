import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const _databaseName = "memorylens.db";
  static const _databaseVersion = 10;
  static const tableOcr = 'ocr_results';
  static const columnAssetId = 'asset_id';
  static const columnExtractedText = 'extracted_text';
  static const columnImageLabels = 'image_labels';
  static const columnUserLabels = 'user_labels';
  static const columnContext = 'context_category';
  static const columnLocationName = 'location_name';
  static const columnQrContent = 'qr_content';
  static const columnOcrBlocks = 'ocr_blocks';
  static const columnCreationDate = 'creation_date';
  static const columnPHash = 'p_hash';

  // Duplicate groups table
  static const tableDuplicates = 'duplicate_groups';
  static const columnGroupId = 'group_id';
  static const columnIsPending = 'is_pending_review';

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final getDatabasesPathString = await getDatabasesPath();
    String path = join(getDatabasesPathString, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
          CREATE TABLE $tableOcr (
            $columnAssetId TEXT PRIMARY KEY,
            $columnExtractedText TEXT NOT NULL,
            $columnImageLabels TEXT NOT NULL,
            $columnUserLabels TEXT NOT NULL DEFAULT "",
            $columnContext TEXT NOT NULL DEFAULT "Personal",
            $columnLocationName TEXT NOT NULL,
            $columnQrContent TEXT,
            $columnOcrBlocks TEXT,
            $columnCreationDate TEXT,
            $columnPHash TEXT
          )
          ''');

    await db.execute('''
          CREATE TABLE $tableDuplicates (
            $columnGroupId TEXT NOT NULL,
            $columnAssetId TEXT NOT NULL,
            $columnIsPending INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY ($columnGroupId, $columnAssetId)
          )
          ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE $tableOcr ADD COLUMN $columnImageLabels TEXT NOT NULL DEFAULT ""',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE $tableOcr ADD COLUMN $columnLocationName TEXT NOT NULL DEFAULT ""',
      );
    }
    if (oldVersion < 4) {
      await db.execute('DROP TABLE IF EXISTS $tableOcr');
      await _onCreate(db, newVersion);
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE $tableOcr ADD COLUMN $columnQrContent TEXT',
      );
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE $tableOcr ADD COLUMN $columnOcrBlocks TEXT',
      );
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE $tableOcr ADD COLUMN $columnUserLabels TEXT NOT NULL DEFAULT ""',
      );
    }
    if (oldVersion < 8) {
      await db.execute(
        'ALTER TABLE $tableOcr ADD COLUMN $columnContext TEXT NOT NULL DEFAULT "Personal"',
      );
    }
    if (oldVersion < 9) {
      await db.execute(
        'ALTER TABLE $tableOcr ADD COLUMN $columnCreationDate TEXT',
      );
    }
    if (oldVersion < 10) {
      await db.execute('ALTER TABLE $tableOcr ADD COLUMN $columnPHash TEXT');
      await db.execute('''
          CREATE TABLE $tableDuplicates (
            $columnGroupId TEXT NOT NULL,
            $columnAssetId TEXT NOT NULL,
            $columnIsPending INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY ($columnGroupId, $columnAssetId)
          )
          ''');
    }
  }

  Future<void> insertOcrResult(
    String assetId,
    String extractedText, [
    String imageLabels = "",
    String locationName = "",
    String? qrContent,
    String? ocrBlocks,
    String? creationDate,
  ]) async {
    Database db = await instance.database;
    await db.insert(tableOcr, {
      columnAssetId: assetId,
      columnExtractedText: extractedText,
      columnImageLabels: imageLabels,
      columnUserLabels: "",
      columnContext: "Personal",
      columnLocationName: locationName,
      columnQrContent: qrContent,
      columnOcrBlocks: ocrBlocks,
      columnCreationDate: creationDate,
      columnPHash: null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertOcrResultsBatch(List<Map<String, dynamic>> results) async {
    Database db = await instance.database;
    Batch batch = db.batch();

    for (var result in results) {
      batch.insert(tableOcr, {
        columnAssetId: result['assetId'],
        columnExtractedText: result['extractedText'],
        columnImageLabels: result['imageLabels'],
        columnUserLabels: result['userLabels'] ?? '',
        columnContext: result['context'] ?? 'Personal',
        columnLocationName: result['locationName'] ?? '',
        columnQrContent: result['qrContent'],
        columnOcrBlocks: result['ocrBlocks'],
        columnCreationDate: result['creationDate'],
        columnPHash: result['pHash'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<String?> getOcrResult(String assetId) async {
    Database db = await instance.database;
    List<Map<String, dynamic>> maps = await db.query(
      tableOcr,
      columns: [columnExtractedText],
      where: '$columnAssetId = ?',
      whereArgs: [assetId],
    );

    if (maps.isNotEmpty) {
      return maps.first[columnExtractedText] as String?;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getPhotoDetails(String assetId) async {
    Database db = await instance.database;
    List<Map<String, dynamic>> maps = await db.query(
      tableOcr,
      columns: [
        columnExtractedText,
        columnImageLabels,
        columnUserLabels,
        columnContext,
        columnLocationName,
        columnQrContent,
        columnOcrBlocks,
        columnCreationDate,
      ],
      where: '$columnAssetId = ?',
      whereArgs: [assetId],
    );

    if (maps.isNotEmpty) {
      return {
        'extractedText': maps.first[columnExtractedText] as String,
        'imageLabels': maps.first[columnImageLabels] as String,
        'userLabels': maps.first[columnUserLabels] as String,
        'context': maps.first[columnContext] as String,
        'locationName': maps.first[columnLocationName] as String,
        'qrContent': maps.first[columnQrContent] as String?,
        'ocrBlocks': maps.first[columnOcrBlocks] as String?,
        'creationDate': maps.first[columnCreationDate] as String?,
      };
    }
    return null;
  }

  Future<Set<String>> getIndexedAssetIds() async {
    Database db = await instance.database;
    List<Map<String, dynamic>> maps = await db.query(
      tableOcr,
      columns: [columnAssetId],
    );

    return maps.map((map) => map[columnAssetId] as String).toSet();
  }

  Future<List<String>> searchPhotos(String query) async {
    Database db = await instance.database;
    List<Map<String, dynamic>> maps = await db.query(
      tableOcr,
      columns: [columnAssetId],
      where:
          '$columnExtractedText LIKE ? OR $columnImageLabels LIKE ? OR $columnUserLabels LIKE ? OR $columnLocationName LIKE ? OR $columnCreationDate LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%', '%$query%', '%$query%'],
    );

    return maps.map((map) => map[columnAssetId] as String).toList();
  }

  Future<List<Map<String, dynamic>>> getAllPhotosMetadata() async {
    Database db = await instance.database;
    return await db.query(
      tableOcr,
      columns: [
        columnAssetId,
        columnExtractedText,
        columnImageLabels,
        columnLocationName,
        columnCreationDate,
        columnContext,
        columnPHash,
      ],
    );
  }

  Future<void> updatePHash(String assetId, String pHash) async {
    Database db = await instance.database;
    await db.update(
      tableOcr,
      {columnPHash: pHash},
      where: '$columnAssetId = ?',
      whereArgs: [assetId],
    );
  }

  Future<void> saveDuplicateGroups(
    List<Map<String, dynamic>> groups, {
    bool clearExisting = true,
  }) async {
    Database db = await instance.database;
    await db.transaction((txn) async {
      if (clearExisting) {
        await txn.delete(tableDuplicates);
      }
      for (var group in groups) {
        final groupId = group['groupId'];
        final assetIds = group['assetIds'] as List<String>;
        for (var assetId in assetIds) {
          await txn.insert(tableDuplicates, {
            columnGroupId: groupId,
            columnAssetId: assetId,
            columnIsPending: 1,
          });
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> getDuplicateGroups() async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> rows = await db.query(tableDuplicates);

    Map<String, List<String>> groups = {};
    for (var row in rows) {
      final gid = row[columnGroupId] as String;
      final aid = row[columnAssetId] as String;
      groups.putIfAbsent(gid, () => []).add(aid);
    }

    return groups.entries
        .map((e) => {'groupId': e.key, 'assetIds': e.value})
        .toList();
  }

  Future<void> deleteAssetMetadata(String assetId) async {
    Database db = await instance.database;
    await db.delete(
      tableOcr,
      where: '$columnAssetId = ?',
      whereArgs: [assetId],
    );
    await db.delete(
      tableDuplicates,
      where: '$columnAssetId = ?',
      whereArgs: [assetId],
    );
  }

  Future<void> updateUserLabels(String assetId, String labels) async {
    Database db = await instance.database;
    await db.update(
      tableOcr,
      {columnUserLabels: labels},
      where: '$columnAssetId = ?',
      whereArgs: [assetId],
    );
  }

  Future<List<String>> getDistinctContexts() async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT DISTINCT $columnContext FROM $tableOcr WHERE $columnContext != "Personal"',
    );
    return maps.map((m) => m[columnContext] as String).toList();
  }

  Future<int> getTotalPhotosCount() async {
    Database db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM $tableOcr');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getDatabaseSize() async {
    final dbPath = await getDatabasesPath();
    final path = "$dbPath/$_databaseName";
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  Future<void> clearAllData() async {
    Database db = await instance.database;
    await db.delete(tableOcr);
    await db.delete(tableDuplicates);
  }
}
