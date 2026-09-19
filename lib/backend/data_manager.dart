import 'dart:async';
import 'ble_service.dart';
import 'alert_service.dart';
import 'sensor_data.dart';

class DataManager {
  final BleService _ble = BleService();
  final AlertService _alertService = AlertService();

  final StreamController<SensorData> _dataController =
      StreamController<SensorData>.broadcast();
  final StreamController<String> _alertController =
      StreamController<String>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<SensorData> get dataStream => _dataController.stream;
  Stream<String> get alertStream => _alertController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isConnected => _ble.isConnected();

  Stream<String> get rawDataStream => _ble.dataStream;

  DataManager() {
    _ble.dataStream.listen(_processIncomingData);
  }

  void _processIncomingData(String raw) {
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

  Future<bool> connect() async {
    bool success = await _ble.connect();
    _connectionController.add(success);
    return success;
  }

  Future<void> disconnect() async {
    await _ble.disconnect();
    _connectionController.add(false);
  }

  void dispose() {
    _alertService.dispose();
    _dataController.close();
    _alertController.close();
    _connectionController.close();
  }
}