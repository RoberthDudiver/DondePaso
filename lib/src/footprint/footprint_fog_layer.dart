import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'footprint_cell.dart';
import 'footprint_h3_grid.dart';

class FootprintFogLayer extends StatelessWidget {
  const FootprintFogLayer({
    super.key,
    required this.cells,
    required this.currentLocation,
    required this.now,
    required this.forgetAfter,
    required this.revealMeters,
  });

  final List<FootprintCell> cells;
  final LatLng? currentLocation;
  final DateTime now;
  final Duration forgetAfter;
  final double revealMeters;

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
        painter: _FogPainter(
          camera: camera,
          cells: cells,
          currentLocation: currentLocation,
          now: now,
          forgetAfter: forgetAfter,
          revealMeters: revealMeters,
        ),
      ),
    );
  }
}

class _FogPainter extends CustomPainter {
  const _FogPainter({
    required this.camera,
    required this.cells,
    required this.currentLocation,
    required this.now,
    required this.forgetAfter,
    required this.revealMeters,
  });

  final MapCamera camera;
  final List<FootprintCell> cells;
  final LatLng? currentLocation;
  final DateTime now;
  final Duration forgetAfter;
  final double revealMeters;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());

    canvas.drawRect(
      bounds,
      Paint()..color = const Color(0xFF020202).withValues(alpha: 0.97),
    );

    for (final cell in cells) {
      final freshness = _freshness(cell);
      if (freshness <= 0) {
        continue;
      }

      if (cell.isH3) {
        final path = _pathForHexCell(cell);
        if (path != null) {
          final clarity = (freshness *
                  (0.28 +
                      (cell.visits.clamp(1, 10) * 0.045) +
                      ((cell.coverageWeight - 1) * 0.12)))
              .clamp(0.18, 0.78);
          final blurRadius = (14 + (cell.visits.clamp(1, 8) * 2.4)).toDouble();
          final edgeWidth = (8 + (cell.visits.clamp(1, 8) * 1.0)).toDouble();
          canvas.drawPath(
            path,
            Paint()
              ..blendMode = BlendMode.dstOut
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius)
              ..color = Colors.white.withValues(alpha: clarity * 0.18),
          );
          canvas.drawPath(
            path,
            Paint()
              ..blendMode = BlendMode.dstOut
              ..style = PaintingStyle.stroke
              ..strokeWidth = edgeWidth
              ..maskFilter = MaskFilter.blur(
                BlurStyle.normal,
                blurRadius * 0.62,
              )
              ..color = Colors.white.withValues(alpha: clarity * 0.54),
          );
          canvas.drawPath(
            path,
            Paint()
              ..blendMode = BlendMode.dstOut
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8
              ..color = Colors.white.withValues(alpha: clarity * 0.22),
          );
        }
        continue;
      }

      final center = camera.projectAtZoom(cell.latLng) - camera.pixelOrigin;
      final radius = _pixelRadiusForMeters(
        revealMeters + (cell.visits.clamp(0, 6) * 1.5),
        cell.latLng,
      );

      if (!_isVisible(center, radius, size)) {
        continue;
      }

      final clarity = (freshness * (0.58 + (cell.visits * 0.08))).clamp(
        0.16,
        0.96,
      );

      final shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: clarity),
          Colors.white.withValues(alpha: clarity * 0.45),
          Colors.transparent,
        ],
        stops: const [0, 0.48, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = shader,
      );
    }

    if (currentLocation != null) {
      final center =
          camera.projectAtZoom(currentLocation!) - camera.pixelOrigin;
      final radius = _pixelRadiusForMeters(
        revealMeters * 0.6,
        currentLocation!,
      );

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.72),
              Colors.white.withValues(alpha: 0.26),
              Colors.transparent,
            ],
            stops: const [0, 0.42, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    canvas.restore();
  }

  double _freshness(FootprintCell cell) {
    final ratio =
        1 - (now.difference(cell.lastSeen).inSeconds / forgetAfter.inSeconds);
    return ratio.clamp(0, 1).toDouble();
  }

  ui.Path? _pathForHexCell(FootprintCell cell) {
    final points = FootprintH3Grid.boundaryForCell(cell);
    if (points.isEmpty) {
      return null;
    }

    final projectedPoints = points
        .map((point) => camera.projectAtZoom(point) - camera.pixelOrigin)
        .toList(growable: false);
    if (projectedPoints.length < 3) {
      return null;
    }

    final path = ui.Path();
    for (var index = 0; index < projectedPoints.length; index++) {
      if (index == 0) {
        path.moveTo(projectedPoints[index].dx, projectedPoints[index].dy);
      } else {
        path.lineTo(projectedPoints[index].dx, projectedPoints[index].dy);
      }
    }

    path.close();
    return path;
  }

  double _pixelRadiusForMeters(num meters, LatLng point) {
    final latitudeStep = meters.toDouble() / 111320;
    final probe = LatLng(point.latitude + latitudeStep, point.longitude);
    final top = camera.projectAtZoom(point);
    final shifted = camera.projectAtZoom(probe);
    return (top.dy - shifted.dy).abs().clamp(8, 32).toDouble();
  }

  bool _isVisible(Offset center, double radius, Size size) {
    return Rect.fromCircle(
      center: center,
      radius: radius,
    ).overlaps(Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant _FogPainter oldDelegate) {
    return oldDelegate.cells != cells ||
        oldDelegate.currentLocation != currentLocation ||
        oldDelegate.now != now ||
        oldDelegate.camera.center != camera.center ||
        oldDelegate.camera.zoom != camera.zoom;
  }
}
