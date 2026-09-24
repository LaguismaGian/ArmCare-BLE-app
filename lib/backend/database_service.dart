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

class SampleRow {
  final int? id;
  final int recordingId;
  final int timestampMs;
  final double ax, ay, az;
  final double gx, gy, gz;

  SampleRow({
    this.id,
    required this.recordingId,
    required this.timestampMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recordingId': recordingId,
      'timestampMs': timestampMs,
      'ax': ax,
      'ay': ay,
      'az': az,
      'gx': gx,
      'gy': gy,
      'gz': gz,
    };
  }

  factory SampleRow.fromMap(Map<String, dynamic> map) {
    return SampleRow(
      id: map['id'],
      recordingId: map['recordingId'],
      timestampMs: map['timestampMs'],
      ax: map['ax'],
      ay: map['ay'],
      az: map['az'],
      gx: map['gx'],
      gy: map['gy'],
      gz: map['gz'],
    );
  }
}

class Threshold {
  final double accelThreshold;
  final double gyroThreshold;
  final String timestamp;

  Threshold({
    required this.accelThreshold,
    required this.gyroThreshold,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'accelThreshold': accelThreshold,
      'gyroThreshold': gyroThreshold,
      'timestamp': timestamp,
    };
  }

  factory Threshold.fromMap(Map<String, dynamic> map) {
    return Threshold(
      accelThreshold: map['accelThreshold'],
      gyroThreshold: map['gyroThreshold'],
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
      version: 3,
      onCreate: (db, version) async {
        await _createRecordingsTable(db);
        await _createSamplesTable(db);
        await _createThresholdsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 → v2: added samples + thresholds
        // v2 → v3: safety re-check (idempotent)
        await _createSamplesTable(db);
        await _createThresholdsTable(db);
      },
    );
  }

  Future<void> _createRecordingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recordings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT,
        mode TEXT,
        durationMs INTEGER,
        sampleCount INTEGER,
        timestamp TEXT
      )
    ''');
  }

  Future<void> _createSamplesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recordingId INTEGER,
        timestampMs INTEGER,
        ax REAL, ay REAL, az REAL,
        gx REAL, gy REAL, gz REAL,
        FOREIGN KEY (recordingId) REFERENCES recordings (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createThresholdsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS thresholds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accelThreshold REAL,
        gyroThreshold REAL,
        timestamp TEXT
      )
    ''');
  }

  // ===== RECORDINGS =====

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
    await db.delete('samples', where: 'recordingId = ?', whereArgs: [id]);
    await db.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAllRecordings() async {
    final db = await database;
    await db.delete('samples');
    await db.delete('recordings');
  }

  // ===== SAMPLES =====

  Future<void> insertSamples(int recordingId, List<dynamic> samples) async {
    final db = await database;
    final batch = db.batch();
    for (var sample in samples) {
      batch.insert('samples', {
        'recordingId': recordingId,
        'timestampMs': sample.timestampMs,
        'ax': sample.ax,
        'ay': sample.ay,
        'az': sample.az,
        'gx': sample.gx,
        'gy': sample.gy,
        'gz': sample.gz,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<SampleRow>> getSamplesForRecording(int recordingId) async {
    final db = await database;
    final maps = await db.query(
      'samples',
      where: 'recordingId = ?',
      whereArgs: [recordingId],
      orderBy: 'timestampMs ASC',
    );
    return maps.map((m) => SampleRow.fromMap(m)).toList();
  }

  Future<List<SampleRow>> getAllSamples() async {
    final db = await database;
    final maps = await db.query('samples', orderBy: 'timestampMs ASC');
    return maps.map((m) => SampleRow.fromMap(m)).toList();
  }

  // ===== THRESHOLDS =====

  Future<void> saveThreshold(Threshold threshold) async {
    final db = await database;
    await db.delete('thresholds');
    await db.insert('thresholds', threshold.toMap());
  }

  Future<Threshold?> getLatestThreshold() async {
    final db = await database;
    final maps = await db.query('thresholds', orderBy: 'id DESC', limit: 1);
    if (maps.isEmpty) return null;
    return Threshold.fromMap(maps.first);
  }
}