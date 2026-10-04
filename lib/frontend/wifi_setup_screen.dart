import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WifiSetupScreen extends StatefulWidget {
  /// Called when ESP32 reports a successful Wi-Fi connection.
  /// Receives the ESP32's IP (e.g. "192.168.43.50").
  final void Function(String ip) onConnected;

  const WifiSetupScreen({super.key, required this.onConnected});

  @override
  State<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends State<WifiSetupScreen> {
  // ===== SAME UUIDS AS ESP32 FIRMWARE =====
  static const String SERVICE_UUID =
      "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String NOTIFY_UUID =
      "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String WRITE_UUID =
      "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String DEVICE_NAME = "ArmCare_ESP32";

  final TextEditingController _ssidCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _isConnecting = false;
  String? _statusMessage;
  Color _statusColor = Colors.grey;

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ssid = _ssidCtrl.text.trim();
    final pass = _passCtrl.text;

    if (ssid.isEmpty || pass.isEmpty) {
      _setStatus('Please fill in both fields', Colors.red);
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Scanning for ESP32...';
      _statusColor = Colors.blue;
    });

    BluetoothDevice? device;
    BluetoothCharacteristic? writeChar;
    BluetoothCharacteristic? notifyChar;
    StreamSubscription? notifySub;
    bool success = false;

    try {
      // ===== 1. Find ESP32 =====
      final completer = Completer<BluetoothDevice?>();
      final scanSub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          final devName = r.device.platformName;
          final advName = r.advertisementData.advName;
          if ((devName == DEVICE_NAME || advName == DEVICE_NAME) &&
              !completer.isCompleted) {
            completer.complete(r.device);
            return;
          }
        }
      });

      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      device = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );

      await scanSub.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}

      if (device == null) {
        _setStatus('ESP32 not found. Make sure it is on and nearby.',
            Colors.red);
        setState(() => _isConnecting = false);
        return;
      }

      _setStatus('Found ESP32. Connecting...', Colors.blue);

      // ===== 2. Connect + discover =====
      await device.connect();

      final services = await device.discoverServices();
      for (final s in services) {
        if (s.uuid.toString().toUpperCase() == SERVICE_UUID.toUpperCase()) {
          for (final c in s.characteristics) {
            final uuid = c.uuid.toString().toUpperCase();
            if (uuid == WRITE_UUID.toUpperCase()) {
              writeChar = c;
            } else if (uuid == NOTIFY_UUID.toUpperCase()) {
              notifyChar = c;
            }
          }
        }
      }

      if (writeChar == null || notifyChar == null) {
        _setStatus('ESP32 is missing required BLE characteristics.',
            Colors.red);
        await device.disconnect();
        setState(() => _isConnecting = false);
        return;
      }

      // ===== 3. Subscribe to notify BEFORE enabling it =====
      final replyCompleter = Completer<String?>();
      notifySub = notifyChar.onValueReceived.listen((value) {
        final msg = String.fromCharCodes(value);
        print('WiFiSetup: reply from ESP32 -> "$msg"');

        if (msg.startsWith('WIFI_OK:') && !replyCompleter.isCompleted) {
          final ip = msg.substring('WIFI_OK:'.length).trim();
          replyCompleter.complete(ip);
        } else if (msg == 'WIFI_FAIL' && !replyCompleter.isCompleted) {
          replyCompleter.complete(null);
        }
      });

      await notifyChar.setNotifyValue(true);

      // ===== 4. Send credentials =====
      _setStatus('Sending credentials...', Colors.blue);
      final payload = 'WIFI:$ssid:$pass';
      await writeChar.write(payload.codeUnits, withoutResponse: false);
      print('WiFiSetup: sent "$payload"');

      // ===== 5. Wait for reply (up to 20s for ESP32 to try connecting) =====
      _setStatus('Waiting for ESP32 to connect...', Colors.blue);

      final ip = await replyCompleter.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => null,
      );

      if (ip == null) {
        _setStatus(
            'ESP32 failed to connect. Check Wi-Fi name/password.', Colors.red);
      } else {
        _setStatus('Connected! ESP32 IP: $ip', Colors.green);
        success = true;
        widget.onConnected(ip);

        // Give the user a moment to see the success
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      print('WiFiSetup error: $e');
      _setStatus('Error: $e', Colors.red);
    } finally {
      await notifySub?.cancel();
      try {
        await device?.disconnect();
      } catch (_) {}
      if (mounted && !success) {
        setState(() => _isConnecting = false);
      }
    }
  }

  void _setStatus(String msg, Color color) {
    if (!mounted) return;
    setState(() {
      _statusMessage = msg;
      _statusColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Wi-Fi Setup'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== Info banner =====
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[800], size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Enter your Wi-Fi network details. '
                        'The ESP32 will join that network and report its IP back.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ===== SSID field =====
              TextField(
                controller: _ssidCtrl,
                enabled: !_isConnecting,
                decoration: const InputDecoration(
                  labelText: 'Wi-Fi Name (SSID)',
                  hintText: 'e.g. HomeWiFi_5G',
                  prefixIcon: Icon(Icons.wifi),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // ===== Password field =====
              TextField(
                controller: _passCtrl,
                enabled: !_isConnecting,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ===== Connect button =====
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isConnecting ? null : _connect,
                  icon: _isConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.link),
                  label: Text(
                    _isConnecting ? 'Connecting...' : 'Connect',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              // ===== Status message =====
              if (_statusMessage != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _statusColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
} 