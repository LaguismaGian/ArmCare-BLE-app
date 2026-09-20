import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../backend/data_manager.dart';
import 'widgets/metric_card.dart';
import 'widgets/connection_status.dart';
import 'widgets/battery_indicator.dart';
import 'plotter_screen.dart';
import 'record_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DataManager _dataManager = DataManager();

  double _hr = 0.0;
  double _motion = 0.0;
  double _gyro = 0.0;
  bool _isConnected = false;
  bool _isScanning = false;
  SensorMode _currentMode = SensorMode.ble;

  final int _battery = 85;

  @override
  void initState() {
    super.initState();
    _requestPermissions();

    _dataManager.dataStream.listen((data) {
      setState(() {
        _hr = data.hr;
        _motion = data.motion;
        _gyro = data.gyro;
      });
    });

    _dataManager.alertStream.listen((message) {
      _showAlertDialog(message);
    });

    _dataManager.connectionStream.listen((connected) {
      setState(() => _isConnected = connected);
    });

    _dataManager.modeStream.listen((mode) {
      setState(() => _currentMode = mode);
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

  void _toggleConnection() async {
    if (_isConnected) {
      await _dataManager.disconnect();
    } else {
      setState(() => _isScanning = true);
      bool success = await _dataManager.connect();
      setState(() {
        _isScanning = false;
        _isConnected = success;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Connected!' : 'Failed to connect'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  void _toggleMode() {
    if (_currentMode == SensorMode.ble) {
      _dataManager.setMode(SensorMode.phone);
    } else {
      _dataManager.setMode(SensorMode.ble);
    }
  }

  @override
  void dispose() {
    _dataManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isPhoneMode = _currentMode == SensorMode.phone;
    bool showConnection = !isPhoneMode;

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
          if (_isConnected && !isPhoneMode)
            BatteryIndicator(battery: _battery),
          if (showConnection)
            IconButton(
              icon: Icon(
                _isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: _isConnected ? Colors.lightGreenAccent : Colors.white70,
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
              if (showConnection)
                ConnectionStatus(
                  isConnected: _isConnected,
                  isScanning: _isScanning,
                ),
              if (isPhoneMode)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[300]!, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.phone_android,
                          color: Colors.orange[800], size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Using Phone Sensors',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.1,
                  children: [
                    MetricCard(
                      title: 'Heart Rate',
                      value: isPhoneMode ? '--' : '${_hr.toInt()}',
                      unit: isPhoneMode ? '' : 'BPM',
                      icon: Icons.favorite,
                      color: Colors.red,
                      gradient: const [
                        Color(0xFFEF5350),
                        Color(0xFFD32F2F)
                      ],
                    ),
                    MetricCard(
                      title: 'Motion',
                      value: _motion.toStringAsFixed(2),
                      unit: 'g',
                      icon: Icons.speed,
                      color: Colors.orange,
                      gradient: const [
                        Color(0xFFFFA726),
                        Color(0xFFF57C00)
                      ],
                    ),
                    MetricCard(
                      title: 'Gyroscope',
                      value: _gyro.toStringAsFixed(1),
                      unit: '°/s',
                      icon: Icons.sync,
                      color: Colors.purple,
                      gradient: const [
                        Color(0xFFAB47BC),
                        Color(0xFF7B1FA2)
                      ],
                    ),
                    MetricCard(
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

              // Mode Switch Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _toggleMode,
                  icon: Icon(
                    isPhoneMode ? Icons.phone_android : Icons.bluetooth,
                  ),
                  label: Text(
                    isPhoneMode
                        ? 'Mode: Phone Sensor'
                        : 'Mode: BLE Sensor',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isPhoneMode ? Colors.orange[700] : Colors.blue[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Record Data Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            RecordScreen(dataManager: _dataManager),
                      ),
                    );
                  },
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text(
                    'Record Data',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Plotter Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PlotterScreen(
                          dataStream: _dataManager.rawDataStream,
                        ),
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

              // Connect Button (only in BLE mode)
              if (showConnection)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _toggleConnection,
                    icon: Icon(
                      _isConnected
                          ? Icons.bluetooth_disabled
                          : Icons.bluetooth,
                    ),
                    label: Text(
                      _isConnected ? 'Disconnect' : 'Connect to ESP32',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isConnected ? Colors.red[400] : Colors.blue[600],
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

  String _getStatus() {
    if (_hr == 0 && _motion == 0 && _gyro == 0) return '--';
    if (_hr > 80) return 'Elevated';
    if (_motion > 1.5) return 'Moving';
    return 'Normal';
  }

  Color _getStatusColor() {
    if (_hr == 0 && _motion == 0 && _gyro == 0) return Colors.grey;
    if (_hr > 80) return Colors.orange;
    if (_motion > 1.5) return Colors.blue;
    return Colors.green;
  }

  List<Color> _getStatusGradient() {
    if (_hr == 0 && _motion == 0 && _gyro == 0) {
      return [Colors.grey[400]!, Colors.grey[600]!];
    }
    if (_hr > 80) return [Colors.orange[400]!, Colors.orange[800]!];
    if (_motion > 1.5) return [Colors.blue[400]!, Colors.blue[800]!];
    return [Colors.green[400]!, Colors.green[800]!];
  }
}