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
    for (final block in blocks) {
      final lastSeen = block.lastSeen;
      if (lastSeen == null) {
        continue;
      }
      final freshness =
          1 -
          (now.difference(lastSeen).inSeconds / footprintForgetAfter.inSeconds);
      final clampedFreshness = freshness.clamp(0, 1).toDouble();
      if (clampedFreshness <= 0) {
        continue;
      }

      final path = _polygonPath(block);
      if (path == null || !path.getBounds().overlaps(Offset.zero & size)) {
        continue;
      }

      final intensity =
          (0.28 +
                  (block.coverageRatio * 0.42) +
                  (clampedFreshness * 0.20) +
                  ((block.visits.clamp(1, 8) - 1) * 0.04))
              .clamp(0.24, 0.92);

      final isVehicle = block.transportMode == FootprintTransportMode.vehicle;
      final fillColor = lightMapMode
          ? Color.lerp(
              isVehicle ? const Color(0xFF173D68) : const Color(0xFF8C2F00),
              isVehicle ? const Color(0xFF3C85D8) : const Color(0xFFB95F18),
              intensity,
            )!
          : Color.lerp(
              isVehicle ? const Color(0xFF2A7DCC) : const Color(0xFFFF4A14),
              isVehicle ? const Color(0xFFD7EEFF) : const Color(0xFFFFF4C1),
              intensity,
            )!;

      canvas.drawPath(
        path,
        Paint()
          ..blendMode = lightMapMode ? BlendMode.plus : BlendMode.plus
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            lightMapMode ? 10.0 : 14.0,
          )
          ..color = fillColor.withValues(
            alpha: lightMapMode
                ? 0.10 + (clampedFreshness * 0.05)
                : 0.18 + (clampedFreshness * 0.10),
          ),
      );

      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.srcOver
          ..color = fillColor.withValues(
            alpha: lightMapMode
                ? 0.14 + (clampedFreshness * 0.06)
                : 0.22 + (clampedFreshness * 0.12),
          ),
      );

      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.srcOver
          ..style = PaintingStyle.stroke
          ..strokeWidth = isVehicle ? 1.4 : 1.0
          ..color = fillColor.withValues(
            alpha: lightMapMode
                ? (isVehicle ? 0.28 : 0.18) + (clampedFreshness * 0.06)
                : (isVehicle ? 0.30 : 0.18) + (clampedFreshness * 0.08),
          ),
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
