import 'package:flutter/material.dart';

import 'src/background/passive_tracking_service.dart';
import 'src/app.dart';
import 'src/telemetry/firebase_telemetry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseTelemetry.initialize();
  await initializePassiveTrackingService();
  runApp(const DondePasoApp());
}
