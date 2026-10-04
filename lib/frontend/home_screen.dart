import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../backend/data_manager.dart';
import '../backend/threshold_service.dart';
import '../backend/database_service.dart';
import 'widgets/metric_card.dart';
import 'widgets/connection_status.dart';
import 'widgets/battery_indicator.dart';
import 'widgets/alert_history.dart';
import 'plotter_screen.dart';
import 'record_screen.dart';
import 'contacts_screen.dart';
import 'wifi_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DataManager _dataManager = DataManager();
  final ThresholdService _thresholdService = ThresholdService();

  double _hr = 0.0;
  double _motion = 0.0;
  double _gyro = 0.0;
  bool _isConnected = false;
  bool _isScanning = false;
  SensorMode _currentMode = SensorMode.ble;

  double? _accelThreshold;
  double? _gyroThreshold;
  bool _isCalibrating = false;

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

    _dataManager.alertStream.listen((event) {
      _showAlertDialog(event.message);
    });

    _dataManager.connectionStream.listen((connected) {
      setState(() => _isConnected = connected);
    });

    _dataManager.modeStream.listen((mode) {
      setState(() => _currentMode = mode);
    });

    _loadThresholdDisplay();
  }

  Future<void> _loadThresholdDisplay() async {
    final saved = await _thresholdService.loadSaved();
    if (!mounted) return;
    setState(() {
      _accelThreshold = saved?.accelThreshold;
      _gyroThreshold = saved?.gyroThreshold;
    });
  }

  void _requestPermissions() async {
    try {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    } catch (e) {
      print('Permission request error: $e');
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

  // ===== CALIBRATION =====

  Future<void> _calibrate() async {
    setState(() => _isCalibrating = true);

    final result = await _thresholdService.calculate();

    if (result.success) {
      await _dataManager.refreshThreshold();
    }

    if (!mounted) return;
    setState(() {
      _isCalibrating = false;
      if (result.threshold != null) {
        _accelThreshold = result.threshold!.accelThreshold;
        _gyroThreshold = result.threshold!.gyroThreshold;
      }
    });

    _showCalibrationDialog(result);
  }

  void _showCalibrationDialog(ThresholdResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text(result.success ? '✅ Calibrated' : '⚠️ Calibration Failed'),
        content: Text(result.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmResetCalibration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Calibration?'),
        content: const Text(
            'This will delete all Fall recordings and reset the threshold.\n\n'
            'Alert history and emergency contacts will be kept.\n\n'
            'You will need to record fresh Fall data and calibrate again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _resetCalibration();
    }
  }

  Future<void> _resetCalibration() async {
    await DatabaseService.instance.clearCalibration();
    await _dataManager.refreshThreshold();
    await _loadThresholdDisplay();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calibration reset. Record fresh Fall data.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ===== CONNECTION =====

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

  // ===== MODE SWITCHING =====

  void _cycleMode() {
    final next = switch (_currentMode) {
      SensorMode.ble => SensorMode.phone,
      SensorMode.phone => SensorMode.wifi,
      SensorMode.wifi => SensorMode.ble,
    };
    _dataManager.setMode(next);
  }

  String _modeLabel() {
    switch (_currentMode) {
      case SensorMode.ble:
        return 'Mode: BLE Sensor';
      case SensorMode.phone:
        return 'Mode: Phone Sensor';
      case SensorMode.wifi:
        return 'Mode: Wi-Fi Sensor';
    }
  }

  IconData _modeIcon() {
    switch (_currentMode) {
      case SensorMode.ble:
        return Icons.bluetooth;
      case SensorMode.phone:
        return Icons.phone_android;
      case SensorMode.wifi:
        return Icons.wifi;
    }
  }

  Color _modeColor() {
    switch (_currentMode) {
      case SensorMode.ble:
        return Colors.blue[700]!;
      case SensorMode.phone:
        return Colors.orange[700]!;
      case SensorMode.wifi:
        return Colors.green[700]!;
    }
  }

  // ===== WI-FI SETUP =====

  Future<void> _openWifiSetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WifiSetupScreen(
          onConnected: (ip) async {
            print('WiFi: got IP $ip, connecting...');
            final ok = await _dataManager.connectWifi(ip);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? 'Wi-Fi connected to $ip'
                      : 'Wi-Fi connected but app socket failed'),
                  backgroundColor: ok ? Colors.green : Colors.orange,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    try {
      _dataManager.dispose();
    } catch (e) {
      print('DataManager dispose error: $e');
    }
    super.dispose();
  }

  // ===== BUILD =====

  @override
  Widget build(BuildContext context) {
    final isPhoneMode = _currentMode == SensorMode.phone;
    final isWifiMode = _currentMode == SensorMode.wifi;
    final showConnection = !isPhoneMode;
    final hasThreshold = _accelThreshold != null && _accelThreshold! > 0;

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
          if (showConnection && !isWifiMode)
            IconButton(
              icon: Icon(
                _isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color:
                    _isConnected ? Colors.lightGreenAccent : Colors.white70,
              ),
              onPressed: _toggleConnection,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ===== SCROLLABLE MIDDLE =====
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildThresholdChip(hasThreshold: hasThreshold),
                    const SizedBox(height: 8),

                    if (showConnection) ...[
                      ConnectionStatus(
                        isConnected: _isConnected,
                        isScanning: _isScanning,
                      ),
                      const SizedBox(height: 8),
                    ],

                    if (isPhoneMode) ...[
                      _buildPhoneModeBanner(),
                      const SizedBox(height: 8),
                    ],

                    if (isWifiMode && _isConnected) ...[
                      _buildWifiConnectedBanner(),
                      const SizedBox(height: 8),
                    ],

                    const SizedBox(height: 8),

                    // ===== METRIC GRID =====
                    GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.1,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
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

                    const SizedBox(height: 20),

                    // ===== ALERT HISTORY =====
                    AlertHistory(dataManager: _dataManager),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ===== FIXED BOTTOM BUTTONS =====
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Calibrate Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isCalibrating ? null : _calibrate,
                      icon: _isCalibrating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.tune),
                      label: Text(
                        _isCalibrating
                            ? 'Calculating...'
                            : 'Calibrate from Falls',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                  // Reset Calibration (only if threshold set)
                  if (hasThreshold) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: TextButton.icon(
                        onPressed: _confirmResetCalibration,
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: const Text(
                          'Reset Calibration',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red[700],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Mode Switch Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _cycleMode,
                      icon: Icon(_modeIcon()),
                      label: Text(
                        _modeLabel(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _modeColor(),
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
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                RecordScreen(dataManager: _dataManager),
                          ),
                        );
                        _loadThresholdDisplay();
                      },
                      icon: const Icon(Icons.fiber_manual_record),
                      label: const Text(
                        'Record Data',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
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
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
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

                  // Emergency Contacts Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ContactsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.contact_phone),
                      label: const Text(
                        'Emergency Contacts',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                  // BLE Connect Button (only in BLE mode)
                  if (_currentMode == SensorMode.ble) ...[
                    const SizedBox(height: 8),
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
                          backgroundColor: _isConnected
                              ? Colors.red[400]
                              : Colors.blue[600],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                        ),
                      ),
                    ),
                  ],

                  // Wi-Fi Setup Button (only in Wi-Fi mode)
                  if (isWifiMode) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _openWifiSetup,
                        icon: const Icon(Icons.settings_ethernet),
                        label: Text(
                          _isConnected
                              ? 'Reconfigure Wi-Fi'
                              : 'Set up Wi-Fi',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== THRESHOLD CHIP =====

  Widget _buildThresholdChip({required bool hasThreshold}) {
    final text = hasThreshold
        ? '🎯 Accel ${_accelThreshold!.toStringAsFixed(2)} g  •  '
            'Gyro ${_gyroThreshold!.toStringAsFixed(0)} °/s'
        : '🎯 No threshold set — calibrate from Falls first';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hasThreshold ? Colors.teal[50] : Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasThreshold ? Colors.teal[300]! : Colors.grey[400]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasThreshold ? Icons.check_circle_outline : Icons.info_outline,
            size: 18,
            color: hasThreshold ? Colors.teal[700] : Colors.grey[700],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hasThreshold ? Colors.teal[900] : Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== PHONE MODE BANNER =====

  Widget _buildPhoneModeBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[300]!, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_android, color: Colors.orange[800], size: 24),
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
    );
  }

  // ===== WI-FI CONNECTED BANNER =====

  Widget _buildWifiConnectedBanner() {
    final ip = _dataManager.espIp ?? '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[300]!, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi, color: Colors.green[800], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wi-Fi Connected',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[800],
                  ),
                ),
                Text(
                  'ESP32 at $ip',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== STATUS HELPERS =====

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