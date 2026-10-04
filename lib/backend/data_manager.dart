import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'ble_service.dart';
import 'wifi_service.dart';
import 'alert_service.dart';
import 'database_service.dart';
import 'sensor_data.dart';

enum SensorMode { ble, phone, wifi }

class DataManager {
  final BleService _ble = BleService();
  final WifiService _wifi = WifiService();
  final AlertService _alertService = AlertService();
  final DatabaseService _db = DatabaseService.instance;

  SensorMode _mode = SensorMode.ble;
  SensorMode get mode => _mode;

  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;
  StreamSubscription? _wifiSub;

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

  bool get isConnected {
    if (_mode == SensorMode.ble) return _ble.isConnected();
    if (_mode == SensorMode.wifi) return _wifi.isConnected();
    return false;
  }

  /// Raw line stream from whichever remote source is active (BLE or Wi-Fi).
  /// Used by RecordingService for fall-data capture.
  Stream<String> get rawDataStream {
    if (_mode == SensorMode.wifi) return _wifi.dataStream;
    return _ble.dataStream;
  }

  /// IP of the ESP32 (only set in Wi-Fi mode).
  String? get espIp => _wifi.espIp;

  DataManager() {
    _ble.dataStream.listen(_processIncomingData);
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

  Future<void> _handleAlert(AlertEvent event) async {
    try {
      await _db.insertAlert(event.toRow());
    } catch (e) {
      print('Failed to save alert: $e');
    }
    _alertController.add(event);
  }

  // ===== REMOTE DATA (BLE + Wi-Fi share this) =====

  void _processIncomingData(String raw) {
    // Route by current mode
    if (_mode != SensorMode.ble && _mode != SensorMode.wifi) return;

    var parts = raw.split(',');
    if (parts.length < 3) return;

    double hr = double.tryParse(parts[0]) ?? 0;
    double rawMotion = double.tryParse(parts[1]) ?? 0;
    double gyro = double.tryParse(parts[2]) ?? 0;

    // Remote sends motion as fused magnitude (near 1g at rest).
    double motion = (rawMotion - 1.0).abs();

    _dataController.add(SensorData(hr: hr, motion: motion, gyro: gyro));

    final event = _alertService.checkAlert(hr, motion, gyro: gyro);
    if (event != null) {
      _handleAlert(event);
    }
  }

  // ===== MODE SWITCH =====

  Future<void> setMode(SensorMode newMode) async {
    if (newMode == _mode) return;

    // Stop phone sensors if leaving phone mode
    if (_mode == SensorMode.phone) {
      _stopPhoneSensors();
    }

    // Disconnect BLE if leaving BLE mode
    if (_mode == SensorMode.ble && newMode != SensorMode.ble) {
      await _ble.disconnect();
      _connectionController.add(false);
    }

    // Disconnect Wi-Fi if leaving Wi-Fi mode
    if (_mode == SensorMode.wifi && newMode != SensorMode.wifi) {
      await _wifiSub?.cancel();
      _wifiSub = null;
      await _wifi.disconnect();
      _connectionController.add(false);
    }

    _mode = newMode;
    _modeController.add(newMode);

    // Start phone sensors if entering phone mode
    if (newMode == SensorMode.phone) {
      _startPhoneSensors();
    }
  }

  void _startPhoneSensors() {
    _accelSub = accelerometerEvents.listen((event) {
      final rawMag = sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z) /
          9.81;
      _phoneMotion = (rawMag - 1.0).abs();

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

  // ===== CONNECTION — BLE =====

  Future<bool> connect() async {
    if (_mode != SensorMode.ble) {
      print('BLE connect blocked — mode is $_mode');
      return false;
    }
    bool success = await _ble.connect();
    _connectionController.add(success);
    return success;
  }

  Future<void> disconnect() async {
    await _ble.disconnect();
    _connectionController.add(false);
  }

  // ===== CONNECTION — WI-FI =====

  /// Connect to the ESP32 at [ip] over TCP.
  /// Caller must have switched mode to [SensorMode.wifi] first.
  Future<bool> connectWifi(String ip) async {
    if (_mode != SensorMode.wifi) {
      print('WiFi connect blocked — mode is $_mode');
      return false;
    }

    await _wifiSub?.cancel();
    _wifiSub = null;

    final success = await _wifi.connect(ip);

    if (success) {
      // Route Wi-Fi stream through the same parser as BLE
      _wifiSub = _wifi.dataStream.listen(_processIncomingData);
    }

    _connectionController.add(success);
    return success;
  }

  Future<void> disconnectWifi() async {
    await _wifiSub?.cancel();
    _wifiSub = null;
    await _wifi.disconnect();
    _connectionController.add(false);
  }

  // ===== DISPOSE =====

  void dispose() {
    _stopPhoneSensors();
    _wifiSub?.cancel();
    _wifi.dispose();
    _alertService.dispose();
    _dataController.close();
    _alertController.close();
    _connectionController.close();
    _modeController.close();
  }
}