import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class PlotterScreen extends StatefulWidget {
  final Stream<String> dataStream;

  const PlotterScreen({super.key, required this.dataStream});

  @override
  State<PlotterScreen> createState() => _PlotterScreenState();
}

class _PlotterScreenState extends State<PlotterScreen> {
  List<double> hrHistory = [];
  List<double> motionHistory = [];
  List<double> gyroHistory = [];
  final int maxDataPoints = 100;

  @override
  void initState() {
    super.initState();
    widget.dataStream.listen((data) {
      var parts = data.split(',');
      if (parts.length >= 3) {
        double hr = double.tryParse(parts[0]) ?? 0;
        double motion = double.tryParse(parts[1]) ?? 0;
        double gyro = double.tryParse(parts[2]) ?? 0;

        setState(() {
          hrHistory.add(hr);
          motionHistory.add(motion);
          gyroHistory.add(gyro);

          if (hrHistory.length > maxDataPoints) {
            hrHistory.removeAt(0);
            motionHistory.removeAt(0);
            gyroHistory.removeAt(0);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Data Plotter')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  titlesData: const FlTitlesData(show: true),
                  borderData: FlBorderData(show: true),
                  minX: 0,
                  maxX: maxDataPoints.toDouble(),
                  minY: 0,
                  maxY: 200,
                  lineBarsData: [
                    _buildLine(hrHistory, Colors.red, "HR"),
                    _buildLine(motionHistory, Colors.blue, "Motion"),
                    _buildLine(gyroHistory, Colors.green, "Gyro"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegend(Colors.red, "HR"),
                const SizedBox(width: 16),
                _buildLegend(Colors.blue, "Motion"),
                const SizedBox(width: 16),
                _buildLegend(Colors.green, "Gyro"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  LineChartBarData _buildLine(List<double> data, Color color, String label) {
    List<FlSpot> spots = [];
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

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(width: 16, height: 16, color: color),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}