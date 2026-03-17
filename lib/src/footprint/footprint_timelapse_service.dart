import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../i18n/app_strings.dart';
import 'footprint_cell.dart';
import 'footprint_h3_grid.dart';
import 'footprint_timelapse_range.dart';

class FootprintTimelapseService {
  FootprintTimelapseService._();

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
    final audioTrack = await _prepareAudioTrack(workingDirectory);

    final frameFiles = await _renderFrames(
      strings: strings,
      cells: sortedCells,
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
    final file = await _encodeVideo(
      workingDirectory: workingDirectory,
      frameCount: frameFiles.length,
      audioTrack: audioTrack,
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'video/mp4')],
        text: strings.timelapseShareBody(
          zoneName,
          explorationPercent,
          strings.timelapseRangeLabel(range),
        ),
        title: strings.shareTimelapseOption,
      ),
    );

    if (workingDirectory.existsSync()) {
      await workingDirectory.delete(recursive: true);
    }
  }

  static Future<List<File>> _renderFrames({
    required AppStrings strings,
    required List<FootprintCell> cells,
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
      final visibleCount = math.max(1, (cells.length * revealRatio).round());
      final uiImage = await _renderFrame(
        strings: strings,
        visibleCells: cells.take(visibleCount).toList(growable: false),
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
        visibleCells: cells,
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

  static double _easeOut(double value) {
    final inverse = 1 - value;
    return 1 - inverse * inverse * inverse;
  }

  static double _musicPulse(double progress) {
    final phase = progress * math.pi * 8.0;
    final pulse = (math.sin(phase) * 0.5) + 0.5;
    return 0.58 + (pulse * 0.42);
  }

  static Future<File> _encodeVideo({
    required Directory workingDirectory,
    required int frameCount,
    required File? audioTrack,
  }) async {
    if (frameCount == 0) {
      throw StateError('No timelapse frames were generated.');
    }

    final outputFile = File(
      '${workingDirectory.path}${Platform.pathSeparator}dondepaso_timelapse.mp4',
    );
    if (outputFile.existsSync()) {
      await outputFile.delete();
    }

    final framesInput =
        '${workingDirectory.path}${Platform.pathSeparator}frame_%03d.png';
    final commandParts = [
      '-y',
      '-framerate',
      '$_fps',
      '-i',
      '"$framesInput"',
    ];
    if (audioTrack != null && audioTrack.existsSync()) {
      final durationSeconds = frameCount / _fps;
      final fadeOutStart = math.max(0.0, durationSeconds - 0.9);
      commandParts.addAll([
        '-stream_loop',
        '-1',
        '-i',
        '"${audioTrack.path}"',
        '-af',
        '"afade=t=in:st=0:d=0.55,afade=t=out:st=${fadeOutStart.toStringAsFixed(2)}:d=0.85,volume=0.95"',
      ]);
    }
    commandParts.addAll([
      '-map',
      '0:v:0',
      if (audioTrack != null && audioTrack.existsSync()) ...[
        '-map',
        '1:a:0',
      ],
      '-vf',
      '"format=yuv420p,scale=720:1280:flags=lanczos,fps=$_fps"',
      '-c:v',
      'mpeg4',
      '-q:v',
      '3',
      if (audioTrack != null && audioTrack.existsSync()) ...[
        '-c:a',
        'aac',
        '-b:a',
        '160k',
        '-shortest',
      ],
      '-movflags',
      '+faststart',
      '"${outputFile.path}"',
    ]);
    final command = commandParts.join(' ');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode) || !outputFile.existsSync()) {
      final logs = await session.getAllLogsAsString();
      throw StateError('Timelapse video encoding failed: ${logs ?? 'unknown'}');
    }
    return outputFile;
  }

  static Future<File?> _prepareAudioTrack(Directory workingDirectory) async {
    try {
      final byteData = await rootBundle.load('DOndePAso1.mp3');
      final audioFile = File(
        '${workingDirectory.path}${Platform.pathSeparator}dondepaso_audio.mp3',
      );
      await audioFile.writeAsBytes(
        byteData.buffer.asUint8List(),
        flush: true,
      );
      return audioFile;
    } catch (_) {
      return null;
    }
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
    required List<FootprintCell> visibleCells,
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

    final sortedBoundaries = visibleCells
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
    final cinematicZoom = 1.28 - (revealRatio * 0.16);
    final paddedLatSpan = latSpan * cinematicZoom;
    final paddedLonSpan = lonSpan * cinematicZoom;
    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;
    final mapWidth = _mapRight - _mapLeft;
    final mapHeight = _mapBottom - _mapTop;

    Offset project(double lat, double lon) {
      final x = ((lon - (centerLon - paddedLonSpan / 2)) / paddedLonSpan) * mapWidth;
      final y = ((centerLat + paddedLatSpan / 2 - lat) / paddedLatSpan) * mapHeight;
      return Offset(_mapLeft + x, _mapTop + y);
    }

    final mapRect = Rect.fromLTWH(_mapLeft, _mapTop, mapWidth, mapHeight);
    _paintMapWell(canvas, mapRect);

    final projectedCells = sortedBoundaries
        .map(
          (entry) => (
            cell: entry.cell,
            path: _buildProjectedPath(
              entry.boundary
                  .map((point) => project(point.latitude, point.longitude))
                  .toList(growable: false),
            ),
          ),
        )
        .toList(growable: false);
    _paintMapBaseLayer(
      canvas,
      mapRect: mapRect,
      cells: projectedCells,
    );
    _paintExplorationMass(
      canvas,
      mapRect: mapRect,
      cells: projectedCells,
      revealRatio: revealRatio,
      pulse: pulse,
    );

    final latestPath = projectedCells.isNotEmpty ? projectedCells.last.path : null;
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
    required List<FootprintCell> visibleCells,
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

    final sortedBoundaries = visibleCells
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
    final latSpan = math.max(0.0006, maxLat - minLat) * 1.02;
    final lonSpan = math.max(0.0006, maxLon - minLon) * 1.02;
    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;
    final mapWidth = _mapRight - _mapLeft;
    final mapHeight = _mapBottom - _mapTop;

    Offset project(double lat, double lon) {
      final x = ((lon - (centerLon - lonSpan / 2)) / lonSpan) * mapWidth;
      final y = ((centerLat + latSpan / 2 - lat) / latSpan) * mapHeight;
      return Offset(_mapLeft + x, _mapTop + y);
    }

    final mapRect = Rect.fromLTWH(_mapLeft, _mapTop, mapWidth, mapHeight);
    _paintMapWell(canvas, mapRect);
    final projectedCells = sortedBoundaries
        .map(
          (entry) => (
            cell: entry.cell,
            path: _buildProjectedPath(
              entry.boundary
                  .map((point) => project(point.latitude, point.longitude))
                  .toList(growable: false),
            ),
          ),
        )
        .toList(growable: false);
    _paintMapBaseLayer(
      canvas,
      mapRect: mapRect,
      cells: projectedCells,
    );
    _paintExplorationMass(
      canvas,
      mapRect: mapRect,
      cells: projectedCells,
      revealRatio: 1,
      pulse: pulse,
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
    required List<({FootprintCell cell, ui.Path path})> cells,
    required double revealRatio,
    required double pulse,
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
          alpha: 0.11 + revealRatio * 0.07 + pulse * 0.025,
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          54 + pulse * 8,
        ),
    );
    canvas.drawPath(
      unionPath,
      Paint()
        ..color = const Color(0xFFFFCE66).withValues(alpha: 0.09)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    for (var index = 0; index < cells.length; index++) {
      final entry = cells[index];
      final cell = entry.cell;
      final intensity = (0.34 + math.min(0.56, (cell.visits - 1) * 0.05))
          .clamp(0.34, 0.94);
      final isRecent = index >= math.max(0, cells.length - 4);

      final fillColor = Color.lerp(
        const Color(0xFF777777),
        const Color(0xFFF9F7F0),
        intensity,
      )!;
      final borderColor = Color.lerp(
        const Color(0xFFFF9C1A),
        const Color(0xFFFFE7A1),
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
          ..color = fillColor.withValues(alpha: isRecent ? 0.86 + pulse * 0.04 : 0.78),
      );
      canvas.drawPath(
        entry.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isRecent ? 2.2 : 1.15
          ..color = borderColor.withValues(alpha: isRecent ? 0.74 + pulse * 0.10 : 0.28),
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
}
