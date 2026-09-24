import 'package:audioplayers/audioplayers.dart';
import 'database_service.dart';

class AlertService {
  AudioPlayer? _audioPlayer;
  DateTime? _lastAlertTime;
  static const int _cooldownSeconds = 10;

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

  /// Update the thresholds used for alerts.
  void applyThreshold(Threshold threshold) {
    if (threshold.accelThreshold > 0) {
      _accelThreshold = threshold.accelThreshold;
    }
    if (threshold.gyroThreshold > 0) {
      _gyroThreshold = threshold.gyroThreshold;
    }
  }

  /// Revert back to built-in defaults (e.g. if user clears calibration).
  void resetToDefaults() {
    _accelThreshold = _defaultAccelThreshold;
    _gyroThreshold = _defaultGyroThreshold;
  }

  /// Returns alert message if alert triggered, null otherwise.
  ///
  /// [motion] is the fused acceleration magnitude (g).
  /// [gyro]   is the fused gyro magnitude (°/s) — pass 0 if unknown.
  String? checkAlert(double hr, double motion, {double gyro = 0.0}) {
    String? message;

    // Fall detection: accel AND gyro must exceed their thresholds.
    // This reduces false positives (a hard wrist tap may spike accel
    // but won't spin the gyro).
    final accelExceeded = motion > _accelThreshold;
    final gyroExceeded = gyro > _gyroThreshold;

    if (accelExceeded && (gyro == 0.0 || gyroExceeded)) {
      message = "⚠️ Fall Detected!";
    } else if (hr > 130) {
      message = "⚠️ High Heart Rate: ${hr.toInt()} BPM";
    } else if (hr > 0 && hr < 40) {
      message = "⚠️ Low Heart Rate: ${hr.toInt()} BPM";
    }

    if (message == null) return null;

    // Cooldown check
    if (_lastAlertTime != null &&
        DateTime.now().difference(_lastAlertTime!).inSeconds <
            _cooldownSeconds) {
      return null;
    }

    _lastAlertTime = DateTime.now();
    _playSound();
    return message;
  }

  /// Lazily create the AudioPlayer on first use — avoids a native crash
  /// at startup on some Android devices (OPPO/ColorOS especially) if the
  /// media pipeline isn't ready when the AlertService is constructed.
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