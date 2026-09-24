import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../backend/data_manager.dart';
import '../backend/threshold_service.dart';
import '../backend/database_service.dart';
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
  final ThresholdService _thresholdService = ThresholdService();

  double _hr = 0.0;
  double _motion = 0.0;
  double _gyro = 0.0;
  bool _isConnected = false;
  bool _isScanning = false;
  SensorMode _currentMode = SensorMode.ble;

  // Cached threshold for display
  double? _accelThreshold;
  double? _gyroThreshold;
  bool _isCalibrating = false;

  final int _battery = 85;

  @override
  void initState() {
    super.initState();
    print('>>> HomeScreen.initState start');

    print('>>> about to request permissions');
    _requestPermissions();
    print('>>> permissions requested (async)');

    print('>>> about to listen dataStream');
    _dataManager.dataStream.listen((data) {
      setState(() {
        _hr = data.hr;
        _motion = data.motion;
        _gyro = data.gyro;
      });
    });

    print('>>> about to listen alertStream');
    _dataManager.alertStream.listen((message) {
      _showAlertDialog(message);
    });

    print('>>> about to listen connectionStream');
    _dataManager.connectionStream.listen((connected) {
      setState(() => _isConnected = connected);
    });

    print('>>> about to listen modeStream');
    _dataManager.modeStream.listen((mode) {
      setState(() => _currentMode = mode);
    });

    print('>>> about to load threshold display');
    _loadThresholdDisplay();
    print('>>> HomeScreen.initState end');
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

  // ===== CALIBRATION =====

  Future<void> _calibrate() async {
    setState(() => _isCalibrating = true);

    final result = await _thresholdService.calculate();

    // Refresh DataManager's live alert thresholds
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
        title: Text(result.success ? '✅ Calibrated' : '⚠️ Calibration Failed'),
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

  // ===== BUILD =====

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
              _buildThresholdChip(),
              const SizedBox(height: 8),

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

              const SizedBox(height: 8),

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

  // ===== THRESHOLD CHIP =====

  Widget _buildThresholdChip() {
    final hasThreshold = _accelThreshold != null && _accelThreshold! > 0;

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