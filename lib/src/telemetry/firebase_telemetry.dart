import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'firebase_runtime_options.dart';

class FirebaseTelemetry {
  FirebaseTelemetry._();

  static bool _initialized = false;
  static FirebaseAnalytics? _analytics;
  static FirebaseAnalyticsObserver? _observer;

  static FirebaseAnalyticsObserver? get observer => _observer;
  static FirebaseAnalytics? get analytics => _analytics;
  static bool get isEnabled => _initialized;

  static Future<void> initialize() async {
    if (_initialized ||
        kIsWeb ||
        !_supportsFirebasePlatform ||
        !FirebaseRuntimeOptions.isConfigured) {
      return;
    }

    await Firebase.initializeApp(
      options: FirebaseRuntimeOptions.currentPlatform,
    );

    _analytics = FirebaseAnalytics.instance;
    _observer = FirebaseAnalyticsObserver(analytics: _analytics!);

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      previousOnError?.call(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!kDebugMode);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );

    _initialized = true;
  }

  static bool get _supportsFirebasePlatform {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => true,
      TargetPlatform.iOS => true,
      _ => false,
    };
  }
}
