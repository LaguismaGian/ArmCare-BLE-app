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

class AlertRow {
  final int? id;
  final String alertClass;
  final String label;
  final String message;
  final String timestamp;
  final double hr;
  final double motion;
  final double gyro;

  AlertRow({
    this.id,
    required this.alertClass,
    required this.label,
    required this.message,
    required this.timestamp,
    required this.hr,
    required this.motion,
    required this.gyro,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'alertClass': alertClass,
      'label': label,
      'message': message,
      'timestamp': timestamp,
      'hr': hr,
      'motion': motion,
      'gyro': gyro,
    };
  }

  factory AlertRow.fromMap(Map<String, dynamic> map) {
    return AlertRow(
      id: map['id'],
      alertClass: map['alertClass'],
      label: map['label'],
      message: map['message'],
      timestamp: map['timestamp'],
      hr: map['hr'],
      motion: map['motion'],
      gyro: map['gyro'],
    );
  }
}

class Contact {
  final int? id;
  final String name;
  final String phone;

  Contact({
    this.id,
    required this.name,
    required this.phone,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
    };
  }

  factory Contact.fromMap(Map<String, dynamic> map) {
    return Contact(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
    );
  }
}

/// User profile data.
class Profile {
  final int? id;
  final String name;
  final String? photoPath;
  final String gender;
  final int age;
  final String address;
  final int? emergencyContactId; // FK to contacts table
  final String medicalCondition;

  Profile({
    this.id,
    required this.name,
    this.photoPath,
    required this.gender,
    required this.age,
    required this.address,
    this.emergencyContactId,
    required this.medicalCondition,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'photoPath': photoPath,
      'gender': gender,
      'age': age,
      'address': address,
      'emergencyContactId': emergencyContactId,
      'medicalCondition': medicalCondition,
    };
  }

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'],
      name: map['name'] ?? '',
      photoPath: map['photoPath'],
      gender: map['gender'] ?? '',
      age: map['age'] ?? 0,
      address: map['address'] ?? '',
      emergencyContactId: map['emergencyContactId'],
      medicalCondition: map['medicalCondition'] ?? '',
    );
  }
}

/// Caregiver details.
class Caregiver {
  final int? id;
  final String name;
  final String? photoPath;
  final int age;
  final String address;
  final String phone;
  final String relationship;

  Caregiver({
    this.id,
    required this.name,
    this.photoPath,
    required this.age,
    required this.address,
    required this.phone,
    required this.relationship,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'photoPath': photoPath,
      'age': age,
      'address': address,
      'phone': phone,
      'relationship': relationship,
    };
  }

  factory Caregiver.fromMap(Map<String, dynamic> map) {
    return Caregiver(
      id: map['id'],
      name: map['name'] ?? '',
      photoPath: map['photoPath'],
      age: map['age'] ?? 0,
      address: map['address'] ?? '',
      phone: map['phone'] ?? '',
      relationship: map['relationship'] ?? '',
    );
  }
}

/// One HR recording session (60s avg).
class HrSession {
  final int? id;
  final double avgBpm;
  final int sampleCount;
  final int durationMs;
  final String timestamp;

  HrSession({
    this.id,
    required this.avgBpm,
    required this.sampleCount,
    required this.durationMs,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'avgBpm': avgBpm,
      'sampleCount': sampleCount,
      'durationMs': durationMs,
      'timestamp': timestamp,
    };
  }

  factory HrSession.fromMap(Map<String, dynamic> map) {
    return HrSession(
      id: map['id'],
      avgBpm: (map['avgBpm'] as num).toDouble(),
      sampleCount: map['sampleCount'] ?? 0,
      durationMs: map['durationMs'] ?? 0,
      timestamp: map['timestamp'] ?? '',
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
      version: 6,
      onCreate: (db, version) async {
        await _createRecordingsTable(db);
        await _createSamplesTable(db);
        await _createThresholdsTable(db);
        await _createAlertsTable(db);
        await _createContactsTable(db);
        await _createProfileTable(db);
        await _createCaregiverTable(db);
        await _createHrSessionsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createRecordingsTable(db);
        await _createSamplesTable(db);
        await _createThresholdsTable(db);
        await _createAlertsTable(db);
        await _createContactsTable(db);
        await _createProfileTable(db);
        await _createCaregiverTable(db);
        await _createHrSessionsTable(db);
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

  Future<void> _createAlertsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alertClass TEXT,
        label TEXT,
        message TEXT,
        timestamp TEXT,
        hr REAL,
        motion REAL,
        gyro REAL
      )
    ''');
  }

  Future<void> _createContactsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contacts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        phone TEXT
      )
    ''');
  }

