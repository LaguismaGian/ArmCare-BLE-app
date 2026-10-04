import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static const String SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String CHARACTERISTIC_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String DEVICE_NAME = "ArmCare_ESP32";

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? dataCharacteristic;

  final StreamController<String> _dataController =
      StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataController.stream;

  StreamSubscription? _scanSub;
  StreamSubscription? _valueSub;

  Future<bool> connect() async {
    try {
      // ===== 1. Clean up any previous scan =====
      try {
        if (FlutterBluePlus.isScanningNow) {
          await FlutterBluePlus.stopScan();
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));

      // ===== 2. Cancel any previous scan listener =====
      await _scanSub?.cancel();
      _scanSub = null;

      BluetoothDevice? targetDevice;
      final completer = Completer<BluetoothDevice?>();

      // ===== 3. Set up scan listener =====
      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        for (var scanResult in results) {
          final advName = scanResult.advertisementData.advName;
          final devName = scanResult.device.platformName;
          final matches = devName == DEVICE_NAME || advName == DEVICE_NAME;

          if (matches && !completer.isCompleted) {
            completer.complete(scanResult.device);
            return;
          }
        }
      });

      // ===== 4. Start scanning =====
      print('BLE: Starting scan for $DEVICE_NAME');
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      // ===== 5. Wait for device or timeout =====
      targetDevice = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('BLE: Scan timed out — $DEVICE_NAME not found');
          return null;
        },
      );

      // ===== 6. Stop scan + cancel listener =====
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await _scanSub?.cancel();
      _scanSub = null;

      if (targetDevice == null) return false;

      // ===== 7. Connect =====
      print('BLE: Found device, connecting...');
      connectedDevice = targetDevice;
      await connectedDevice!.connect();

      // ===== 8. Discover services =====
      List<BluetoothService> services =
          await connectedDevice!.discoverServices();

      for (var service in services) {
        if (service.uuid.toString().toUpperCase() ==
            SERVICE_UUID.toUpperCase()) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() ==
                CHARACTERISTIC_UUID.toUpperCase()) {
              dataCharacteristic = characteristic;

              // ===== 9. Cancel old value subscription =====
              await _valueSub?.cancel();
              _valueSub = null;

              // ===== 10. Listen BEFORE enabling notify =====
              _valueSub = dataCharacteristic!.onValueReceived.listen((value) {
                final raw = String.fromCharCodes(value);
                print('BLE data: $raw');
                _dataController.add(raw);
              });

              // ===== 11. Enable notifications =====
              await dataCharacteristic!.setNotifyValue(true);
              print('BLE: Notify enabled for $CHARACTERISTIC_UUID');

              print('BLE: Connected + subscribed');
              return true;
            }
          }
        }
      }

      print('BLE: Characteristic not found');
      return false;
    } catch (e) {
      print('BLE Error: $e');
      try {
        await _scanSub?.cancel();
      } catch (_) {}
      _scanSub = null;
      return false;
    }
  }

  Future<void> disconnect() async {
    await _scanSub?.cancel();
    _scanSub = null;

    await _valueSub?.cancel();
    _valueSub = null;

    try {
      await connectedDevice?.disconnect();
    } catch (_) {}

    connectedDevice = null;
    dataCharacteristic = null;
  }

  bool isConnected() {
    return connectedDevice != null && connectedDevice!.isConnected;
  }
}