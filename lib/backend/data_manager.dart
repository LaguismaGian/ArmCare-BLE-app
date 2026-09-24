import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'ble_service.dart';
import 'alert_service.dart';
import 'database_service.dart';
import 'sensor_data.dart';

enum SensorMode { ble, phone }

class DataManager {
  final BleService _ble = BleService();
  final AlertService _alertService = AlertService();
  final DatabaseService _db = DatabaseService.instance;

  SensorMode _mode = SensorMode.ble;
  SensorMode get mode => _mode;

  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;

  double _phoneMotion = 0.0;
  double _phoneGyro = 0.0;

  final StreamController<SensorData> _dataController =
      StreamController<SensorData>.broadcast();
  final StreamController<AlertEvent> _alertController =
      StreamController<AlertEvent>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<SensorMode> _modeController =
      StreamController<SensorMode>.broadcast();

  Stream<SensorData> get dataStream => _dataController.stream;
  Stream<AlertEvent> get alertStream => _alertController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<SensorMode> get modeStream => _modeController.stream;

  bool get isConnected => _ble.isConnected();

  Stream<String> get rawDataStream => _ble.dataStream;

  DataManager() {
    _ble.dataStream.listen(_processBleData);
    _loadThresholdFromDb();
  }

  // ===== THRESHOLD HANDLING =====

  Future<void> _loadThresholdFromDb() async {
    final saved = await _db.getLatestThreshold();
    if (saved != null) {
      _alertService.applyThreshold(saved);
    }
  }

  Future<void> refreshThreshold() async {
    final saved = await _db.getLatestThreshold();
    if (saved != null) {
      _alertService.applyThreshold(saved);
    } else {
      _alertService.resetToDefaults();
    }
  }

  double get activeAccelThreshold => _alertService.accelThreshold;
  double get activeGyroThreshold => _alertService.gyroThreshold;

  // ===== ALERT HANDLING =====

  /// Fire an alert: save to DB, push to stream.
  Future<void> _handleAlert(AlertEvent event) async {
    try {
      await _db.insertAlert(event.toRow());
    } catch (e) {
      print('Failed to save alert: $e');
    }
    _alertController.add(event);
  }

  // ===== BLE DATA =====

  void _processBleData(String raw) {
    if (_mode != SensorMode.ble) return;

    var parts = raw.split(',');
    if (parts.length < 3) return;

    double hr = double.tryParse(parts[0]) ?? 0;
    double motion = double.tryParse(parts[1]) ?? 0;
    double gyro = double.tryParse(parts[2]) ?? 0;

    _dataController.add(SensorData(hr: hr, motion: motion, gyro: gyro));

    final event = _alertService.checkAlert(hr, motion, gyro: gyro);
    if (event != null) {
      _handleAlert(event);
    }
  }

  // ===== MODE SWITCH =====

  Future<void> setMode(SensorMode newMode) async {
    if (newMode == _mode) return;

    if (_mode == SensorMode.phone) {
      _stopPhoneSensors();
    }

    if (_mode == SensorMode.ble && newMode == SensorMode.phone) {
      await _ble.disconnect();
      _connectionController.add(false);
    }

    _mode = newMode;
    _modeController.add(newMode);

    if (newMode == SensorMode.phone) {
      _startPhoneSensors();
    }
  }

  void _startPhoneSensors() {
    _accelSub = accelerometerEvents.listen((event) {
      // m/s² → g
      _phoneMotion = sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z) /
          9.81;

      _dataController.add(SensorData(
        hr: 0,
        motion: _phoneMotion,
        gyro: _phoneGyro,
      ));

      final alertEvent =
          _alertService.checkAlert(0, _phoneMotion, gyro: _phoneGyro);
      if (alertEvent != null) {
        _handleAlert(alertEvent);
      }
    });

    _gyroSub = gyroscopeEvents.listen((event) {
      // rad/s → °/s
      _phoneGyro = sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z) *
          (180 / pi);
    });
  }

  void _stopPhoneSensors() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _phoneMotion = 0.0;
    _phoneGyro = 0.0;
  }

  // ===== CONNECTION =====

  Future<bool> connect() async {
    if (_mode != SensorMode.ble) return false;
    bool success = await _ble.connect();
    _connectionController.add(success);
    return success;
  }

  Future<void> disconnect() async {
    await _ble.disconnect();
    _connectionController.add(false);
  }

  void dispose() {
    _stopPhoneSensors();
    _alertService.dispose();
    _dataController.close();
    _alertController.close();
    _connectionController.close();
    _modeController.close();
  }
}