  Future<void> _createProfileTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS profile (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        photoPath TEXT,
        gender TEXT,
        age INTEGER,
        address TEXT,
        emergencyContactId INTEGER,
        medicalCondition TEXT
      )
    ''');
  }

  Future<void> _createCaregiverTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS caregiver (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        photoPath TEXT,
        age INTEGER,
        address TEXT,
        phone TEXT,
        relationship TEXT
      )
    ''');
  }

  Future<void> _createHrSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hr_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        avgBpm REAL,
        sampleCount INTEGER,
        durationMs INTEGER,
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

  Future<void> clearCalibration() async {
    final db = await database;
    await db.delete('samples');
    await db.delete('recordings');
    await db.delete('thresholds');
  }

  // ===== ALERTS =====

  Future<int> insertAlert(AlertRow alert) async {
    final db = await database;
    return await db.insert('alerts', alert.toMap());
  }

  Future<List<AlertRow>> getRecentAlerts({int limit = 20}) async {
    final db = await database;
    final maps = await db.query(
      'alerts',
      orderBy: 'id DESC',
      limit: limit,
    );
    return maps.map((m) => AlertRow.fromMap(m)).toList();
  }

  Future<List<AlertRow>> getAllAlerts() async {
    final db = await database;
    final maps = await db.query('alerts', orderBy: 'id DESC');
    return maps.map((m) => AlertRow.fromMap(m)).toList();
  }

  Future<void> clearAllAlerts() async {
    final db = await database;
    await db.delete('alerts');
  }

  // ===== CONTACTS =====

  Future<int> insertContact(Contact contact) async {
    final db = await database;
    return await db.insert('contacts', contact.toMap());
  }

  Future<List<Contact>> getAllContacts() async {
    final db = await database;
    final maps = await db.query('contacts', orderBy: 'id ASC');
    return maps.map((m) => Contact.fromMap(m)).toList();
  }

  Future<void> deleteContact(int id) async {
    final db = await database;
    await db.delete('contacts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAllContacts() async {
    final db = await database;
    await db.delete('contacts');
  }

  // ===== PROFILE =====
  // There is only ever ONE profile row. Save overwrites.

  Future<void> saveProfile(Profile profile) async {
    final db = await database;
    await db.delete('profile'); // keep only one
    await db.insert('profile', profile.toMap());
  }

  Future<Profile?> getProfile() async {
    final db = await database;
    final maps = await db.query('profile', limit: 1);
    if (maps.isEmpty) return null;
    return Profile.fromMap(maps.first);
  }

  Future<void> clearProfile() async {
    final db = await database;
    await db.delete('profile');
  }

  // ===== CAREGIVER =====
  // There is only ever ONE caregiver row. Save overwrites.

  Future<void> saveCaregiver(Caregiver caregiver) async {
    final db = await database;
    await db.delete('caregiver');
    await db.insert('caregiver', caregiver.toMap());
  }

  Future<Caregiver?> getCaregiver() async {
    final db = await database;
    final maps = await db.query('caregiver', limit: 1);
    if (maps.isEmpty) return null;
    return Caregiver.fromMap(maps.first);
  }

  Future<void> clearCaregiver() async {
    final db = await database;
    await db.delete('caregiver');
  }

  // ===== HR SESSIONS =====

  Future<int> insertHrSession(HrSession session) async {
    final db = await database;
    return await db.insert('hr_sessions', session.toMap());
  }

  Future<List<HrSession>> getAllHrSessions() async {
    final db = await database;
    final maps = await db.query('hr_sessions', orderBy: 'id DESC');
    return maps.map((m) => HrSession.fromMap(m)).toList();
  }

  Future<HrSession?> getLatestHrSession() async {
    final db = await database;
    final maps =
        await db.query('hr_sessions', orderBy: 'id DESC', limit: 1);
    if (maps.isEmpty) return null;
    return HrSession.fromMap(maps.first);
  }

  Future<void> clearAllHrSessions() async {
    final db = await database;
    await db.delete('hr_sessions');
  }
}