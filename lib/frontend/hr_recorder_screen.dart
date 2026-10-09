import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../backend/database_service.dart';

class HrRecorderScreen extends StatefulWidget {
  const HrRecorderScreen({super.key});

  @override
  State<HrRecorderScreen> createState() => _HrRecorderScreenState();
}

class _HrRecorderScreenState extends State<HrRecorderScreen> {
  // ===== BLE UUIDS (must match ESP32 firmware) =====
  static const String SERVICE_UUID =
      "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String NOTIFY_UUID =
      "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String DEVICE_NAME = "ArmCare_ESP32";

  static const int RECORD_DURATION_S = 60;
  static const int MIN_DURATION_S = 10;   // min seconds before save is allowed

  // ===== STATE =====
  bool _isRecording = false;
  bool _isSaving = false;
  int _elapsedS = 0;
  double _liveBpm = 0;
  final List<double> _bpmSamples = [];

  // BLE objects
  BluetoothDevice? _device;
  StreamSubscription? _notifySub;
  StreamSubscription? _scanSub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _connectAndStart();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _notifySub?.cancel();
    _scanSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  // ===== CONNECT + START =====

  Future<void> _connectAndStart() async {
    // 1. Find ESP32 over BLE
    final completer = Completer<BluetoothDevice?>();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
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

    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 300));

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      _device = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );
    } catch (_) {}

    await _scanSub?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    if (_device == null) {
      _showError('ESP32 not found. Power it on and try again.');
      return;
    }

    try {
      await _device!.connect();
      final services = await _device!.discoverServices();

      BluetoothCharacteristic? notifyChar;
      for (final s in services) {
        if (s.uuid.toString().toUpperCase() == SERVICE_UUID.toUpperCase()) {
          for (final c in s.characteristics) {
            if (c.uuid.toString().toUpperCase() == NOTIFY_UUID.toUpperCase()) {
              notifyChar = c;
              break;
            }
          }
        }
      }

      if (notifyChar == null) {
        _showError('ESP32 HR characteristic not found.');
        return;
      }

      // Subscribe BEFORE enabling notifications
      _notifySub = notifyChar.onValueReceived.listen((value) {
        final raw = String.fromCharCodes(value);
        _handleData(raw);
      });

      await notifyChar.setNotifyValue(true);

      // Start recording
      setState(() {
        _isRecording = true;
        _elapsedS = 0;
        _bpmSamples.clear();
      });

      // Ticker every second
      _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!_isRecording) {
          t.cancel();
          return;
        }
        setState(() => _elapsedS++);
        if (_elapsedS >= RECORD_DURATION_S) {
          _finishRecording();
        }
      });
    } catch (e) {
      _showError('Connection failed: $e');
    }
  }

  void _handleData(String raw) {
    // Format: "BPM,Accel,Gyro,RawIR"
    final parts = raw.split(',');
    if (parts.isEmpty) return;

    final bpm = double.tryParse(parts[0]) ?? 0;

    // Only collect valid BPM readings
    if (bpm > 30 && bpm < 220) {
      _bpmSamples.add(bpm);
      if (mounted) setState(() => _liveBpm = bpm);
    }
  }

  // ===== FINISH =====

  Future<void> _finishRecording() async {
    _ticker?.cancel();
    setState(() => _isRecording = false);

    if (_elapsedS < MIN_DURATION_S || _bpmSamples.isEmpty) {
      _showError('Not enough data. Record at least $MIN_DURATION_S seconds.');
      return;
    }

    setState(() => _isSaving = true);

    // Median BPM
    final sorted = List<double>.from(_bpmSamples)..sort();
    final median = sorted.length.isOdd
        ? sorted[sorted.length ~/ 2]
        : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;

    final session = HrSession(
      avgBpm: median,
      sampleCount: _bpmSamples.length,
      durationMs: _elapsedS * 1000,
      timestamp: DateTime.now().toIso8601String(),
    );

    await DatabaseService.instance.insertHrSession(session);

    if (!mounted) return;
    setState(() => _isSaving = false);

    // Show result dialog
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('✅ Recording Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${median.toStringAsFixed(0)} BPM',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            Text('Duration: ${_elapsedS}s'),
            Text('Samples: ${_bpmSamples.length}'),
            const Text('Method: median'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (mounted) Navigator.pop(context);
  }

  Future<void> _cancelRecording() async {
    if (_elapsedS < MIN_DURATION_S) {
      // Too short — discard
      _ticker?.cancel();
      _notifySub?.cancel();
      await _device?.disconnect();
      if (mounted) Navigator.pop(context);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Recording?'),
        content: Text(
            'Save current reading? (${_elapsedS}s recorded, ${_bpmSamples.length} samples)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _finishRecording();
    } else {
      _ticker?.cancel();
      _notifySub?.cancel();
      await _device?.disconnect();
      if (mounted) Navigator.pop(context);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
    Navigator.pop(context);
  }

  // ===== BUILD =====

  @override
  Widget build(BuildContext context) {
    final progress = _elapsedS / RECORD_DURATION_S;
    final remaining = RECORD_DURATION_S - _elapsedS;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('HR Recording'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        leading: _isRecording
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _cancelRecording,
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // ===== LIVE BPM =====
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _liveBpm > 0
                        ? [Colors.red[400]!, Colors.red[800]!]
                        : [Colors.grey[400]!, Colors.grey[600]!],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_liveBpm > 0 ? Colors.red : Colors.grey)
                          .withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _liveBpm > 0
                            ? _liveBpm.toStringAsFixed(0)
                            : '--',
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'BPM',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // ===== PROGRESS =====
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey[300],
                color: Colors.red[700],
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              Text(
                _isSaving
                    ? 'Saving...'
                    : _isRecording
                        ? '${_elapsedS}s elapsed · ${remaining}s remaining'
                        : 'Preparing...',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),

              const SizedBox(height: 20),

              // ===== SAMPLE COUNT =====
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timeline, size: 18, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Text(
                      '${_bpmSamples.length} samples collected',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ===== INSTRUCTION =====
              if (_isRecording)
                Text(
                  'Keep your finger on the sensor.\n'
                  'Stay still for the most accurate reading.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),

              const SizedBox(height: 16),

              // ===== CANCEL / STOP BUTTON =====
              if (_isRecording)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _cancelRecording,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop & Save'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[700],
                      side: BorderSide(color: Colors.red[300]!),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}