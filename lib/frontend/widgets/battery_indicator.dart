import 'package:flutter/material.dart';

class BatteryIndicator extends StatelessWidget {
  final int battery;

  const BatteryIndicator({super.key, required this.battery});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(_getIcon(), color: _getColor(), size: 22),
        const SizedBox(width: 4),
        Text(
          '$battery%',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  IconData _getIcon() {
    if (battery >= 80) return Icons.battery_full;
    if (battery >= 60) return Icons.battery_6_bar;
    if (battery >= 40) return Icons.battery_4_bar;
    if (battery >= 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  Color _getColor() {
    if (battery >= 40) return Colors.white;
    if (battery >= 20) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}