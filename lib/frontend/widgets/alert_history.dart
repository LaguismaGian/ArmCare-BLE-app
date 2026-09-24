import 'dart:async';
import 'package:flutter/material.dart';
import '../../backend/data_manager.dart';
import '../../backend/alert_service.dart';
import '../../backend/database_service.dart';

class AlertHistory extends StatefulWidget {
  final DataManager dataManager;

  const AlertHistory({super.key, required this.dataManager});

  @override
  State<AlertHistory> createState() => AlertHistoryState();
}

class AlertHistoryState extends State<AlertHistory> {
  final List<AlertEvent> _alerts = [];
  StreamSubscription<AlertEvent>? _sub;
  static const int _maxEntries = 20;

  @override
  void initState() {
    super.initState();
    _loadPastAlerts();
    _sub = widget.dataManager.alertStream.listen(_onNewAlert);
  }

  Future<void> _loadPastAlerts() async {
    final rows = await DatabaseService.instance
        .getRecentAlerts(limit: _maxEntries);
    if (!mounted) return;
    setState(() {
      _alerts
        ..clear()
        ..addAll(rows.map(_rowToEvent));
    });
  }

  void _onNewAlert(AlertEvent event) {
    if (!mounted) return;
    setState(() {
      _alerts.insert(0, event); // newest first
      if (_alerts.length > _maxEntries) {
        _alerts.removeLast();
      }
    });
  }

  AlertEvent _rowToEvent(AlertRow row) {
    return AlertEvent(
      alertClass: row.alertClass,
      label: row.label,
      message: row.message,
      hr: row.hr,
      motion: row.motion,
      gyro: row.gyro,
    );
  }

  Future<void> clearHistory() async {
    await DatabaseService.instance.clearAllAlerts();
    if (!mounted) return;
    setState(() => _alerts.clear());
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Alert History?'),
        content: const Text(
            'This will delete all past alerts from the database. '
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await clearHistory();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ===== Header with Clear button =====
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Alert History',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            if (_alerts.isNotEmpty)
              TextButton.icon(
                onPressed: _confirmClear,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red[700],
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // ===== List =====
        if (_alerts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                Icon(Icons.notifications_none,
                    size: 32, color: Colors.grey[500]),
                const SizedBox(height: 8),
                Text(
                  'No alerts yet',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _alerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              return _buildAlertCard(_alerts[index]);
            },
          ),
      ],
    );
  }

  Widget _buildAlertCard(AlertEvent event) {
    final isFall = event.alertClass == 'fall';
    final color = isFall ? Colors.red : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isFall ? Colors.red[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isFall ? Colors.red[200]! : Colors.orange[200]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFall ? Icons.warning : Icons.error_outline,
            color: color[700],
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color[900],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _detailLine(event),
                  style: TextStyle(
                    fontSize: 12,
                    color: color[800],
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatTime(event),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color[800],
            ),
          ),
        ],
      ),
    );
  }

  /// Detail line for the alert — the values that triggered it.
  String _detailLine(AlertEvent event) {
    switch (event.label) {
      case 'Fall Detected':
        return '${event.motion.toStringAsFixed(2)}g · '
            '${event.gyro.toStringAsFixed(0)}°/s';
      case 'Abnormal Motion':
        return '${event.motion.toStringAsFixed(2)}g · '
            '${event.gyro.toStringAsFixed(0)}°/s';
      case 'High HR':
      case 'Low HR':
        return 'HR ${event.hr.toInt()} BPM';
      default:
        return '';
    }
  }

  /// Time format for the alert entry. Stored as ISO8601 in the DB.
  String _formatTime(AlertEvent event) {
    // In-memory events don't carry a timestamp (added live), so use now.
    // DB-loaded ones would carry it, but our AlertEvent doesn't store it —
    // so use the moment the alert arrived. Close enough for a live feed.
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}