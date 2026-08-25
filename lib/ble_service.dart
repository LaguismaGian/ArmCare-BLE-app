import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static const String SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String CHARACTERISTIC_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String DEVICE_NAME = "ArmCare_ESP32";

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? dataCharacteristic;

  final StreamController<String> _dataController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataController.stream;

  Future<bool> connect() async {
    try {
      Completer<List<ScanResult>> completer = Completer();

      // Listen for scan results
      FlutterBluePlus.onScanResults.listen((results) {
        if (results.isNotEmpty && !completer.isCompleted) {
          print("Scan received: ${results.length} devices");
          completer.complete(results);
        }
      });

      // Start scanning
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 10));

      // Wait for results
      List<ScanResult> results = await completer.future.timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print("Scan timed out");
          return [];
        },
      );

      print("Found ${results.length} devices");

      BluetoothDevice? targetDevice;
      for (var scanResult in results) {
        print("Device: ${scanResult.device.name} (${scanResult.device.remoteId})");
        if (scanResult.device.name == DEVICE_NAME) {
          targetDevice = scanResult.device;
          break;
        }
      }

      if (targetDevice == null) {
        print("Device not found");
        return false;
      }

      await FlutterBluePlus.stopScan();

      connectedDevice = targetDevice;
      await connectedDevice!.connect();
      print("Connected to ${connectedDevice!.name}");

      List<BluetoothService> services = await connectedDevice!.discoverServices();

      for (var service in services) {
        if (service.uuid.toString().toUpperCase() == SERVICE_UUID.toUpperCase()) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() == CHARACTERISTIC_UUID.toUpperCase()) {
              dataCharacteristic = characteristic;
              await dataCharacteristic!.setNotifyValue(true);

              dataCharacteristic!.onValueReceived.listen((value) {
                String data = String.fromCharCodes(value);
                print("Direct BLE data: $data");
                _dataController.add(data);
              });

              print("Data characteristic found");
              return true;
            }
          }
        }
      }

      print("Characteristic not found");
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