import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../i18n/app_strings.dart';
import 'footprint_cell.dart';
import 'footprint_h3_grid.dart';
import 'footprint_media_store.dart';
import 'footprint_timelapse_range.dart';
import 'footprint_video_encoder.dart';

class FootprintTimelapseService {
  FootprintTimelapseService._();

  static const String _soundtrackAsset = 'DOndePAso1.mp3';
  static const double _canvasWidth = 720.0;
  static const double _canvasHeight = 1280.0;
  static const double _mapTop = 248.0;
  static const double _mapBottom = 962.0;
  static const double _mapLeft = 52.0;
  static const double _mapRight = 668.0;
  static const int _fps = 15;
  static const double _introDurationSeconds = 3.0;
  static const double _minTimelineDurationSeconds = 5.0;
  static const double _maxTimelineDurationSeconds = 10.0;
  static const double _heroDurationSeconds = 1.6;
  static const double _holdDurationSeconds = 0.9;
  static const int _maxMapTiles = 36;

  static Future<void> generateAndShare({
    required AppStrings strings,
    required List<FootprintCell> cells,
    required String zoneName,
    required int explorationPercent,
    required int totalPoints,
    required double knownKilometers,
    required FootprintTimelapseRange range,
  }) async {
    final filteredCells = _filterCellsForRange(cells, range);
    final h3Cells = filteredCells.where((cell) => cell.isH3).toList(growable: false);
    if (h3Cells.isEmpty) {
      throw StateError('No H3 cells available for timelapse.');
    }

    final sortedCells = [...h3Cells]
      ..sort((left, right) => left.lastSeen.compareTo(right.lastSeen));

    final introFrameCount = _framesForSeconds(_introDurationSeconds);
    final heroFrameCount = _framesForSeconds(_heroDurationSeconds);
    final holdFrameCount = _framesForSeconds(_holdDurationSeconds);
    final revealFrameCount = _resolveRevealFrameCount(
      cellCount: sortedCells.length,
      heroFrameCount: heroFrameCount,
      holdFrameCount: holdFrameCount,
    );
    final directory = await getTemporaryDirectory();
    final workingDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}dondepaso_timelapse_frames',
    );
    if (workingDirectory.existsSync()) {
      await workingDirectory.delete(recursive: true);
    }
    await workingDirectory.create(recursive: true);
    final scene = await _buildScene(sortedCells);
    try {
      if (FootprintVideoEncoder.isSupported) {
        final frameFiles = await _renderFrames(
          strings: strings,
          scene: scene,
          zoneName: zoneName,
          explorationPercent: explorationPercent,
          totalPoints: totalPoints,
          knownKilometers: knownKilometers,
          introFrameCount: introFrameCount,
          revealFrameCount: revealFrameCount,
          heroFrameCount: heroFrameCount,
          holdFrameCount: holdFrameCount,
          range: range,
          workingDirectory: workingDirectory,
        );
        final outputPath =
            '${workingDirectory.path}${Platform.pathSeparator}dondepaso_timelapse.mp4';
        final soundtrackPath = await _prepareSoundtrackFile();
        final totalFrameCount =
            introFrameCount + revealFrameCount + heroFrameCount + holdFrameCount;
        final encodedPath = await FootprintVideoEncoder.encodePngSequenceToMp4(
          framePaths: frameFiles.map((file) => file.path).toList(growable: false),
          outputPath: outputPath,
          width: _canvasWidth.toInt(),
          height: _canvasHeight.toInt(),
          fps: _fps,
          audioPath: soundtrackPath,
          audioDurationUs: ((totalFrameCount * 1000000) / _fps).round(),
        );
        if (encodedPath != null) {
          await _shareVideo(
            strings: strings,
            encodedPath: encodedPath,
            zoneName: zoneName,
            explorationPercent: explorationPercent,
            range: range,
          );
          return;
        }
      }

      final image = await _renderHeroFrame(
        strings: strings,
        visibleCells: scene.cells,
        scene: scene,
        heroRatio: 1.0,
        pulse: 0.92,
        zoneName: zoneName,
        explorationPercent: explorationPercent,
        totalPoints: totalPoints,
        knownKilometers: knownKilometers,
        range: range,
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Timelapse fallback image bytes are empty.');
      }

      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}dondepaso_timelapse_fallback.png',
      );
      await file.writeAsBytes(bytes, flush: true);

      await _shareImage(
        strings: strings,
        imagePath: file.path,
        zoneName: zoneName,
        explorationPercent: explorationPercent,
        range: range,
      );
    } finally {
      if (workingDirectory.existsSync()) {
        await workingDirectory.delete(recursive: true);
      }
      scene.dispose();
    }
  }

  static Future<List<File>> _renderFrames({
    required AppStrings strings,
    required _TimelapseScene scene,
    required String zoneName,
    required int explorationPercent,
    required int totalPoints,
    required double knownKilometers,
    required int introFrameCount,
    required int revealFrameCount,
    required int heroFrameCount,
    required int holdFrameCount,
    required FootprintTimelapseRange range,
    required Directory workingDirectory,
  }) async {
    final frameFiles = <File>[];
    for (var introIndex = 0; introIndex < introFrameCount; introIndex++) {
      final introRatio = introIndex / math.max(1, introFrameCount - 1);
      final uiImage = await _renderIntroFrame(
        strings: strings,
        introRatio: introRatio,
        zoneName: zoneName,
        range: range,
      );
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        uiImage.dispose();
        continue;
      }
      final frameFile = File(
        '${workingDirectory.path}${Platform.pathSeparator}frame_${frameFiles.length.toString().padLeft(3, '0')}.png',
      );
      await frameFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      frameFiles.add(frameFile);
      uiImage.dispose();
    }

    for (var frameIndex = 0; frameIndex < revealFrameCount; frameIndex++) {
      final revealRatio = _easeOut((frameIndex + 1) / revealFrameCount);
      final pulse = _musicPulse(frameIndex / math.max(1, revealFrameCount - 1));
      final visibleCount = math.max(1, (scene.cells.length * revealRatio).round());
      final uiImage = await _renderFrame(
        strings: strings,
        visibleCells: scene.cells.take(visibleCount).toList(growable: false),
        scene: scene,
        revealRatio: revealRatio,
        pulse: pulse,
        zoneName: zoneName,
        explorationPercent: explorationPercent,
        totalPoints: totalPoints,
        knownKilometers: knownKilometers,
        range: range,
      );
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        uiImage.dispose();
        continue;
      }
      final frameFile = File(
        '${workingDirectory.path}${Platform.pathSeparator}frame_${frameFiles.length.toString().padLeft(3, '0')}.png',
      );
      await frameFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      frameFiles.add(frameFile);
      uiImage.dispose();
    }

    for (var heroIndex = 0; heroIndex < heroFrameCount; heroIndex++) {
      final heroRatio = heroIndex / math.max(1, heroFrameCount - 1);
      final pulse = _musicPulse(0.82 + heroRatio * 0.18);
      final uiImage = await _renderHeroFrame(
        strings: strings,
        visibleCells: scene.cells,
        scene: scene,
        heroRatio: heroRatio,
        pulse: pulse,
        zoneName: zoneName,
        explorationPercent: explorationPercent,
        totalPoints: totalPoints,
        knownKilometers: knownKilometers,
        range: range,
      );
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        uiImage.dispose();
        continue;
      }
      final frameFile = File(
        '${workingDirectory.path}${Platform.pathSeparator}frame_${frameFiles.length.toString().padLeft(3, '0')}.png',
      );
      await frameFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      frameFiles.add(frameFile);
      uiImage.dispose();
    }

    if (frameFiles.isNotEmpty) {
      final lastBytes = await frameFiles.last.readAsBytes();
      for (var holdIndex = 0; holdIndex < holdFrameCount; holdIndex++) {
        final holdFile = File(
          '${workingDirectory.path}${Platform.pathSeparator}frame_${(frameFiles.length + holdIndex).toString().padLeft(3, '0')}.png',
        );
        await holdFile.writeAsBytes(lastBytes, flush: true);
        frameFiles.add(holdFile);
      }
    }

    return frameFiles;
  }

  static Future<void> generateAndShareCard({
    required AppStrings strings,
    required List<FootprintCell> cells,
    required String zoneName,
    required int explorationPercent,
    required int totalPoints,
    required double knownKilometers,
  }) async {
    final h3Cells = cells.where((cell) => cell.isH3).toList(growable: false);
    if (h3Cells.isEmpty) {
      throw StateError('No H3 cells available for share card.');
    }

    final sortedCells = [...h3Cells]
      ..sort((left, right) => left.lastSeen.compareTo(right.lastSeen));
    final scene = await _buildScene(sortedCells);
    try {
      final image = await _renderHeroFrame(
        strings: strings,
        visibleCells: scene.cells,
        scene: scene,
        heroRatio: 0.58,
        pulse: 0.76,
        zoneName: zoneName,
        explorationPercent: explorationPercent,
        totalPoints: totalPoints,
        knownKilometers: knownKilometers,
        range: FootprintTimelapseRange.global,
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Share card image bytes are empty.');
      }

      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}dondepaso_share_card.png',
      );
      await file.writeAsBytes(bytes, flush: true);

      await _shareImage(
        strings: strings,
        imagePath: file.path,
        zoneName: zoneName,
        explorationPercent: explorationPercent,
        range: FootprintTimelapseRange.global,
        isMapCard: true,
      );
    } finally {
      scene.dispose();
    }
  }

  static Future<void> generateAndSaveCard({
    required AppStrings strings,
    required List<FootprintCell> cells,
    required String zoneName,
    required int explorationPercent,
    required int totalPoints,
    required double knownKilometers,
  }) async {
    final h3Cells = cells.where((cell) => cell.isH3).toList(growable: false);
    if (h3Cells.isEmpty) {
      throw StateError('No H3 cells available for share card.');
    }

    final sortedCells = [...h3Cells]
      ..sort((left, right) => left.lastSeen.compareTo(right.lastSeen));
    final scene = await _buildScene(sortedCells);
    try {
      final image = await _renderHeroFrame(
        strings: strings,
        visibleCells: scene.cells,
        scene: scene,
        heroRatio: 0.58,
        pulse: 0.76,
        zoneName: zoneName,
        explorationPercent: explorationPercent,
        totalPoints: totalPoints,
        knownKilometers: knownKilometers,
        range: FootprintTimelapseRange.global,
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Share card image bytes are empty.');
      }

      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}dondepaso_share_card.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await _saveImageToGallery(
        imagePath: file.path,
        displayName: _buildDisplayName('dondepaso_card', '.png'),
      );
    } finally {
      scene.dispose();
    }
  }

  static Future<void> generateAndSaveTimelapse({
    required AppStrings strings,
    required List<FootprintCell> cells,
    required String zoneName,
    required int explorationPercent,
    required int totalPoints,
    required double knownKilometers,
    required FootprintTimelapseRange range,
  }) async {
    final filteredCells = _filterCellsForRange(cells, range);
    final h3Cells = filteredCells.where((cell) => cell.isH3).toList(growable: false);
    if (h3Cells.isEmpty) {
      throw StateError('No H3 cells available for timelapse.');
    }

    final sortedCells = [...h3Cells]
      ..sort((left, right) => left.lastSeen.compareTo(right.lastSeen));

    final introFrameCount = _framesForSeconds(_introDurationSeconds);
    final heroFrameCount = _framesForSeconds(_heroDurationSeconds);
    final holdFrameCount = _framesForSeconds(_holdDurationSeconds);
    final revealFrameCount = _resolveRevealFrameCount(
      cellCount: sortedCells.length,
      heroFrameCount: heroFrameCount,
      holdFrameCount: holdFrameCount,
    );
    final directory = await getTemporaryDirectory();
    final workingDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}dondepaso_timelapse_frames',
    );
    if (workingDirectory.existsSync()) {
      await workingDirectory.delete(recursive: true);
    }
    await workingDirectory.create(recursive: true);
    final scene = await _buildScene(sortedCells);
    try {
      if (FootprintVideoEncoder.isSupported) {
        final frameFiles = await _renderFrames(
          strings: strings,
          scene: scene,
          zoneName: zoneName,
          explorationPercent: explorationPercent,
          totalPoints: totalPoints,
          knownKilometers: knownKilometers,
          introFrameCount: introFrameCount,
          revealFrameCount: revealFrameCount,
          heroFrameCount: heroFrameCount,
          holdFrameCount: holdFrameCount,
          range: range,
          workingDirectory: workingDirectory,
        );
        final outputPath =
            '${workingDirectory.path}${Platform.pathSeparator}dondepaso_timelapse.mp4';
        final soundtrackPath = await _prepareSoundtrackFile();
        final totalFrameCount =
            introFrameCount + revealFrameCount + heroFrameCount + holdFrameCount;
        final encodedPath = await FootprintVideoEncoder.encodePngSequenceToMp4(
          framePaths: frameFiles.map((file) => file.path).toList(growable: false),
          outputPath: outputPath,
          width: _canvasWidth.toInt(),
          height: _canvasHeight.toInt(),
          fps: _fps,
          audioPath: soundtrackPath,
          audioDurationUs: ((totalFrameCount * 1000000) / _fps).round(),
        );
        if (encodedPath != null) {
          await _saveVideoToGallery(encodedPath);
          return;
        }
      }

      final image = await _renderHeroFrame(
        strings: strings,
        visibleCells: scene.cells,
        scene: scene,
        heroRatio: 1.0,
        pulse: 0.92,
        zoneName: zoneName,
        explorationPercent: explorationPercent,
        totalPoints: totalPoints,
        knownKilometers: knownKilometers,
        range: range,
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Timelapse fallback image bytes are empty.');
      }

      final file = File(
        '${workingDirectory.path}${Platform.pathSeparator}dondepaso_timelapse_fallback.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await _saveImageToGallery(
        imagePath: file.path,
        displayName: _buildDisplayName('dondepaso_timelapse', '.png'),
      );
    } finally {
      if (workingDirectory.existsSync()) {
        await workingDirectory.delete(recursive: true);
      }
      scene.dispose();
    }
  }

  static int _framesForSeconds(double seconds) {
    return math.max(1, (seconds * _fps).round());
  }

  static int _resolveRevealFrameCount({
    required int cellCount,
    required int heroFrameCount,
    required int holdFrameCount,
  }) {
    final desiredTimelineSeconds = (cellCount / 8).clamp(
      _minTimelineDurationSeconds,
      _maxTimelineDurationSeconds,
    );
    final desiredTimelineFrames = _framesForSeconds(desiredTimelineSeconds);
    final revealFrames = desiredTimelineFrames - heroFrameCount - holdFrameCount;
    return math.max(_framesForSeconds(2.5), revealFrames);
  }

  static List<FootprintCell> _filterCellsForRange(
    List<FootprintCell> cells,
    FootprintTimelapseRange range,
  ) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    return switch (range) {
      FootprintTimelapseRange.global => cells,
      FootprintTimelapseRange.today => cells
          .where((cell) => !cell.lastSeen.isBefore(startOfToday))
          .toList(growable: false),
      FootprintTimelapseRange.last7Days => cells
          .where(
            (cell) => !cell.lastSeen.isBefore(
              now.subtract(const Duration(days: 7)),
            ),
          )
          .toList(growable: false),
      FootprintTimelapseRange.last30Days => cells
          .where(
            (cell) => !cell.lastSeen.isBefore(
              now.subtract(const Duration(days: 30)),
            ),
          )
          .toList(growable: false),
    };
  }

  static Future<_TimelapseScene> _buildScene(List<FootprintCell> cells) async {
    final sortedBoundaries = cells
        .map((cell) => (cell: cell, boundary: FootprintH3Grid.boundaryForCell(cell)))
        .where((entry) => entry.boundary.isNotEmpty)
        .toList(growable: false);

    final latitudes = sortedBoundaries
        .expand((entry) => entry.boundary.map((point) => point.latitude))
        .toList(growable: false);
    final longitudes = sortedBoundaries
        .expand((entry) => entry.boundary.map((point) => point.longitude))
        .toList(growable: false);

    final minLat = latitudes.reduce(math.min);
    final maxLat = latitudes.reduce(math.max);
    final minLon = longitudes.reduce(math.min);
    final maxLon = longitudes.reduce(math.max);
    final latSpan = math.max(0.0006, maxLat - minLat);
    final lonSpan = math.max(0.0006, maxLon - minLon);
    final paddedLatSpan = latSpan * 1.18;
    final paddedLonSpan = lonSpan * 1.18;
    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;
    final mapWidth = _mapRight - _mapLeft;
    final mapHeight = _mapBottom - _mapTop;

    Offset project(double lat, double lon) {
      final x =
          ((lon - (centerLon - paddedLonSpan / 2)) / paddedLonSpan) * mapWidth;
      final y =
          ((centerLat + paddedLatSpan / 2 - lat) / paddedLatSpan) * mapHeight;
      return Offset(_mapLeft + x, _mapTop + y);
    }

    final projectedCells = sortedBoundaries
        .map(
          (entry) => _ProjectedTimelapseCell(
            cell: entry.cell,
            path: _buildProjectedPath(
              entry.boundary
                  .map((point) => project(point.latitude, point.longitude))
                  .toList(growable: false),
            ),
          ),
        )
        .toList(growable: false);

    final mapImage = await _fetchRealMapImage(
      minLat: centerLat - paddedLatSpan / 2,
      maxLat: centerLat + paddedLatSpan / 2,
      minLon: centerLon - paddedLonSpan / 2,
      maxLon: centerLon + paddedLonSpan / 2,
      width: mapWidth.toInt(),
      height: mapHeight.toInt(),
    );

    return _TimelapseScene(
      cells: projectedCells,
      mapRect: Rect.fromLTWH(_mapLeft, _mapTop, mapWidth, mapHeight),
      mapImage: mapImage,
    );
  }

  static double _easeOut(double value) {
    final inverse = 1 - value;
    return 1 - inverse * inverse * inverse;
  }

  static double _musicPulse(double progress) {
    final phase = progress * math.pi * 8.0;
    final pulse = (math.sin(phase) * 0.5) + 0.5;
    return 0.58 + (pulse * 0.42);
  }


  static Future<ui.Image?> _fetchRealMapImage({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required int width,
    required int height,
  }) async {
    try {
      final zoom = _chooseZoom(
        minLat: minLat,
        maxLat: maxLat,
        minLon: minLon,
        maxLon: maxLon,
        width: width,
        height: height,
      );

      final topLeft = _latLonToWorldPixel(maxLat, minLon, zoom);
      final bottomRight = _latLonToWorldPixel(minLat, maxLon, zoom);

      final minTileX = (topLeft.dx / 256).floor();
      final minTileY = (topLeft.dy / 256).floor();
      final maxTileX = (bottomRight.dx / 256).floor();
      final maxTileY = (bottomRight.dy / 256).floor();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );

      final pixelWidth = (bottomRight.dx - topLeft.dx).abs();
      final pixelHeight = (bottomRight.dy - topLeft.dy).abs();
      final scale = math.max(width / pixelWidth, height / pixelHeight);
      final offsetX = (width - (pixelWidth * scale)) / 2;
      final offsetY = (height - (pixelHeight * scale)) / 2;

      canvas.drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = const Color(0xFF1B1C1F),
      );

      final tileCount =
          (maxTileX - minTileX + 1) * (maxTileY - minTileY + 1);
      if (tileCount > _maxMapTiles) {
        return null;
      }

      for (var tileX = minTileX; tileX <= maxTileX; tileX++) {
        for (var tileY = minTileY; tileY <= maxTileY; tileY++) {
          final tileImage = await _fetchTile(zoom, tileX, tileY);
          if (tileImage == null) {
            continue;
          }

          final destX = (((tileX * 256.0) - topLeft.dx) * scale) + offsetX;
          final destY = (((tileY * 256.0) - topLeft.dy) * scale) + offsetY;
          final destRect = Rect.fromLTWH(destX, destY, 256 * scale, 256 * scale);
          paintImage(
            canvas: canvas,
            rect: destRect,
            image: tileImage,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          );
          tileImage.dispose();
        }
      }

      final fullRect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      canvas.drawRect(
        fullRect,
        Paint()..color = Colors.black.withValues(alpha: 0.18),
      );
      canvas.drawRect(
        fullRect,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x127CA7FF), Color(0x10FFB457), Color(0x00000000)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(fullRect),
      );

      final picture = recorder.endRecording();
      return picture.toImage(width, height);
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image?> _fetchTile(int zoom, int x, int y) async {
    try {
      final response = await http.get(
        Uri.parse('https://tile.openstreetmap.org/$zoom/$x/$y.png'),
        headers: const {
          'User-Agent': 'DondePaso/1.0 (timelapse test)',
        },
      );
      if (response.statusCode != 200) {
        return null;
      }
      return _decodeImage(response.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  static int _chooseZoom({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required int width,
    required int height,
  }) {
    for (var zoom = 18; zoom >= 12; zoom--) {
      final topLeft = _latLonToWorldPixel(maxLat, minLon, zoom);
      final bottomRight = _latLonToWorldPixel(minLat, maxLon, zoom);
      final pixelWidth = (bottomRight.dx - topLeft.dx).abs();
      final pixelHeight = (bottomRight.dy - topLeft.dy).abs();
      final tileCount =
          ((bottomRight.dx / 256).floor() - (topLeft.dx / 256).floor() + 1) *
          ((bottomRight.dy / 256).floor() - (topLeft.dy / 256).floor() + 1);
      if (tileCount > _maxMapTiles) {
        continue;
      }
      if (pixelWidth <= width * 1.25 && pixelHeight <= height * 1.25) {
        return zoom;
      }
    }
    return 12;
  }

  static Offset _latLonToWorldPixel(double lat, double lon, int zoom) {
    final scale = 256.0 * math.pow(2, zoom).toDouble();
    final x = ((lon + 180.0) / 360.0) * scale;
    final sinLat = math.sin(lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
    final y =
        (0.5 -
            math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
        scale;
    return Offset(x, y);
  }

  static Future<ui.Image> _renderIntroFrame({
    required AppStrings strings,
    required double introRatio,
    required String zoneName,
    required FootprintTimelapseRange range,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, _canvasWidth, _canvasHeight),
    );
    final rect = const Rect.fromLTWH(0, 0, _canvasWidth, _canvasHeight);
    _paintBackdrop(canvas, rect, introRatio * 0.25, 0.62 + introRatio * 0.18);

    final fadeIn = math.min(1.0, introRatio / 0.42);
    final fadeOut = introRatio > 0.78 ? (1 - ((introRatio - 0.78) / 0.22)).clamp(0.0, 1.0) : 1.0;
    final alpha = (fadeIn * fadeOut).clamp(0.0, 1.0);

    final haloRect = Rect.fromCircle(
      center: const Offset(_canvasWidth / 2, 520),
      radius: 290,
    );
    canvas.drawOval(
      haloRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFC463).withValues(alpha: 0.12 * alpha),
            const Color(0x00000000),
          ],
        ).createShader(haloRect),
    );

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06 * alpha)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      const Offset(92, 300),
      const Offset(628, 300),
      linePaint,
    );
    canvas.drawLine(
      const Offset(92, 844),
      const Offset(628, 844),
      linePaint,
    );

    _paintText(
      canvas,
      strings.appTitle,
      const Offset(56, 92),
      38,
      FontWeight.w800,
      Colors.white.withValues(alpha: alpha),
      maxWidth: 608,
      shadow: Shadow(
        color: const Color(0xCC000000).withValues(alpha: alpha),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    );
    _paintText(
      canvas,
      strings.timelapseIntroOverline.toUpperCase(),
      const Offset(56, 218),
      18,
      FontWeight.w700,
      const Color(0xFF8FCBFF).withValues(alpha: alpha),
      maxWidth: 608,
      shadow: Shadow(
        color: const Color(0x77000000).withValues(alpha: alpha),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
    );
    _paintText(
      canvas,
      strings.timelapseIntroTitle,
      const Offset(56, 332),
      52,
      FontWeight.w800,
      const Color(0xFFFFE8A7).withValues(alpha: alpha),
      maxWidth: 608,
      shadow: Shadow(
        color: const Color(0xCC1A0B00).withValues(alpha: alpha),
        blurRadius: 28,
        offset: const Offset(0, 8),
      ),
    );
    _paintText(
      canvas,
      strings.timelapseIntroBody(zoneName, strings.timelapseRangeLabel(range)),
      const Offset(56, 600),
      24,
      FontWeight.w500,
      Colors.white.withValues(alpha: 0.78 * alpha),
      maxWidth: 560,
      shadow: Shadow(
        color: const Color(0xAA000000).withValues(alpha: alpha),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    );

    return recorder.endRecording().toImage(_canvasWidth.toInt(), _canvasHeight.toInt());
  }

  static Future<ui.Image> _renderFrame({
    required AppStrings strings,
    required List<_ProjectedTimelapseCell> visibleCells,
    required _TimelapseScene scene,
    required double revealRatio,
    required double pulse,
    required String zoneName,
    required int explorationPercent,
    required int totalPoints,
    required double knownKilometers,
    required FootprintTimelapseRange range,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, _canvasWidth, _canvasHeight),
    );

    final backgroundRect = const Rect.fromLTWH(0, 0, _canvasWidth, _canvasHeight);
    _paintBackdrop(canvas, backgroundRect, revealRatio, pulse);

    final mapRect = scene.mapRect;
    _paintMapWell(canvas, mapRect);
    _paintSceneBackdrop(canvas, scene, mapReveal: 0.0);
    _paintExplorationMass(
      canvas,
      mapRect: mapRect,
      cells: visibleCells,
      revealRatio: revealRatio,
      pulse: pulse,
      mapReveal: 0.0,
    );

    final latestPath = visibleCells.isNotEmpty ? visibleCells.last.path : null;
    if (latestPath != null) {
      final latestBounds = latestPath.getBounds();
      final focusRect = Rect.fromCircle(
        center: latestBounds.center,
        radius: math.max(latestBounds.longestSide * 2.2, 90),
      );
      canvas.drawOval(
        focusRect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFF2BC).withValues(alpha: 0.10 + revealRatio * 0.07),
              const Color(0xFFFFB348).withValues(alpha: 0.08 + pulse * 0.04),
              const Color(0x00000000),
            ],
            stops: const [0.0, 0.34, 1.0],
          ).createShader(focusRect)
          ..blendMode = BlendMode.screen,
      );
    }

    final progressRect = const Rect.fromLTWH(56, 1018, 608, 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(progressRect, const Radius.circular(999)),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(progressRect.left, progressRect.top, progressRect.width * revealRatio, progressRect.height),
        const Radius.circular(999),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFC04F), Color(0xFFFFF1B3)],
        ).createShader(progressRect),
    );

    _paintText(
      canvas,
      strings.appTitle,
      const Offset(56, 58),
      40,
      FontWeight.w800,
      Colors.white,
      maxWidth: 608,
      shadow: const Shadow(
        color: Color(0xCC000000),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
    );
    _paintText(
      canvas,
      strings.shareTimelapseOption.toUpperCase(),
      const Offset(56, 112),
      18,
      FontWeight.w700,
      const Color(0xFF8FCBFF),
      maxWidth: 608,
      shadow: const Shadow(
        color: Color(0x99000000),
        blurRadius: 12,
        offset: Offset(0, 3),
      ),
    );
    _paintText(
      canvas,
      strings.cityPromptTop,
      const Offset(56, 144),
      25,
      FontWeight.w500,
      Colors.white.withValues(alpha: 0.86),
      maxWidth: 608,
      shadow: const Shadow(
        color: Color(0xAA000000),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
    );
    _paintText(
      canvas,
      strings.cityPromptHighlight,
      const Offset(56, 178),
      40,
      FontWeight.w800,
      const Color(0xFFFFD57D),
      maxWidth: 608,
      shadow: const Shadow(
        color: Color(0xCC1A0B00),
        blurRadius: 22,
        offset: Offset(0, 6),
      ),
    );

    final sweepRect = Rect.fromLTWH(
      _mapLeft - 10 + (_mapRight - _mapLeft + 20) * revealRatio - 90,
      _mapTop - 8,
      160,
      _mapBottom - _mapTop + 16,
    );
    canvas.drawRect(
      sweepRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x00000000), Color(0x55FFF1C1), Color(0x00000000)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(sweepRect)
        ..blendMode = BlendMode.screen,
    );

    _paintPill(
      canvas,
      title: zoneName,
      value: '$explorationPercent%',
      origin: const Offset(56, 1052),
      width: 216,
      accent: const Color(0xFFFFD57D),
    );
    _paintPill(
      canvas,
      title: strings.points,
      value: strings.formatCompactNumber(totalPoints),
      origin: const Offset(286, 1052),
      width: 170,
      accent: const Color(0xFF7BE0FF),
    );
    _paintPill(
      canvas,
      title: strings.totalKnownKm,
      value: '${knownKilometers.toStringAsFixed(1)} km',
      origin: const Offset(470, 1052),
      width: 200,
      accent: const Color(0xFFB8FF8C),
    );

    _paintText(
      canvas,
      strings.timelapseShareBody(
        zoneName,
        explorationPercent,
        strings.timelapseRangeLabel(range),
      ),
      const Offset(56, 963),
      18,
      FontWeight.w500,
      Colors.white.withValues(alpha: 0.66),
      maxWidth: 608,
    );
    _paintText(
      canvas,
      '${strings.cityExploration} $explorationPercent%',
      const Offset(56, 988),
      21,
      FontWeight.w700,
      Colors.white,
      maxWidth: 608,
      shadow: const Shadow(
        color: Color(0x99000000),
        blurRadius: 10,
        offset: Offset(0, 3),
      ),
    );

    return recorder.endRecording().toImage(_canvasWidth.toInt(), _canvasHeight.toInt());
  }

  static Future<ui.Image> _renderHeroFrame({
    required AppStrings strings,
    required List<_ProjectedTimelapseCell> visibleCells,
    required _TimelapseScene scene,
    required double heroRatio,
    required double pulse,
    required String zoneName,
    required int explorationPercent,
    required int totalPoints,
    required double knownKilometers,
    required FootprintTimelapseRange range,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, _canvasWidth, _canvasHeight),
    );
    final backgroundRect = const Rect.fromLTWH(0, 0, _canvasWidth, _canvasHeight);
    _paintBackdrop(canvas, backgroundRect, 1.0, pulse);

    final mapRect = scene.mapRect;
    _paintMapWell(canvas, mapRect);
    final mapReveal = 0.25 + heroRatio * 0.75;
    _paintSceneBackdrop(canvas, scene, mapReveal: mapReveal);
    _paintExplorationMass(
      canvas,
      mapRect: mapRect,
      cells: visibleCells,
      revealRatio: 1,
      pulse: pulse,
      mapReveal: mapReveal,
    );

    final heroAlpha = (0.72 + heroRatio * 0.28).clamp(0.0, 1.0);
    final heroHaloRect = Rect.fromCircle(
      center: const Offset(_canvasWidth / 2, 430),
      radius: 260 + (pulse * 45),
    );
    canvas.drawOval(
      heroHaloRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFD57D).withValues(alpha: 0.10 * heroAlpha),
            const Color(0x00000000),
          ],
        ).createShader(heroHaloRect),
    );

    _paintText(
      canvas,
      strings.timelapseHeroTitle,
      const Offset(56, 84),
      42,
      FontWeight.w800,
      const Color(0xFFFFF1C0).withValues(alpha: heroAlpha),
      maxWidth: 608,
      shadow: const Shadow(
        color: Color(0xCC1A0B00),
        blurRadius: 24,
        offset: Offset(0, 8),
      ),
    );
    _paintText(
      canvas,
      strings.timelapseHeroBody(
        zoneName,
        explorationPercent,
        strings.timelapseRangeLabel(range),
      ),
      const Offset(56, 146),
      22,
      FontWeight.w500,
      Colors.white.withValues(alpha: 0.78 * heroAlpha),
      maxWidth: 608,
      shadow: const Shadow(
        color: Color(0xAA000000),
        blurRadius: 12,
        offset: Offset(0, 4),
      ),
    );
    _paintText(
      canvas,
      '$explorationPercent%',
      const Offset(56, 1000),
      86,
      FontWeight.w800,
      const Color(0xFFFFE9A8).withValues(alpha: heroAlpha),
      maxWidth: 300,
      shadow: const Shadow(
        color: Color(0xCC1A0B00),
        blurRadius: 28,
        offset: Offset(0, 8),
      ),
    );
    _paintText(
      canvas,
      strings.cityExploration,
      const Offset(300, 1028),
      20,
      FontWeight.w700,
      Colors.white.withValues(alpha: 0.72 * heroAlpha),
      maxWidth: 220,
    );

    _paintPill(
      canvas,
      title: strings.points,
      value: strings.formatCompactNumber(totalPoints),
      origin: const Offset(56, 1120),
      width: 178,
      accent: const Color(0xFF7BE0FF),
    );
    _paintPill(
      canvas,
      title: strings.totalKnownKm,
      value: '${knownKilometers.toStringAsFixed(1)} km',
      origin: const Offset(248, 1120),
      width: 188,
      accent: const Color(0xFFB8FF8C),
    );
    _paintPill(
      canvas,
      title: zoneName,
      value: strings.timelapseIntroOverline,
      origin: const Offset(450, 1120),
      width: 214,
      accent: const Color(0xFFFFD57D),
    );

    return recorder.endRecording().toImage(_canvasWidth.toInt(), _canvasHeight.toInt());
  }

  static void _paintBackdrop(Canvas canvas, Rect rect, double revealRatio, double pulse) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF020304), Color(0xFF05070B), Color(0xFF020202)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );

    final spotlightRect = Rect.fromCircle(
      center: Offset(rect.width * 0.54, rect.height * 0.47),
      radius: 420,
    );
    canvas.drawOval(
      spotlightRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFB145).withValues(
              alpha: 0.07 + revealRatio * 0.04 + pulse * 0.02,
            ),
            const Color(0x00000000),
          ],
        ).createShader(spotlightRect),
    );

    final coolRect = Rect.fromCircle(
      center: Offset(rect.width * 0.2, rect.height * 0.2),
      radius: 320,
    );
    canvas.drawOval(
      coolRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x223F7BEA), Color(0x00000000)],
        ).createShader(coolRect),
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (double x = 24; x < rect.width; x += 46) {
      canvas.drawLine(Offset(x, 0), Offset(x, rect.height), gridPaint);
    }
    for (double y = 20; y < rect.height; y += 46) {
      canvas.drawLine(Offset(0, y), Offset(rect.width, y), gridPaint);
    }

    final scanPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.018)
      ..strokeWidth = 1;
    for (double y = 0; y < rect.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(rect.width, y), scanPaint);
    }

    final edgeFogRect = rect.inflate(24);
    canvas.drawRect(
      edgeFogRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x00000000), Color(0xE0000000)],
          stops: [0.52, 1.0],
        ).createShader(edgeFogRect),
    );
  }

  static void _paintMapWell(Canvas canvas, Rect rect) {
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(42));
    canvas.drawRRect(
      rounded,
      Paint()..color = Colors.white.withValues(alpha: 0.03),
    );
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    final vignetteRect = rect.inflate(28);
    canvas.drawRRect(
      RRect.fromRectAndRadius(vignetteRect, const Radius.circular(52)),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x00000000), Color(0xA8000000)],
          stops: [0.58, 1.0],
        ).createShader(vignetteRect),
    );
  }

  static void _paintMapBaseLayer(
    Canvas canvas, {
    required Rect mapRect,
    required List<({FootprintCell cell, ui.Path path})> cells,
  }) {
    if (cells.isEmpty) {
      return;
    }

    final roadPaint = Paint()
      ..color = const Color(0xFF8E8E8E).withValues(alpha: 0.14)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final arterialPaint = Paint()
      ..color = const Color(0xFFCFCFCF).withValues(alpha: 0.10)
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final parcelPaint = Paint()
      ..color = const Color(0xFF6E6E6E).withValues(alpha: 0.055)
      ..style = PaintingStyle.fill;

    final centers = cells
        .map((entry) => entry.path.getBounds().center)
        .toList(growable: false);

    for (final entry in cells) {
      canvas.drawPath(entry.path, parcelPaint);
      canvas.drawPath(entry.path, roadPaint);
    }

    for (var i = 0; i < centers.length; i++) {
      for (var j = i + 1; j < centers.length; j++) {
        final start = centers[i];
        final end = centers[j];
        final distance = (start - end).distance;
        if (distance > 86) {
          continue;
        }

        final ratio = (1 - (distance / 86)).clamp(0.0, 1.0);
        final paint = ratio > 0.62 ? arterialPaint : roadPaint;
        final path = ui.Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
        canvas.drawPath(
          path,
          Paint()
            ..color = paint.color.withValues(
              alpha: paint.color.a * (0.42 + ratio * 0.58),
            )
            ..strokeWidth = paint.strokeWidth * (0.82 + ratio * 0.28)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    final vignette = mapRect.deflate(8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(vignette, const Radius.circular(30)),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x00000000), Color(0x5A000000)],
          stops: [0.58, 1.0],
        ).createShader(vignette),
    );
  }

  static void _paintSceneBackdrop(
    Canvas canvas,
    _TimelapseScene scene, {
    required double mapReveal,
  }) {
    if (scene.mapImage != null) {
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(scene.mapRect, const Radius.circular(42)),
      );
      if (mapReveal > 0) {
        paintImage(
          canvas: canvas,
          rect: scene.mapRect,
          image: scene.mapImage!,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        );
      }
      canvas.drawRect(
        scene.mapRect,
        Paint()..color = Colors.black.withValues(alpha: 0.72 - (mapReveal * 0.52)),
      );
      canvas.restore();
      _paintMapAttribution(canvas, scene.mapRect);
      return;
    }

    _paintMapBaseLayer(
      canvas,
      mapRect: scene.mapRect,
      cells: scene.cells
          .map((entry) => (cell: entry.cell, path: entry.path))
          .toList(growable: false),
    );
  }

  static void _paintMapAttribution(Canvas canvas, Rect mapRect) {
    final painter = TextPainter(
      text: TextSpan(
        text: '© OpenStreetMap',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.34),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        mapRect.right - painter.width - 10,
        mapRect.bottom - painter.height - 8,
      ),
    );
  }

  static ui.Path _buildProjectedPath(List<Offset> boundary) {
    final path = ui.Path()..moveTo(boundary.first.dx, boundary.first.dy);
    for (final point in boundary.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    return path;
  }

  static void _paintExplorationMass(
    Canvas canvas, {
    required Rect mapRect,
    required List<_ProjectedTimelapseCell> cells,
    required double revealRatio,
    required double pulse,
    required double mapReveal,
  }) {
    if (cells.isEmpty) {
      return;
    }

    ui.Path unionPath = cells.first.path;
    for (final entry in cells.skip(1)) {
      unionPath = ui.Path.combine(ui.PathOperation.union, unionPath, entry.path);
    }

    canvas.drawPath(
      unionPath,
      Paint()
        ..color = const Color(0xFFFFA11A).withValues(
          alpha: (0.11 + revealRatio * 0.07 + pulse * 0.025) * (1 - mapReveal * 0.28),
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          54 + pulse * 8,
        ),
    );
    canvas.drawPath(
      unionPath,
      Paint()
        ..color = const Color(0xFFFFCE66).withValues(alpha: 0.09 * (1 - mapReveal * 0.22))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    canvas.save();
    canvas.clipPath(unionPath);
    canvas.drawRect(
      mapRect,
      Paint()
        ..color = Colors.white.withValues(
          alpha: (0.06 + revealRatio * 0.05 + pulse * 0.02) * (1 - mapReveal * 0.35),
        )
        ..blendMode = BlendMode.screen,
    );
    canvas.drawRect(
      mapRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x33FFF1C1), Color(0x1AFFF8EB), Color(0x22FFB03B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(mapRect)
        ..blendMode = BlendMode.screen,
    );
    canvas.restore();

    for (var index = 0; index < cells.length; index++) {
      final entry = cells[index];
      final cell = entry.cell;
      final intensity = (0.34 + math.min(0.56, (cell.visits - 1) * 0.05))
          .clamp(0.34, 0.94);
      final isRecent = index >= math.max(0, cells.length - 4);
      final contrastBoost = mapReveal.clamp(0.0, 1.0);

      final fillColor = Color.lerp(
        const Color(0xFF4D4434),
        const Color(0xFFB69D70),
        intensity,
      )!;
      final borderColor = Color.lerp(
        const Color(0xFF6B4A18),
        const Color(0xFFF0BF68),
        intensity,
      )!;
      final darkEdgeColor = Color.lerp(
        const Color(0xFF1A1206),
        const Color(0xFF3B2B11),
        intensity,
      )!;

      canvas.drawPath(
        entry.path,
        Paint()
          ..color = borderColor.withValues(alpha: isRecent ? 0.18 : 0.12)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            isRecent ? 28 + pulse * 12 : 18,
          ),
      );
      canvas.drawPath(
        entry.path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = fillColor.withValues(
            alpha: ((isRecent ? 0.24 + pulse * 0.03 : 0.18) *
                    (1 - mapReveal * 0.16)) +
                (0.10 * contrastBoost),
          )
          ..blendMode = BlendMode.srcOver,
      );
      canvas.drawPath(
        entry.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (isRecent ? 3.6 : 2.4) + (contrastBoost * 0.65)
          ..color = darkEdgeColor.withValues(
            alpha: ((isRecent ? 0.62 : 0.48) * (1 - mapReveal * 0.05)) +
                (0.10 * contrastBoost),
          ),
      );
      canvas.drawPath(
        entry.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (isRecent ? 2.15 : 1.4) + (contrastBoost * 0.4)
          ..color = borderColor.withValues(
            alpha: ((isRecent ? 0.86 + pulse * 0.08 : 0.54) *
                    (1 - mapReveal * 0.04)) +
                (0.10 * contrastBoost),
          ),
      );
    }

    final recentPath = cells
        .skip(math.max(0, cells.length - 4))
        .map((entry) => entry.path)
        .fold<ui.Path?>(null, (combined, path) {
          if (combined == null) {
            return path;
          }
          return ui.Path.combine(ui.PathOperation.union, combined, path);
        });
    if (recentPath != null) {
      canvas.drawPath(
        recentPath,
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.11 + revealRatio * 0.11)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 42),
      );
    }

    final cutoutRect = mapRect.deflate(12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cutoutRect, const Radius.circular(34)),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x00000000), Color(0x88000000)],
          stops: [0.64, 1.0],
        ).createShader(cutoutRect),
    );
  }

  static void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize,
    FontWeight fontWeight,
    Color color,
    {double maxWidth = 608,
    Shadow? shadow,}
  ) {
    final shadows = shadow == null ? null : [shadow];
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: -0.4,
          shadows: shadows,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  static void _paintPill(
    Canvas canvas, {
    required String title,
    required String value,
    required Offset origin,
    required double width,
    required Color accent,
  }) {
    final rect = Rect.fromLTWH(origin.dx, origin.dy, width, 116);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.48),
            Colors.black.withValues(alpha: 0.26),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.08),
    );
    _paintText(canvas, title, Offset(origin.dx + 16, origin.dy + 16), 18, FontWeight.w600, accent);
    _paintText(canvas, value, Offset(origin.dx + 16, origin.dy + 48), 28, FontWeight.w800, Colors.white);
  }

  static Future<void> _shareVideo({
    required AppStrings strings,
    required String encodedPath,
    required String zoneName,
    required int explorationPercent,
    required FootprintTimelapseRange range,
  }) async {
    final body = strings.timelapseShareBody(
      zoneName,
      explorationPercent,
      strings.timelapseRangeLabel(range),
    );

    if (FootprintMediaStore.isSupported) {
      final uri = await FootprintMediaStore.saveToGallery(
        sourcePath: encodedPath,
        mimeType: 'video/mp4',
        displayName: _buildDisplayName('dondepaso_timelapse', '.mp4'),
      );
      if (uri != null) {
        await FootprintMediaStore.shareSavedMedia(
          uri: uri,
          mimeType: 'video/mp4',
          text: body,
          title: strings.shareTimelapseOption,
        );
        return;
      }
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(encodedPath, mimeType: 'video/mp4')],
        text: body,
        title: strings.shareTimelapseOption,
      ),
    );
  }

  static Future<void> _shareImage({
    required AppStrings strings,
    required String imagePath,
    required String zoneName,
    required int explorationPercent,
    required FootprintTimelapseRange range,
    bool isMapCard = false,
  }) async {
    final body = isMapCard
        ? strings.shareMapBody(zoneName, explorationPercent)
        : strings.timelapseShareBody(
            zoneName,
            explorationPercent,
            strings.timelapseRangeLabel(range),
          );
    final title =
        isMapCard ? strings.shareMapTitle : strings.shareTimelapseOption;

    if (FootprintMediaStore.isSupported) {
      final uri = await FootprintMediaStore.saveToGallery(
        sourcePath: imagePath,
        mimeType: 'image/png',
        displayName: _buildDisplayName(
          isMapCard ? 'dondepaso_card' : 'dondepaso_timelapse',
          '.png',
        ),
      );
      if (uri != null) {
        await FootprintMediaStore.shareSavedMedia(
          uri: uri,
          mimeType: 'image/png',
          text: body,
          title: title,
        );
        return;
      }
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(imagePath, mimeType: 'image/png')],
        text: body,
        title: title,
      ),
    );
  }

  static Future<void> _saveImageToGallery({
    required String imagePath,
    required String displayName,
  }) async {
    if (FootprintMediaStore.isSupported) {
      final savedUri = await FootprintMediaStore.saveToGallery(
        sourcePath: imagePath,
        mimeType: 'image/png',
        displayName: displayName,
      );
      if (savedUri != null) {
        return;
      }
    }
  }

  static Future<void> _saveVideoToGallery(String encodedPath) async {
    if (FootprintMediaStore.isSupported) {
      final savedUri = await FootprintMediaStore.saveToGallery(
        sourcePath: encodedPath,
        mimeType: 'video/mp4',
        displayName: _buildDisplayName('dondepaso_timelapse', '.mp4'),
      );
      if (savedUri != null) {
        return;
      }
    }
  }

  static String _buildDisplayName(String prefix, String extension) {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return '${prefix}_$stamp$extension';
  }

  static Future<String?> _prepareSoundtrackFile() async {
    try {
      final byteData = await rootBundle.load(_soundtrackAsset);
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}dondepaso_soundtrack.mp3',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}

class _ProjectedTimelapseCell {
  const _ProjectedTimelapseCell({required this.cell, required this.path});

  final FootprintCell cell;
  final ui.Path path;
}

class _TimelapseScene {
  const _TimelapseScene({
    required this.cells,
    required this.mapRect,
    required this.mapImage,
  });

  final List<_ProjectedTimelapseCell> cells;
  final Rect mapRect;
  final ui.Image? mapImage;

  void dispose() {
    mapImage?.dispose();
  }
}
