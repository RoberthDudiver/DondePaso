import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'footprint_block_model.dart';
import 'footprint_progress.dart';
import 'footprint_transport.dart';

class FootprintBlockLayer extends StatelessWidget {
  const FootprintBlockLayer({
    super.key,
    required this.blocks,
    required this.now,
    required this.lightMapMode,
  });

  final List<CapturedBlockSnapshot> blocks;
  final DateTime now;
  final bool lightMapMode;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final cameraSize = camera.size;
    if (!cameraSize.width.isFinite || !cameraSize.height.isFinite) {
      return const SizedBox.shrink();
    }

    return MobileLayerTransformer(
      child: CustomPaint(
        size: cameraSize,
        painter: _BlockPainter(
          camera: camera,
          blocks: blocks,
          now: now,
          lightMapMode: lightMapMode,
        ),
      ),
    );
  }
}

class _BlockPainter extends CustomPainter {
  const _BlockPainter({
    required this.camera,
    required this.blocks,
    required this.now,
    required this.lightMapMode,
  });

  final MapCamera camera;
  final List<CapturedBlockSnapshot> blocks;
  final DateTime now;
  final bool lightMapMode;

  @override
  void paint(Canvas canvas, Size size) {
    final viewportRect = Offset.zero & size;

    // Batch visible block paths into walking/vehicle groups.
    final walkingPaths = ui.Path();
    final vehiclePaths = ui.Path();
    var hasWalking = false;
    var hasVehicle = false;

    for (final block in blocks) {
      final lastSeen = block.lastSeen;
      if (lastSeen == null) continue;

      final freshness =
          1 -
          (now.difference(lastSeen).inSeconds / footprintForgetAfter.inSeconds);
      if (freshness <= 0) continue;

      final path = _polygonPath(block);
      if (path == null || !path.getBounds().overlaps(viewportRect)) continue;

      if (block.transportMode == FootprintTransportMode.vehicle) {
        vehiclePaths.addPath(path, Offset.zero);
        hasVehicle = true;
      } else {
        walkingPaths.addPath(path, Offset.zero);
        hasWalking = true;
      }
    }

    final blurRadius = lightMapMode ? 10.0 : 14.0;

    if (hasWalking) {
      final color = lightMapMode
          ? const Color(0xFFB95F18)
          : const Color(0xFFFF8844);
      canvas.drawPath(
        walkingPaths,
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius)
          ..color = color.withValues(alpha: lightMapMode ? 0.12 : 0.22),
      );
      canvas.drawPath(
        walkingPaths,
        Paint()
          ..blendMode = BlendMode.srcOver
          ..color = color.withValues(alpha: lightMapMode ? 0.16 : 0.28),
      );
      canvas.drawPath(
        walkingPaths,
        Paint()
          ..blendMode = BlendMode.srcOver
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = color.withValues(alpha: lightMapMode ? 0.20 : 0.22),
      );
    }

    if (hasVehicle) {
      final color = lightMapMode
          ? const Color(0xFF3C85D8)
          : const Color(0xFF88CCFF);
      canvas.drawPath(
        vehiclePaths,
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius)
          ..color = color.withValues(alpha: lightMapMode ? 0.12 : 0.22),
      );
      canvas.drawPath(
        vehiclePaths,
        Paint()
          ..blendMode = BlendMode.srcOver
          ..color = color.withValues(alpha: lightMapMode ? 0.16 : 0.28),
      );
      canvas.drawPath(
        vehiclePaths,
        Paint()
          ..blendMode = BlendMode.srcOver
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: lightMapMode ? 0.30 : 0.32),
      );
    }
  }

  ui.Path? _polygonPath(CapturedBlockSnapshot block) {
    if (block.points.length < 3) {
      return null;
    }

    final projected = block.points
        .map((point) => camera.projectAtZoom(point) - camera.pixelOrigin)
        .toList(growable: false);
    if (projected.length < 3) {
      return null;
    }

    final path = ui.Path()..moveTo(projected.first.dx, projected.first.dy);
    for (final point in projected.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _BlockPainter oldDelegate) {
    return oldDelegate.blocks != blocks ||
        oldDelegate.now != now ||
        oldDelegate.lightMapMode != lightMapMode ||
        oldDelegate.camera.center != camera.center ||
        oldDelegate.camera.zoom != camera.zoom;
  }
}
