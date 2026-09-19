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

  Future<bool> connect() async {
    try {
      BluetoothDevice? targetDevice;
      Completer<BluetoothDevice?> completer = Completer();

      // Listen for scan results — wait specifically for OUR device
      FlutterBluePlus.onScanResults.listen((results) {
        for (var scanResult in results) {
          if (scanResult.device.name == DEVICE_NAME) {
            if (!completer.isCompleted) {
              completer.complete(scanResult.device);
            }
            FlutterBluePlus.stopScan();
            return;
          }
        }
      });

      // Start scanning
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 15));

      // Wait specifically for our device
      targetDevice = await completer.future.timeout(
        Duration(seconds: 15),
        onTimeout: () {
          print("Scan timed out — device not found");
          return null;
        },
      );

      if (targetDevice == null) return false;

      connectedDevice = targetDevice;
      await connectedDevice!.connect();

      List<BluetoothService> services =
          await connectedDevice!.discoverServices();

      for (var service in services) {
        if (service.uuid.toString().toUpperCase() == SERVICE_UUID.toUpperCase()) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() ==
                CHARACTERISTIC_UUID.toUpperCase()) {
              dataCharacteristic = characteristic;
              await dataCharacteristic!.setNotifyValue(true);

              dataCharacteristic!.onValueReceived.listen((value) {
                _dataController.add(String.fromCharCodes(value));
              });

              return true;
            }
          }
        }
      }

      return false;
    } catch (e) {
    print("BLE Error: $e");
      return false;
    }
  }

  Future<void> disconnect() async {
    await connectedDevice?.disconnect();
    connectedDevice = null;
    dataCharacteristic = null;
  }

  bool isConnected() {
    return connectedDevice != null && connectedDevice!.isConnected;
  }
}