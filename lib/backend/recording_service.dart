import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'database_service.dart';
import 'data_manager.dart';

class RecordingSample {
  final int timestampMs;
  final double ax, ay, az;
  final double gx, gy, gz;

  RecordingSample({
    required this.timestampMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestampMs': timestampMs,
      'ax': ax,
      'ay': ay,
      'az': az,
      'gx': gx,
      'gy': gy,
      'gz': gz,
    };
  }
}

class RecordingService {
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  SensorMode _currentMode = SensorMode.ble;
  SensorMode get currentMode => _currentMode;

  final List<RecordingSample> _samples = [];
  List<RecordingSample> get samples => List.unmodifiable(_samples);

  DateTime? _startTime;
  Timer? _autoStopTimer;
  Timer? _tickerTimer;

  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;
  StreamSubscription? _bleSub;

  final DataManager _dataManager;
  final DatabaseService _db = DatabaseService.instance;

  // Streams for UI
  final StreamController<RecordingSample> _sampleController =
      StreamController<RecordingSample>.broadcast();
  Stream<RecordingSample> get sampleStream => _sampleController.stream;

  final StreamController<int> _timerController =
      StreamController<int>.broadcast();
  Stream<int> get timerStream => _timerController.stream;

  final StreamController<bool> _stateController =
      StreamController<bool>.broadcast();
  Stream<bool> get stateStream => _stateController.stream;

  // Latest phone sensor values
  double _ax = 0, _ay = 0, _az = 0;
  double _gx = 0, _gy = 0, _gz = 0;

  RecordingService(this._dataManager);

  void setMode(SensorMode mode) {
    _currentMode = mode;
  }

  // ===== START RECORDING =====
  Future<bool> startRecording({int maxSeconds = 10}) async {
    if (_isRecording) return false;

    _samples.clear();
    _isRecording = true;
    _stateController.add(true);
    _startTime = DateTime.now();

    // Ticker timer
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_startTime!).inMilliseconds;
      _timerController.add(elapsed);
    });

    // Auto-stop
    _autoStopTimer = Timer(Duration(seconds: maxSeconds), () {
      if (_isRecording) stopRecording();
    });

    // Subscribe based on mode
    if (_currentMode == SensorMode.phone) {
      _subscribePhoneSensors();
    } else {
      _subscribeBleSensors();
    }

    return true;
  }

  // ===== PHONE SENSORS =====
  void _subscribePhoneSensors() {
    _accelSub = accelerometerEvents.listen((event) {
      if (!_isRecording) return;
      _ax = event.x / 9.81;
      _ay = event.y / 9.81;
      _az = event.z / 9.81;
      _recordSample();
    });

    _gyroSub = gyroscopeEvents.listen((event) {
      if (!_isRecording) return;
      _gx = event.x * (180 / 3.141592653589793);
      _gy = event.y * (180 / 3.141592653589793);
      _gz = event.z * (180 / 3.141592653589793);
    });
  }

  // ===== BLE SENSORS =====
  void _subscribeBleSensors() {
    _bleSub = _dataManager.rawDataStream.listen((raw) {
      if (!_isRecording) return;

      final parts = raw.split(',');
      if (parts.length < 3) return;

      // BLE sends combined Motion + Gyro (scalars, no separate X/Y/Z).
      // Store motion only in ax so magnitude = |motion| (not √3·motion).
      final motion = double.tryParse(parts[1]) ?? 0;
      final gyro = double.tryParse(parts[2]) ?? 0;

      _ax = motion;
      _ay = 0;
      _az = 0;
      _gx = gyro;
      _gy = 0;
      _gz = 0;
      _recordSample();
    });
  }

  void _recordSample() {
    final elapsed = DateTime.now().difference(_startTime!).inMilliseconds;
    final sample = RecordingSample(
      timestampMs: elapsed,
      ax: _ax,
      ay: _ay,
      az: _az,
      gx: _gx,
      gy: _gy,
      gz: _gz,
    );
    _samples.add(sample);
    _sampleController.add(sample);
  }

  // ===== STOP RECORDING =====
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _isRecording = false;
    _stateController.add(false);
    _autoStopTimer?.cancel();
    _tickerTimer?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _bleSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _bleSub = null;

    final durationMs = _samples.isEmpty ? 0 : _samples.last.timestampMs;

    // Save as "Fall" always
    final recording = Recording(
      label: 'Fall',
      mode: _currentMode == SensorMode.phone ? 'phone' : 'ble',
      durationMs: durationMs,
      sampleCount: _samples.length,
      timestamp: DateTime.now().toIso8601String(),
    );

    try {
      final newId = await _db.insertRecording(recording);
      await _db.insertSamples(newId, _samples);
      print('Recording saved: id=$newId, samples=${_samples.length}');
    } catch (e, stack) {
      print('Failed to save recording: $e');
      print(stack);
    }
  }

  // ===== CANCEL (discard) =====
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    _isRecording = false;
    _stateController.add(false);
    _autoStopTimer?.cancel();
    _tickerTimer?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _bleSub?.cancel();
    _samples.clear();
  }

  void dispose() {
    _autoStopTimer?.cancel();
    _tickerTimer?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _bleSub?.cancel();
    _sampleController.close();
    _timerController.close();
    _stateController.close();
  }
}