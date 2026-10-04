import 'package:audioplayers/audioplayers.dart';
import 'database_service.dart';

/// Structured alert event returned by [AlertService.checkAlert].
class AlertEvent {
  /// 'fall' or 'warning'
  final String alertClass;

  /// 'Fall Detected' / 'Abnormal Motion' / 'High HR' / 'Low HR'
  final String label;

  /// Human-readable message for display.
  final String message;

  final double hr;
  final double motion;
  final double gyro;

  AlertEvent({
    required this.alertClass,
    required this.label,
    required this.message,
    required this.hr,
    required this.motion,
    required this.gyro,
  });

  AlertRow toRow() {
    return AlertRow(
      alertClass: alertClass,
      label: label,
      message: message,
      timestamp: DateTime.now().toIso8601String(),
      hr: hr,
      motion: motion,
      gyro: gyro,
    );
  }
}

class AlertService {
  AudioPlayer? _audioPlayer;
  DateTime? _lastAlertTime;
  static const int _cooldownSeconds = 10;

  // ===== Tunable constants (Phase 2 refines these) =====

  /// Warning fires at this fraction of the fall threshold.
  static const double _softFactor = 0.85;

  /// Below this, motion is just noise — ignore.
  static const double _motionNoiseFloor = 0.3; // g (deviation)

  /// Below this, gyro is just noise — ignore.
  static const double _gyroNoiseFloor = 10.0; // °/s

  /// Above this HR, consider the user "active" (exercise explains it).
  static const double _activeHrFloor = 100; // bpm

  /// High HR warning bound (bpm) — used if baseline not set.
  static const double _highHrThreshold = 130;

  /// Low HR warning bound (bpm) — used if baseline not set.
  static const double _lowHrThreshold = 40;

  // ===== Defaults (used until a threshold is calculated) =====
  static const double _defaultAccelThreshold = 2.5; // g
  static const double _defaultGyroThreshold = 150.0; // °/s

  // ===== Active thresholds =====
  double _accelThreshold = _defaultAccelThreshold;
  double _gyroThreshold = _defaultGyroThreshold;

  // ===== HR baseline (personalized) =====
  double? _hrBaseline;

  double get accelThreshold => _accelThreshold;
  double get gyroThreshold => _gyroThreshold;
  double? get hrBaseline => _hrBaseline;

  AlertService({Threshold? threshold}) {
    if (threshold != null) {
      applyThreshold(threshold);
    }
  }

  void applyThreshold(Threshold threshold) {
    if (threshold.accelThreshold > 0) {
      _accelThreshold = threshold.accelThreshold;
    }
    if (threshold.gyroThreshold > 0) {
      _gyroThreshold = threshold.gyroThreshold;
    }
  }

  /// Set the personalized HR baseline.
  void applyHrBaseline(double baselineBpm) {
    if (baselineBpm > 0) {
      _hrBaseline = baselineBpm;
    }
  }

  void resetToDefaults() {
    _accelThreshold = _defaultAccelThreshold;
    _gyroThreshold = _defaultGyroThreshold;
    _hrBaseline = null;
  }

  /// Returns an [AlertEvent] if an alert triggered, null otherwise.
  AlertEvent? checkAlert(double hr, double motion, {double gyro = 0.0}) {
    AlertEvent? event;

    // ===== Noise floor — reject sensor junk =====
    final motionAboveNoise = motion > _motionNoiseFloor;
    final gyroAboveNoise = gyro > _gyroNoiseFloor;
    final hrValid = hr > 0;

    final accelExceeded = motion > _accelThreshold;
    final gyroExceeded = gyro > _gyroThreshold;

    final softAccel = _accelThreshold * _softFactor;
    final softGyro = _gyroThreshold * _softFactor;

    // ===== 1. Fall: motion AND gyro BOTH exceed thresholds =====
    // (noise floors guard against sensor junk)
    if (accelExceeded && gyroAboveNoise && gyroExceeded) {
      event = AlertEvent(
        alertClass: 'fall',
        label: 'Fall Detected',
        message: '⚠️ Fall Detected!',
        hr: hr,
        motion: motion,
        gyro: gyro,
      );
    }
    // ===== 2. Abnormal motion (near-fall / stumble) =====
    // Requires: motion or gyro above soft threshold
    //           AND above noise floor
    //           AND HR is NOT elevated (rules out exercise)
    else if (motionAboveNoise &&
        gyroAboveNoise &&
        (motion > softAccel || gyro > softGyro) &&
        (!hrValid || hr < _activeHrFloor)) {
      event = AlertEvent(
        alertClass: 'warning',
        label: 'Abnormal Motion',
        message: '⚠️ Abnormal Motion Detected',
        hr: hr,
        motion: motion,
        gyro: gyro,
      );
    }
    // ===== 3. HR warnings (only if user is NOT exercising) =====
    else if (hrValid && motion < _motionNoiseFloor) {
      final highBound = _hrBaseline != null
          ? _hrBaseline! + 50
          : _highHrThreshold;
      final lowBound = _hrBaseline != null
          ? _hrBaseline! - 30
          : _lowHrThreshold;

      if (hr > highBound) {
        event = AlertEvent(
          alertClass: 'warning',
          label: 'High HR',
          message: '⚠️ High Heart Rate: ${hr.toInt()} BPM',
          hr: hr,
          motion: motion,
          gyro: gyro,
        );
      } else if (hr < lowBound) {
        event = AlertEvent(
          alertClass: 'warning',
          label: 'Low HR',
          message: '⚠️ Low Heart Rate: ${hr.toInt()} BPM',
          hr: hr,
          motion: motion,
          gyro: gyro,
        );
      }
    }

    if (event == null) return null;

    // ===== Cooldown =====
    if (_lastAlertTime != null &&
        DateTime.now().difference(_lastAlertTime!).inSeconds <
            _cooldownSeconds) {
      return null;
    }

    _lastAlertTime = DateTime.now();
    _playSound();
    return event;
  }

  Future<void> _playSound() async {
    try {
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer!.play(AssetSource('sounds/alert.mp3'));
    } catch (e) {
      print("Sound error: $e");
    }
  }

  void dispose() {
    try {
      _audioPlayer?.dispose();
    } catch (e) {
      print("AudioPlayer dispose error: $e");
    }
    _audioPlayer = null;
  }
}