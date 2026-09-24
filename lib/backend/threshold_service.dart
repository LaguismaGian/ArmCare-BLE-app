import 'dart:math';
import 'database_service.dart';

/// Result of a threshold calculation attempt.
class ThresholdResult {
  final bool success;
  final String message;
  final int recordingCount;
  final Threshold? threshold;

  ThresholdResult({
    required this.success,
    required this.message,
    required this.recordingCount,
    this.threshold,
  });
}

class ThresholdService {
  final DatabaseService _db = DatabaseService.instance;

  /// How many std-devs below the mean fall to set the threshold.
  /// Higher = more sensitive (more false positives).
  /// Lower  = stricter (may miss real falls).
  static const double _k = 1.0;

  /// Minimum number of Fall recordings required to calculate.
  static const int _minRecordings = 3;

  /// Reads all Fall recordings, computes thresholds, saves them.
  Future<ThresholdResult> calculate() async {
    final recordings = await _db.getAllRecordings();

    // Only Fall recordings matter
    final fallRecordings =
        recordings.where((r) => r.label.toLowerCase() == 'fall').toList();

    if (fallRecordings.length < _minRecordings) {
      return ThresholdResult(
        success: false,
        message: 'Need at least $_minRecordings Fall recordings '
            '(you have ${fallRecordings.length}).',
        recordingCount: fallRecordings.length,
      );
    }

    final peakAccels = <double>[];
    final peakGyros = <double>[];

    for (final rec in fallRecordings) {
      if (rec.id == null) continue;

      final samples = await _db.getSamplesForRecording(rec.id!);
      if (samples.isEmpty) continue;

      double maxAccel = 0.0;
      double maxGyro = 0.0;

      for (final s in samples) {
        final accelMag = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
        final gyroMag = sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz);

        if (accelMag > maxAccel) maxAccel = accelMag;
        if (gyroMag > maxGyro) maxGyro = gyroMag;
      }

      // Only count recordings that actually produced data
      if (maxAccel > 0) peakAccels.add(maxAccel);
      if (maxGyro > 0) peakGyros.add(maxGyro);
    }

    if (peakAccels.length < _minRecordings) {
      return ThresholdResult(
        success: false,
        message: 'Not enough valid samples in recordings. '
            'Try recording again.',
        recordingCount: peakAccels.length,
      );
    }

    final accelThreshold = _computeThreshold(peakAccels);
    final gyroThreshold = _computeThreshold(peakGyros);

    final threshold = Threshold(
      accelThreshold: accelThreshold,
      gyroThreshold: gyroThreshold,
      timestamp: DateTime.now().toIso8601String(),
    );

    await _db.saveThreshold(threshold);

    return ThresholdResult(
      success: true,
      message: 'Threshold calculated from ${peakAccels.length} falls.\n'
          'Accel: ${accelThreshold.toStringAsFixed(2)} g\n'
          'Gyro: ${gyroThreshold.toStringAsFixed(1)} °/s',
      recordingCount: peakAccels.length,
      threshold: threshold,
    );
  }

  /// Convenience: read the currently-saved threshold, or null if none.
  Future<Threshold?> loadSaved() async {
    return _db.getLatestThreshold();
  }

  /// mean − k · stdDev, clamped to be positive.
  double _computeThreshold(List<double> peaks) {
    if (peaks.isEmpty) return 0.0;

    final mean = peaks.reduce((a, b) => a + b) / peaks.length;
    final variance =
        peaks.map((p) => pow(p - mean, 2)).reduce((a, b) => a + b) /
            peaks.length;
    final stdDev = sqrt(variance);

    final result = mean - _k * stdDev;
    return result > 0 ? result : 0.0;
  }
}