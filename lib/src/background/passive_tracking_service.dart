import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import 'tracking_preferences.dart';
import '../footprint/footprint_progress.dart';
import '../footprint/footprint_storage.dart';
import '../i18n/app_strings.dart';

const trackingNotificationChannelId = 'tracking_foreground';
const _trackingNotificationId = 1207;

const AndroidNotificationChannel _trackingChannel = AndroidNotificationChannel(
  trackingNotificationChannelId,
  'DondePaso tracking',
  description: 'Foreground service for passive location tracking.',
  importance: Importance.low,
);

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();
final Distance _distance = const Distance();
StreamSubscription<Position>? _backgroundPositionSubscription;
LatLng? _adaptiveAnchorPoint;
DateTime? _adaptiveAnchorAt;
bool _usingReducedTracking = false;
int _idleSamples = 0;
int _movingSamples = 0;

enum PassiveTrackingPermissionResult {
  granted,
  locationServicesDisabled,
  foregroundDenied,
  backgroundDenied,
  permanentlyDenied,
}

Future<void> initializePassiveTrackingService() async {
  await _ensureTrackingNotificationChannel();
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
      foregroundServiceNotificationId: _trackingNotificationId,
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

  if (Platform.isAndroid) {
    await Permission.notification.request();
  }

  return PassiveTrackingPermissionResult.granted;
}

Future<void> ensurePassiveTrackingServiceRunning() async {
  final storage = FootprintStorage();
  await storage.setPassiveTrackingEnabled(true);
  final service = FlutterBackgroundService();
  await _ensureTrackingNotificationChannel();

  if (await service.isRunning()) {
    service.invoke('capture_now');
    return;
  }

  await service.startService();
}

Future<void> stopPassiveTrackingService() async {
  await FootprintStorage().setPassiveTrackingEnabled(false);
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

Future<void> _ensureTrackingNotificationChannel() async {
  if (!Platform.isAndroid) {
    return;
  }

  final androidNotifications = _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  await androidNotifications?.createNotificationChannel(_trackingChannel);
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

  await _backgroundPositionSubscription?.cancel();
  _adaptiveAnchorPoint = null;
  _adaptiveAnchorAt = null;
  _usingReducedTracking = false;
  _idleSamples = 0;
  _movingSamples = 0;

  if (service is AndroidServiceInstance) {
    service.on('stop_service').listen((_) async {
      await _backgroundPositionSubscription?.cancel();
      await FootprintProgress.flushPending();
      service.stopSelf();
    });
  }

  service.on('capture_now').listen((_) async {
    await _captureAndPersist(service);
  });

  service.on('refresh_stream').listen((_) async {
    await _backgroundPositionSubscription?.cancel();
    await _startBackgroundTrackingStream(service);
  });

  await _captureAndPersist(service);
  await _startBackgroundTrackingStream(service);
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
  await _persistPosition(service, position);
}

Future<void> _startBackgroundTrackingStream(ServiceInstance service) async {
  await _backgroundPositionSubscription?.cancel();
  final permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.always &&
      permission != LocationPermission.whileInUse) {
    return;
  }

  final servicesEnabled = await Geolocator.isLocationServiceEnabled();
  if (!servicesEnabled) {
    return;
  }

  final trackingPreferences = (await FootprintStorage().load()).trackingPreferences;
  final tuning = resolveTrackingTuning(
    trackingPreferences,
    reducedMode: _usingReducedTracking,
  );

  final locationSettings = AndroidSettings(
    accuracy: tuning.accuracy,
    distanceFilter: tuning.distanceFilterMeters,
    intervalDuration: tuning.interval,
    forceLocationManager: false,
  );

  _backgroundPositionSubscription =
      Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((position) async {
        await _persistPosition(service, position);
      }, onError: (_) async {
        await _captureAndPersist(service);
      });
}

Future<void> _persistPosition(ServiceInstance service, Position position) async {
  final point = LatLng(position.latitude, position.longitude);
  await _updateAdaptiveMode(service, point, position);
  final snapshot = await FootprintProgress.recordVisit(
    point: point,
    persistImmediately: false,
  );
  final strings = AppStrings.fromSystem();
  final knownKilometers = FootprintProgress.knownKilometersFor(
    snapshot.cells,
    DateTime.now(),
  );
  final traveledTodayKilometers = FootprintProgress.todayKilometersFor(
    snapshot,
  );

  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: strings.serviceNotificationTitle,
      content: strings.serviceNotificationContent(
        knownKilometers: knownKilometers,
        traveledTodayKilometers: traveledTodayKilometers,
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

Future<void> _updateAdaptiveMode(
  ServiceInstance service,
  LatLng point,
  Position position,
) async {
  final trackingPreferences = (await FootprintStorage().load()).trackingPreferences;
  if (!trackingPreferences.adaptiveModeEnabled) {
    _adaptiveAnchorPoint = point;
    _adaptiveAnchorAt = position.timestamp;
    _idleSamples = 0;
    _movingSamples = 0;
    if (_usingReducedTracking) {
      _usingReducedTracking = false;
      service.invoke('refresh_stream');
    }
    return;
  }

  final anchorPoint = _adaptiveAnchorPoint;
  final anchorAt = _adaptiveAnchorAt;
  _adaptiveAnchorPoint = point;
  _adaptiveAnchorAt = position.timestamp;

  if (anchorPoint == null || anchorAt == null) {
    return;
  }

  final now = position.timestamp;
  final movedMeters = _distance.as(LengthUnit.Meter, anchorPoint, point);
  final seconds = now.difference(anchorAt).inSeconds;
  final speed = position.speed > 0
      ? position.speed
      : seconds > 0
      ? movedMeters / seconds
      : 0.0;

  final looksIdle = movedMeters < 10 && speed < 0.8;
  final looksMoving = movedMeters > 18 || speed > 1.2;

  if (looksIdle) {
    _idleSamples += 1;
    _movingSamples = 0;
  } else if (looksMoving) {
    _movingSamples += 1;
    _idleSamples = 0;
  }

  if (!_usingReducedTracking && _idleSamples >= 3) {
    _usingReducedTracking = true;
    service.invoke('refresh_stream');
    return;
  }

  if (_usingReducedTracking && _movingSamples >= 2) {
    _usingReducedTracking = false;
    service.invoke('refresh_stream');
  }
}
