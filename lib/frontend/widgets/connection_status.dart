import 'package:flutter/material.dart';

class ConnectionStatus extends StatelessWidget {
  final bool isConnected;
  final bool isScanning;

  const ConnectionStatus({
    super.key,
    required this.isConnected,
    required this.isScanning,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected ? Colors.green[300]! : Colors.red[300]!,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.check_circle : Icons.error_outline,
            color: isConnected ? Colors.green : Colors.red,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isConnected ? 'Connected to ESP32' : 'Disconnected',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isConnected ? Colors.green[800] : Colors.red[800],
              ),
            ),
          ),
          if (isScanning)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue,
              ),
            ),
        ],
      ),
    );
  }
}