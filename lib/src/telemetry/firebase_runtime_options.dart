import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseRuntimeOptions {
  FirebaseRuntimeOptions._();

  static const String _apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );
  static const String _androidAppId = String.fromEnvironment(
    'FIREBASE_APP_ID_ANDROID',
    defaultValue: '',
  );
  static const String _iosAppId = String.fromEnvironment(
    'FIREBASE_APP_ID_IOS',
    defaultValue: '',
  );
  static const String _messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '',
  );
  static const String _projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: '',
  );
  static const String _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: '',
  );
  static const String _androidClientId = String.fromEnvironment(
    'FIREBASE_ANDROID_CLIENT_ID',
    defaultValue: '',
  );
  static const String _iosClientId = String.fromEnvironment(
    'FIREBASE_IOS_CLIENT_ID',
    defaultValue: '',
  );
  static const String _iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: '',
  );

  static bool get isConfigured {
    if (_apiKey.isEmpty ||
        _messagingSenderId.isEmpty ||
        _projectId.isEmpty) {
      return false;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidAppId.isNotEmpty,
      TargetPlatform.iOS => _iosAppId.isNotEmpty,
      _ => false,
    };
  }

  static FirebaseOptions get currentPlatform {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => FirebaseOptions(
        apiKey: _apiKey,
        appId: _androidAppId,
        messagingSenderId: _messagingSenderId,
        projectId: _projectId,
        storageBucket: _optional(_storageBucket),
        androidClientId: _optional(_androidClientId),
      ),
      TargetPlatform.iOS => FirebaseOptions(
        apiKey: _apiKey,
        appId: _iosAppId,
        messagingSenderId: _messagingSenderId,
        projectId: _projectId,
        storageBucket: _optional(_storageBucket),
        iosClientId: _optional(_iosClientId),
        iosBundleId: _optional(_iosBundleId),
      ),
      _ => throw UnsupportedError('Firebase is not configured for this platform.'),
    };
  }

  static String? _optional(String value) => value.isEmpty ? null : value;
}
