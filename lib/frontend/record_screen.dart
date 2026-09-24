import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../backend/data_manager.dart';
import '../backend/recording_service.dart';
import '../backend/database_service.dart';

class RecordScreen extends StatefulWidget {
  final DataManager dataManager;

  const RecordScreen({super.key, required this.dataManager});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final RecordingService _recorder;

  SensorMode _selectedMode = SensorMode.ble;

  bool _isRecording = false;
  int _elapsedMs = 0;

  // Live graph buffers
  final List<double> _motionHistory = [];
  final List<double> _gyroHistory = [];
  final int _maxPoints = 50;

  // Recording log
  List<Recording> _recordings = [];

  @override
  void initState() {
    super.initState();
    _recorder = RecordingService(widget.dataManager);

    _recorder.stateStream.listen((recording) {
      setState(() => _isRecording = recording);
      if (!recording) {
        _loadRecordings();
      }
    });

    _recorder.timerStream.listen((elapsed) {
      setState(() => _elapsedMs = elapsed);
    });

    _recorder.sampleStream.listen((sample) {
      setState(() {
        final motion = _combinedAccel(sample.ax, sample.ay, sample.az);
        final gyro = _combinedGyro(sample.gx, sample.gy, sample.gz);
        _motionHistory.add(motion);
        _gyroHistory.add(gyro);
        if (_motionHistory.length > _maxPoints) {
          _motionHistory.removeAt(0);
          _gyroHistory.removeAt(0);
        }
      });
    });

    _loadRecordings();
  }

  /// Fused acceleration magnitude in g: √(ax² + ay² + az²)
  double _combinedAccel(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }

  /// Fused gyroscope magnitude in °/s: √(gx² + gy² + gz²)
  double _combinedGyro(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }

  Future<void> _loadRecordings() async {
    final list = await DatabaseService.instance.getAllRecordings();
    setState(() => _recordings = list);
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _recorder.stopRecording();
    } else {
      _motionHistory.clear();
      _gyroHistory.clear();
      _recorder.setMode(_selectedMode);
      await _recorder.startRecording(maxSeconds: 10);
    }
  }

  Future<void> _clearLog() async {
    await DatabaseService.instance.clearAllRecordings();
    _loadRecordings();
  }

  Future<void> _deleteRecording(int id) async {
    await DatabaseService.instance.deleteRecording(id);
    _loadRecordings();
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Record Fall Data'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _recordings.isEmpty ? null : _clearLog,
            tooltip: 'Clear Log',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildModeSwitch(),
              const SizedBox(height: 12),
              _buildLiveGraph(),
              const SizedBox(height: 12),
              _buildTimerAndRecordButton(),
              const SizedBox(height: 12),
              _buildRecordingLog(),
            ],
          ),
        ),
      ),
    );
  }

  // ===== MODE SWITCH =====
  Widget _buildModeSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeButton(
              label: 'BLE Sensor',
              icon: Icons.bluetooth,
              mode: SensorMode.ble,
            ),
          ),
          Expanded(
            child: _modeButton(
              label: 'Phone Sensor',
              icon: Icons.phone_android,
              mode: SensorMode.phone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required SensorMode mode,
  }) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: _isRecording ? null : () => setState(() => _selectedMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.red[700] : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[700],
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== LIVE GRAPH =====
  Widget _buildLiveGraph() {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: _motionHistory.isEmpty
          ? const Center(
              child: Text(
                'No data yet — press Record',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : LineChart(
              LineChartData(
                gridData: const FlGridData(show: true),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: _maxPoints.toDouble(),
                minY: 0,
                lineBarsData: [
                  _buildLine(_motionHistory, Colors.orange),
                  _buildLine(_gyroHistory, Colors.purple),
                ],
              ),
            ),
    );
  }

  LineChartBarData _buildLine(List<double> data, Color color) {
    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i]));
    }
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    );
  }

  // ===== TIMER + RECORD BUTTON =====
  Widget _buildTimerAndRecordButton() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            '${(_elapsedMs / 1000).toStringAsFixed(1)}s',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _toggleRecording,
              icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
              label: Text(
                _isRecording ? 'STOP' : 'RECORD FALL',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isRecording ? Colors.red[600] : Colors.red[800],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===== RECORDING LOG =====
  Widget _buildRecordingLog() {
    if (_recordings.isEmpty) {
      return const Expanded(
        child: Center(
          child: Text(
            'No recordings yet',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return Expanded(
      child: ListView.builder(
        itemCount: _recordings.length,
        itemBuilder: (context, index) {
          final rec = _recordings[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.red,
                child: Icon(Icons.warning, color: Colors.white),
              ),
              title: Text(
                rec.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${rec.mode.toUpperCase()} • '
                '${(rec.durationMs / 1000).toStringAsFixed(1)}s • '
                '${rec.sampleCount} samples',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteRecording(rec.id!),
              ),
            ),
          );
        },
      ),
    );
  }
}