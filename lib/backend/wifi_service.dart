import 'dart:async';
import 'dart:io';

class WifiService {
  static const int TCP_PORT = 3333;
  static const Duration CONNECT_TIMEOUT = Duration(seconds: 5);

  Socket? _socket;
  String? _espIp;

  final StreamController<String> _dataController =
      StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataController.stream;

  StreamSubscription? _socketSub;
  String _lineBuffer = '';

  String? get espIp => _espIp;

  /// Connect to the ESP32 at [ip] on the standard TCP port.
  /// Returns true on success.
  Future<bool> connect(String ip) async {
    await disconnect();

    try {
      print('WiFi: Connecting to $ip:$TCP_PORT');
      _socket = await Socket.connect(
        ip,
        TCP_PORT,
        timeout: CONNECT_TIMEOUT,
      );
      _espIp = ip;
      print('WiFi: Connected');

      // Listen for incoming data
      _socketSub = _socket!.listen(
        (data) {
          _lineBuffer += String.fromCharCodes(data);

          // ESP32 uses println() → lines end with \n
          while (_lineBuffer.contains('\n')) {
            final idx = _lineBuffer.indexOf('\n');
            final line = _lineBuffer.substring(0, idx).trim();
            _lineBuffer = _lineBuffer.substring(idx + 1);

            if (line.isNotEmpty) {
              print('WiFi data: $line');
              _dataController.add(line);
            }
          }
        },
        onError: (err) {
          print('WiFi socket error: $err');
          _cleanup();
        },
        onDone: () {
          print('WiFi socket closed');
          _cleanup();
        },
        cancelOnError: true,
      );

      return true;
    } catch (e) {
      print('WiFi connect failed: $e');
      _cleanup();
      return false;
    }
  }

  Future<void> disconnect() async {
    await _socketSub?.cancel();
    _socketSub = null;

    try {
      await _socket?.close();
      _socket?.destroy();
    } catch (_) {}

    _socket = null;
    _espIp = null;
    _lineBuffer = '';
  }

  bool isConnected() {
    return _socket != null;
  }

  void _cleanup() {
    _socket = null;
    _espIp = null;
    _lineBuffer = '';
  }

  void dispose() {
    disconnect();
    _dataController.close();
  }
}