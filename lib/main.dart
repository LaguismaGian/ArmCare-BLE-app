import 'dart:async';
import 'package:flutter/material.dart';
import 'frontend/home_screen.dart';

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    print('FLUTTER ERROR: ${details.exception}');
    print(details.stack);
  };

  runZonedGuarded(() {
    print('>>> main() starting');
    runApp(const MyApp());
    print('>>> runApp() returned');
  }, (error, stack) {
    print('ZONE ERROR: $error');
    print(stack);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('>>> MyApp.build()');
    return MaterialApp(
      title: 'ArmCare',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}