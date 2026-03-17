import 'package:flutter/material.dart';

import 'src/background/passive_tracking_service.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializePassiveTrackingService();
  runApp(const DondePasoApp());
}
