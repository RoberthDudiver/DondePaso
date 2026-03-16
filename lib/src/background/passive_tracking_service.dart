import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../footprint/footprint_progress.dart';
import '../i18n/app_strings.dart';

const trackingNotificationChannelId = 'tracking_foreground';

enum PassiveTrackingPermissionResult {
  granted,
  locationServicesDisabled,
  foregroundDenied,
  backgroundDenied,
  permanentlyDenied,
}

Future<void> initializePassiveTrackingService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: passiveTrackingOnStart,
      autoStart: false,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: trackingNotificationChannelId,
      initialNotificationTitle: 'DondePaso activo',
      initialNotificationContent: 'Preparando rastreo pasivo',
      foregroundServiceNotificationId: 1207,
      foregroundServiceTypes: const [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: passiveTrackingOnStart,
      onBackground: onIosBackground,
    ),
  );
}

Future<PassiveTrackingPermissionResult>
requestPassiveTrackingPermissions() async {
  final servicesEnabled = await Geolocator.isLocationServiceEnabled();
  if (!servicesEnabled) {
    return PassiveTrackingPermissionResult.locationServicesDisabled;
  }

  final foreground = await Permission.locationWhenInUse.request();
  if (foreground.isPermanentlyDenied) {
    return PassiveTrackingPermissionResult.permanentlyDenied;
  }
  if (!foreground.isGranted) {
    return PassiveTrackingPermissionResult.foregroundDenied;
  }

  final background = await Permission.locationAlways.request();
  if (background.isPermanentlyDenied) {
    return PassiveTrackingPermissionResult.permanentlyDenied;
  }
  if (!background.isGranted) {
    return PassiveTrackingPermissionResult.backgroundDenied;
  }

  return PassiveTrackingPermissionResult.granted;
}

Future<void> ensurePassiveTrackingServiceRunning() async {
  // Temporarily disabled on-device due to foreground notification crashes
  // on some Android 16 / Samsung builds.
}

Future<void> stopPassiveTrackingService() async {
  try {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stop_service');
    }
  } catch (_) {
    // Ignored on unsupported platforms such as widget tests.
  }
}

Future<bool> isPassiveTrackingServiceRunning() async {
  try {
    return FlutterBackgroundService().isRunning();
  } catch (_) {
    return false;
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await _captureAndPersist(service);
  return true;
}

@pragma('vm:entry-point')
void passiveTrackingOnStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('stop_service').listen((_) {
      service.stopSelf();
    });
  }

  service.on('capture_now').listen((_) async {
    await _captureAndPersist(service);
  });

  await _captureAndPersist(service);

  Timer.periodic(const Duration(seconds: 20), (timer) async {
    await _captureAndPersist(service);
  });
}

Future<void> _captureAndPersist(ServiceInstance service) async {
  final permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.always &&
      permission != LocationPermission.whileInUse) {
    return;
  }

  final servicesEnabled = await Geolocator.isLocationServiceEnabled();
  if (!servicesEnabled) {
    return;
  }

  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
  );

  final point = LatLng(position.latitude, position.longitude);
  final snapshot = await FootprintProgress.recordVisit(point: point);
  final strings = AppStrings.fromSystem();
  final knownMeters =
      (FootprintProgress.knownKilometersFor(snapshot.cells, DateTime.now()) *
              1000)
          .round();

  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: strings.serviceNotificationTitle,
      content: strings.serviceNotificationContent(
        snapshot.totalPoints,
        knownMeters,
      ),
    );
  }

  service.invoke('footprint_update', <String, dynamic>{
    'points': snapshot.totalPoints,
    'latitude': point.latitude,
    'longitude': point.longitude,
    'trackedAt': snapshot.lastTrackedAt?.toIso8601String(),
  });
}
