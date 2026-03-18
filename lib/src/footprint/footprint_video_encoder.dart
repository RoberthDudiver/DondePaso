import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FootprintVideoEncoder {
  FootprintVideoEncoder._();

  static const MethodChannel _channel = MethodChannel(
    'com.dudiver.dondepaso/video_encoder',
  );

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<String?> encodePngSequenceToMp4({
    required List<String> framePaths,
    required String outputPath,
    required int width,
    required int height,
    required int fps,
    String? audioPath,
    int? audioDurationUs,
  }) async {
    if (!isSupported || framePaths.isEmpty) {
      return null;
    }

    final result = await _channel.invokeMethod<String>(
      'encodePngSequenceToMp4',
      <String, dynamic>{
        'framePaths': framePaths,
        'outputPath': outputPath,
        'width': width,
        'height': height,
        'fps': fps,
        'audioPath': audioPath,
        'audioDurationUs': audioDurationUs,
      },
    );
    return result;
  }
}
