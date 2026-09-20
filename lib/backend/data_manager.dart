import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'ble_service.dart';
import 'alert_service.dart';
import 'sensor_data.dart';

enum SensorMode { ble, phone }

class DataManager {
  final BleService _ble = BleService();
  final AlertService _alertService = AlertService();

  SensorMode _mode = SensorMode.ble;
  SensorMode get mode => _mode;

  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;

  double _phoneMotion = 0.0;
  double _phoneGyro = 0.0;

  final StreamController<SensorData> _dataController =
      StreamController<SensorData>.broadcast();
  final StreamController<String> _alertController =
      StreamController<String>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<SensorMode> _modeController =
      StreamController<SensorMode>.broadcast();

  Stream<SensorData> get dataStream => _dataController.stream;
  Stream<String> get alertStream => _alertController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<SensorMode> get modeStream => _modeController.stream;

  bool get isConnected => _ble.isConnected();

  Stream<String> get rawDataStream => _ble.dataStream;

  DataManager() {
    _ble.dataStream.listen(_processBleData);
  }

  void _processBleData(String raw) {
    if (_mode != SensorMode.ble) return;

    var parts = raw.split(',');
    if (parts.length < 3) return;

    double hr = double.tryParse(parts[0]) ?? 0;
    double motion = double.tryParse(parts[1]) ?? 0;
    double gyro = double.tryParse(parts[2]) ?? 0;

    _dataController.add(SensorData(hr: hr, motion: motion, gyro: gyro));

    String? alert = _alertService.checkAlert(hr, motion);
    if (alert != null) {
      _alertController.add(alert);
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
    if (_mode == SensorMode.ble && newMode == SensorMode.phone) {
      await _ble.disconnect();
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
      // Convert m/s² to g-force
      _phoneMotion = sqrt(event.x * event.x + event.y * event.y + event.z * event.z) / 9.81;

      _dataController.add(SensorData(
        hr: 0,
        motion: _phoneMotion,
        gyro: _phoneGyro,
      ));
    });

    _gyroSub = gyroscopeEvents.listen((event) {
      // Convert rad/s to deg/s
      _phoneGyro = sqrt(event.x * event.x + event.y * event.y + event.z * event.z) *
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