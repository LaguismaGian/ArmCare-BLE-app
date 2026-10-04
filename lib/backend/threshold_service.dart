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
  static const double _k = 1.0;

  /// Minimum number of Fall recordings required to calculate.
  static const int _minRecordings = 3;

  /// Noise floors — samples below these are ignored during peak detection.
  static const double _motionNoiseFloor = 0.3; // g (deviation)
  static const double _gyroNoiseFloor = 10.0; // °/s

  /// Sanity check — if the peak is below this, the recording is junk.
  static const double _minValidMotionPeak = 0.5; // g
  static const double _minValidGyroPeak = 20.0; // °/s

  Future<ThresholdResult> calculate() async {
    final recordings = await _db.getAllRecordings();

    final fallRecordings =
        recordings.where((r) => r.label.toLowerCase() == 'fall').toList();

    print('>>> DB has ${recordings.length} recordings, '
        '${fallRecordings.length} labeled fall');

    if (fallRecordings.length < _minRecordings) {
      return ThresholdResult(
        success: false,
        message: 'Need at least $_minRecordings Fall recordings '
            '(you have ${fallRecordings.length}).',
        recordingCount: fallRecordings.length,
      );
    }

    final peakMotions = <double>[];
    final peakGyros = <double>[];

    for (final rec in fallRecordings) {
      if (rec.id == null) continue;

      final samples = await _db.getSamplesForRecording(rec.id!);
      if (samples.isEmpty) {
        print('>>> rec id=${rec.id} has ZERO samples in DB');
        continue;
      }

      double maxMotion = 0.0;
      double maxGyro = 0.0;

      for (final s in samples) {
        // recording_service.dart already stores the bias-corrected
        // deviation in `ax` (phone + BLE both).
        final motion = s.ax.abs();

        final gyroMag = sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz);

        if (motion > _motionNoiseFloor && motion > maxMotion) {
          maxMotion = motion;
        }
        if (gyroMag > _gyroNoiseFloor && gyroMag > maxGyro) {
          maxGyro = gyroMag;
        }
      }

      print('>>> rec id=${rec.id} mode=${rec.mode} '
          'samples=${samples.length} '
          'maxMotion=${maxMotion.toStringAsFixed(3)} '
          'maxGyro=${maxGyro.toStringAsFixed(1)}');

      if (maxMotion >= _minValidMotionPeak) {
        peakMotions.add(maxMotion);
      } else {
        print('>>>   motion rejected (need >= $_minValidMotionPeak)');
      }

      if (maxGyro >= _minValidGyroPeak) {
        peakGyros.add(maxGyro);
      } else {
        print('>>>   gyro rejected (need >= $_minValidGyroPeak)');
      }
    }

    print('>>> AFTER FILTER: peakMotions=${peakMotions.length} '
        'peakGyros=${peakGyros.length}');

    if (peakMotions.length < _minRecordings) {
      return ThresholdResult(
        success: false,
        message: 'Not enough valid recordings (${peakMotions.length} of '
            '$_minRecordings). Peak motion too low or samples empty.\n\n'
            'Try harder drops on a hard surface.',
        recordingCount: peakMotions.length,
      );
    }

    final accelThreshold = _computeThreshold(peakMotions);
    final gyroThreshold = _computeThreshold(peakGyros);

    final threshold = Threshold(
      accelThreshold: accelThreshold,
      gyroThreshold: gyroThreshold,
      timestamp: DateTime.now().toIso8601String(),
    );

    await _db.saveThreshold(threshold);

    return ThresholdResult(
      success: true,
      message: 'Threshold calculated from ${peakMotions.length} falls.\n'
          'Accel: ${accelThreshold.toStringAsFixed(2)} g\n'
          'Gyro: ${gyroThreshold.toStringAsFixed(1)} °/s',
      recordingCount: peakMotions.length,
      threshold: threshold,
    );
  }

  Future<Threshold?> loadSaved() async {
    return _db.getLatestThreshold();
  }

  double _computeThreshold(List<double> peaks) {
    if (peaks.isEmpty) return 0.0;

    final mean = peaks.reduce((a, b) => a + b) / peaks.length;
    final variance = peaks
            .map((p) => pow(p - mean, 2))
            .reduce((a, b) => a + b) /
        peaks.length;
    final stdDev = sqrt(variance);

    final result = mean - _k * stdDev;
    return result > 0 ? result : 0.0;
  }
}