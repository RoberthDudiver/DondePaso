import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/background/passive_tracking_service.dart';
import 'src/app.dart';
import 'src/telemetry/firebase_telemetry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DondePasoBootstrapApp());
}

class DondePasoBootstrapApp extends StatefulWidget {
  const DondePasoBootstrapApp({super.key});

  @override
  State<DondePasoBootstrapApp> createState() => _DondePasoBootstrapAppState();
}

class _DondePasoBootstrapAppState extends State<DondePasoBootstrapApp> {
  bool _telemetryReady = FirebaseTelemetry.isEnabled;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapAsync());
  }

  Future<void> _bootstrapAsync() async {
    await _initializeTelemetry();
    await _initializePassiveTracking();
  }

  Future<void> _initializeTelemetry() async {
    try {
      await FirebaseTelemetry.initialize().timeout(const Duration(seconds: 4));
      if (!mounted) {
        return;
      }
      setState(() {
        _telemetryReady = FirebaseTelemetry.isEnabled;
      });
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('DondePaso bootstrap: telemetry init skipped: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  Future<void> _initializePassiveTracking() async {
    try {
      await initializePassiveTrackingService().timeout(
        const Duration(seconds: 6),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('DondePaso bootstrap: passive tracking init skipped: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DondePasoApp(
      includeTelemetryObserver: _telemetryReady,
    );
  }
}
