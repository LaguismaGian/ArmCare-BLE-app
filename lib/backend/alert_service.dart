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

  // ===== Tunable constants (Phase 2 will refine these) =====

  /// Abnormal-motion multiplier — alert fires at this fraction of the
  /// fall threshold. Lower = more sensitive, higher = stricter.
  static const double _softFactor = 0.7;

  /// High heart-rate warning bound (bpm).
  static const double _highHrThreshold = 130;

  /// Low heart-rate warning bound (bpm).
  static const double _lowHrThreshold = 40;

  // ===== Defaults (used until a threshold is calculated) =====
  static const double _defaultAccelThreshold = 2.5; // g
  static const double _defaultGyroThreshold = 150.0; // °/s

  // ===== Active thresholds =====
  double _accelThreshold = _defaultAccelThreshold;
  double _gyroThreshold = _defaultGyroThreshold;

  double get accelThreshold => _accelThreshold;
  double get gyroThreshold => _gyroThreshold;

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

  void resetToDefaults() {
    _accelThreshold = _defaultAccelThreshold;
    _gyroThreshold = _defaultGyroThreshold;
  }

  /// Returns an [AlertEvent] if an alert triggered, null otherwise.
  ///
  /// [motion] is fused acceleration magnitude (g).
  /// [gyro]   is fused gyro magnitude (°/s) — pass 0 if unknown.
  AlertEvent? checkAlert(double hr, double motion, {double gyro = 0.0}) {
    AlertEvent? event;

    final accelExceeded = motion > _accelThreshold;
    final gyroExceeded = gyro > _gyroThreshold;

    final softAccel = _accelThreshold * _softFactor;
    final softGyro = _gyroThreshold * _softFactor;

    final softMotionExceeded =
        motion > softAccel || (gyro > 0 && gyro > softGyro);

    // ===== 1. Fall: accel AND gyro both exceed their thresholds =====
    if (accelExceeded && (gyro == 0.0 || gyroExceeded)) {
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
    else if (softMotionExceeded) {
      event = AlertEvent(
        alertClass: 'warning',
        label: 'Abnormal Motion',
        message: '⚠️ Abnormal Motion Detected',
        hr: hr,
        motion: motion,
        gyro: gyro,
      );
    }
    // ===== 3. Heart-rate warnings =====
    else if (hr > _highHrThreshold) {
      event = AlertEvent(
        alertClass: 'warning',
        label: 'High HR',
        message: '⚠️ High Heart Rate: ${hr.toInt()} BPM',
        hr: hr,
        motion: motion,
        gyro: gyro,
      );
    } else if (hr > 0 && hr < _lowHrThreshold) {
      event = AlertEvent(
        alertClass: 'warning',
        label: 'Low HR',
        message: '⚠️ Low Heart Rate: ${hr.toInt()} BPM',
        hr: hr,
        motion: motion,
        gyro: gyro,
      );
    }

    if (event == null) return null;

    // ===== Cooldown check =====
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