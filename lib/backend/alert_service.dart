import 'package:audioplayers/audioplayers.dart';

class AlertService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  DateTime? _lastAlertTime;
  static const int _cooldownSeconds = 10;

  /// Returns alert message if alert triggered, null otherwise
  String? checkAlert(double hr, double motion) {
    String? message;

    if (motion > 2.5) {
      message = "⚠️ Fall Detected!";
    } else if (hr > 130) {
      message = "⚠️ High Heart Rate: ${hr.toInt()} BPM";
    } else if (hr > 0 && hr < 40) {
      message = "⚠️ Low Heart Rate: ${hr.toInt()} BPM";
    }

    if (message == null) return null;

    // Cooldown check
    if (_lastAlertTime != null &&
        DateTime.now().difference(_lastAlertTime!).inSeconds < _cooldownSeconds) {
      return null;
    }

    _lastAlertTime = DateTime.now();
    _playSound();
    return message;
  }

  void _playSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/alert.mp3'));
    } catch (e) {
      print("Sound error: $e");
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}