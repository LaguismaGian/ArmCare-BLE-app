import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class Recording {
  final int? id;
  final String label;
  final String mode;
  final int durationMs;
  final int sampleCount;
  final String timestamp;

  Recording({
    this.id,
    required this.label,
    required this.mode,
    required this.durationMs,
    required this.sampleCount,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'mode': mode,
      'durationMs': durationMs,
      'sampleCount': sampleCount,
      'timestamp': timestamp,
    };
  }

  factory Recording.fromMap(Map<String, dynamic> map) {
    return Recording(
      id: map['id'],
      label: map['label'],
      mode: map['mode'],
      durationMs: map['durationMs'],
      sampleCount: map['sampleCount'],
      timestamp: map['timestamp'],
    );
  }
}

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'armcare.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recordings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT,
            mode TEXT,
            durationMs INTEGER,
            sampleCount INTEGER,
            timestamp TEXT
          )
        ''');
      },
    );
  }

  Future<int> insertRecording(Recording recording) async {
    final db = await database;
    return await db.insert('recordings', recording.toMap());
  }

  Future<List<Recording>> getAllRecordings() async {
    final db = await database;
    final maps = await db.query('recordings', orderBy: 'id DESC');
    return maps.map((m) => Recording.fromMap(m)).toList();
  }

  Future<void> deleteRecording(int id) async {
    final db = await database;
    await db.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAllRecordings() async {
    final db = await database;
    await db.delete('recordings');
  }
}