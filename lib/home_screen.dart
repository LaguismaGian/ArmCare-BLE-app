import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';
import 'plotter_screen.dart';
import 'kalman_filter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BleService ble = BleService();
  bool isConnected = false;
  bool isScanning = false;

  double _hr = 0.0;
  double _motion = 0.0;
  double _gyro = 0.0;

  // Battery percentage (placeholder)
  int _battery = 85;

  // Kalman filters
  KalmanFilter hrFilter = KalmanFilter(Q: 0.1, R: 1.0);
  KalmanFilter motionFilter = KalmanFilter(Q: 0.1, R: 0.5);
  KalmanFilter gyroFilter = KalmanFilter(Q: 0.01, R: 0.1);

  final AudioPlayer _audioPlayer = AudioPlayer();
  DateTime? _lastAlertTime;

  @override
  void initState() {
    super.initState();
    _requestPermissions();

    ble.dataStream.listen((data) {
      var parts = data.split(',');
      if (parts.length >= 3) {
        double rawHR = double.tryParse(parts[0]) ?? 0;
        double rawMotion = double.tryParse(parts[1]) ?? 0;
        double rawGyro = double.tryParse(parts[2]) ?? 0;

        // Apply Kalman filter
        double filteredHR = hrFilter.update(rawHR);
        double filteredMotion = motionFilter.update(rawMotion);
        double filteredGyro = gyroFilter.update(rawGyro);

        setState(() {
          _hr = filteredHR;
          _motion = filteredMotion;
          _gyro = filteredGyro;
        });
        _checkForAlerts();
      }
    });
  }

  void _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  void _checkForAlerts() {
    bool alertTriggered = false;
    String alertMessage = "";

    if (_motion > 2.5) {
      alertTriggered = true;
      alertMessage = "⚠️ Fall Detected!";
    } else if (_hr > 130) {
      alertTriggered = true;
      alertMessage = "⚠️ High Heart Rate: ${_hr.toInt()} BPM";
    } else if (_hr > 0 && _hr < 40) {
      alertTriggered = true;
      alertMessage = "⚠️ Low Heart Rate: ${_hr.toInt()} BPM";
    }

    if (alertTriggered) {
      if (_lastAlertTime == null ||
          DateTime.now().difference(_lastAlertTime!).inSeconds > 10) {
        _lastAlertTime = DateTime.now();
        _playAlertSound();
        _showAlertDialog(alertMessage);
      }
    }
  }

  void _playAlertSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/alert.mp3'));
    } catch (e) {
      print("Asset error: $e");
      try {
        await _audioPlayer.play(
          UrlSource('https://www.soundjay.com/misc/sounds/bell-ringing-05.mp3'),
        );
      } catch (e2) {
        print("URL error: $e2");
      }
    }
  }

  void _showAlertDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('🚨 Alert'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _testScan() async {
    print("=== TEST SCAN (Stream Method) ===");
    try {
      FlutterBluePlus.onScanResults.listen((results) {
        print("📡 Scan results: ${results.length} devices");
        for (var r in results) {
          print("  - ${r.device.name} (${r.device.remoteId})");
        }
      });

      FlutterBluePlus.startScan(timeout: Duration(seconds: 5));

      await Future.delayed(Duration(seconds: 6));

      FlutterBluePlus.stopScan();
      print("=== SCAN COMPLETE ===");
    } catch (e) {
      print("Scan error: $e");
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    ble.disconnect();
    super.dispose();
  }

  void _toggleConnection() async {
    if (isConnected) {
      await ble.disconnect();
      setState(() => isConnected = false);
    } else {
      setState(() => isScanning = true);
      bool success = await ble.connect();
      setState(() {
        isScanning = false;
        isConnected = success;
      });
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected to ESP32!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'ArmCare',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Battery Indicator (only show when connected)
          if (isConnected) ...[
            Row(
              children: [
                Icon(
                  _getBatteryIcon(),
                  color: _getBatteryColor(),
                  size: 22,
                ),
                const SizedBox(width: 4),
                Text(
                  '$_battery%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ],
          // Bluetooth Icon
          IconButton(
            icon: Icon(
              isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: isConnected ? Colors.lightGreenAccent : Colors.white70,
            ),
            onPressed: _toggleConnection,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Connection Status Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isConnected ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isConnected ? Colors.green[300]! : Colors.red[300]!,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isConnected ? Icons.check_circle : Icons.error_outline,
                      color: isConnected ? Colors.green : Colors.red,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isConnected ? 'Connected to ESP32' : 'Disconnected',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isConnected ? Colors.green[800] : Colors.red[800],
                        ),
                      ),
                    ),
                    if (isScanning)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blue,
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Main Data Cards
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.1,
                  children: [
                    _buildMetricCard(
                      title: 'Heart Rate',
                      value: '${_hr.toInt()}',
                      unit: 'BPM',
                      icon: Icons.favorite,
                      color: Colors.red,
                      gradient: const [Color(0xFFEF5350), Color(0xFFD32F2F)],
                    ),
                    _buildMetricCard(
                      title: 'Motion',
                      value: _motion.toStringAsFixed(2),
                      unit: 'g',
                      icon: Icons.speed,
                      color: Colors.orange,
                      gradient: const [Color(0xFFFFA726), Color(0xFFF57C00)],
                    ),
                    _buildMetricCard(
                      title: 'Gyroscope',
                      value: _gyro.toStringAsFixed(1),
                      unit: '°/s',
                      icon: Icons.sync,
                      color: Colors.purple,
                      gradient: const [Color(0xFFAB47BC), Color(0xFF7B1FA2)],
                    ),
                    _buildMetricCard(
                      title: 'Status',
                      value: _getStatus(),
                      unit: '',
                      icon: Icons.health_and_safety,
                      color: _getStatusColor(),
                      gradient: _getStatusGradient(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Plotter Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PlotterScreen(dataStream: ble.dataStream),
                      ),
                    );
                  },
                  icon: const Icon(Icons.show_chart),
                  label: const Text(
                    'Open Plotter',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Test Scan Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _testScan,
                  icon: const Icon(Icons.search),
                  label: const Text(
                    'Test Scan',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Connect Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _toggleConnection,
                  icon: Icon(isConnected ? Icons.bluetooth_disabled : Icons.bluetooth),
                  label: Text(
                    isConnected ? 'Disconnect' : 'Connect to ESP32',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected ? Colors.red[400] : Colors.blue[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
    required List<Color> gradient,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(icon, color: Colors.white70, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (unit.isNotEmpty)
              Text(
                unit,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getStatus() {
    if (_hr == 0 && _motion == 0 && _gyro == 0) {
      return '--';
    }
    if (_hr > 80) {
      return 'Elevated';
    }
    if (_motion > 1.5) {
      return 'Moving';
    }
    return 'Normal';
  }

  Color _getStatusColor() {
    if (_hr == 0 && _motion == 0 && _gyro == 0) {
      return Colors.grey;
    }
    if (_hr > 80) {
      return Colors.orange;
    }
    if (_motion > 1.5) {
      return Colors.blue;
    }
    return Colors.green;
  }

  List<Color> _getStatusGradient() {
    if (_hr == 0 && _motion == 0 && _gyro == 0) {
      return [Colors.grey[400]!, Colors.grey[600]!];
    }
    if (_hr > 80) {
      return [Colors.orange[400]!, Colors.orange[800]!];
    }
    if (_motion > 1.5) {
      return [Colors.blue[400]!, Colors.blue[800]!];
    }
    return [Colors.green[400]!, Colors.green[800]!];
  }

  // ===== BATTERY HELPER FUNCTIONS =====
  IconData _getBatteryIcon() {
    if (_battery >= 80) return Icons.battery_full;
    if (_battery >= 60) return Icons.battery_6_bar;
    if (_battery >= 40) return Icons.battery_4_bar;
    if (_battery >= 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  Color _getBatteryColor() {
    if (_battery >= 40) return Colors.white;
    if (_battery >= 20) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}