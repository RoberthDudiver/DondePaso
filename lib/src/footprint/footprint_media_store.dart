import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FootprintMediaStore {
  FootprintMediaStore._();

  static const MethodChannel _channel = MethodChannel(
    'com.dudiver.dondepaso/media_share',
  );

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<String?> saveToGallery({
    required String sourcePath,
    required String mimeType,
    required String displayName,
  }) async {
    if (!isSupported) {
      return null;
    }

    return _channel.invokeMethod<String>(
      'saveToGallery',
      <String, dynamic>{
        'sourcePath': sourcePath,
        'mimeType': mimeType,
        'displayName': displayName,
      },
    );
  }

  static Future<void> shareSavedMedia({
    required String uri,
    required String mimeType,
    String? text,
    String? title,
  }) async {
    if (!isSupported) {
      return;
    }

    await _channel.invokeMethod<void>(
      'shareSavedMedia',
      <String, dynamic>{
        'uri': uri,
        'mimeType': mimeType,
        'text': text,
        'title': title,
      },
    );
  }
}
