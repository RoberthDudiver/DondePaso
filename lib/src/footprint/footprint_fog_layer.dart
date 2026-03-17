import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'footprint_cell.dart';
import 'footprint_h3_grid.dart';
import 'footprint_transport.dart';

class FootprintFogLayer extends StatelessWidget {
  const FootprintFogLayer({
    super.key,
    required this.cells,
    required this.currentLocation,
    required this.now,
    required this.forgetAfter,
    required this.revealMeters,
    required this.lightMapMode,
  });

  final List<FootprintCell> cells;
  final LatLng? currentLocation;
  final DateTime now;
  final Duration forgetAfter;
  final double revealMeters;
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
        painter: _FogPainter(
          camera: camera,
          cells: cells,
          currentLocation: currentLocation,
          now: now,
          forgetAfter: forgetAfter,
          revealMeters: revealMeters,
          lightMapMode: lightMapMode,
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
    required this.lightMapMode,
  });

  final MapCamera camera;
  final List<FootprintCell> cells;
  final LatLng? currentLocation;
  final DateTime now;
  final Duration forgetAfter;
  final double revealMeters;
  final bool lightMapMode;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());

    canvas.drawRect(
      bounds,
      Paint()
        ..color = const Color(0xFF000000).withValues(
          alpha: lightMapMode ? 0.26 : 1.0,
        ),
    );

    final visibleHexes = <_VisibleHexRender>[];

    for (final cell in cells) {
      final freshness = _freshness(cell);
      if (freshness <= 0) {
        continue;
      }

      if (cell.isH3) {
        final path = _pathForHexCell(cell);
        if (path != null && _isPathVisible(path, size)) {
          final clarity = (freshness *
                  (0.28 +
                      (cell.visits.clamp(1, 10) * 0.045) +
                      ((cell.coverageWeight - 1) * 0.12)))
              .clamp(0.22, 0.82);
          final whiteness =
              (0.24 + (cell.visits.clamp(1, 12) * 0.05)).clamp(0.28, 0.86);
          visibleHexes.add(
            _VisibleHexRender(
              path: path,
              clarity: clarity,
              whiteness: whiteness,
              visits: cell.visits,
              transportMode: cell.dominantTransport,
            ),
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

    _paintMergedHexTerritory(canvas, visibleHexes);
    _paintHexTexture(canvas, visibleHexes);

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

  void _paintMergedHexTerritory(
    Canvas canvas,
    List<_VisibleHexRender> visibleHexes,
  ) {
    final mergedPath = _mergedVisibleHexPath(visibleHexes);
    if (mergedPath == null) {
      return;
    }

    var claritySum = 0.0;
    var whitenessPeak = 0.0;
    var visitsPeak = 1;
    for (final render in visibleHexes) {
      claritySum += render.clarity;
      if (render.whiteness > whitenessPeak) {
        whitenessPeak = render.whiteness;
      }
      if (render.visits > visitsPeak) {
        visitsPeak = render.visits;
      }
    }

    final averageClarity = claritySum / visibleHexes.length;
    final outerGlowBlur = 9.0 + (visitsPeak.clamp(1, 12) * 1.05);

    if (lightMapMode) {
      final warmGlow = Color.lerp(
        const Color(0xFF8A4A00),
        const Color(0xFFC57A16),
        whitenessPeak,
      )!;
      final warmFill = Color.lerp(
        const Color(0xFF6D3900),
        const Color(0xFFB56A10),
        whitenessPeak,
      )!;

      canvas.drawPath(
        mergedPath,
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, outerGlowBlur)
          ..color = warmGlow.withValues(
            alpha: 0.14 + (averageClarity * 0.16),
          ),
      );
      canvas.drawPath(
        mergedPath,
        Paint()
          ..blendMode = BlendMode.srcOver
          ..color = warmFill.withValues(
            alpha: 0.15 + (averageClarity * 0.10),
          ),
      );
    } else {
      canvas.drawPath(
        mergedPath,
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, outerGlowBlur)
          ..color = Colors.white.withValues(
            alpha: (0.06 + (averageClarity * 0.10)) *
                (0.8 + (whitenessPeak * 0.2)),
          ),
      );
      canvas.drawPath(
        mergedPath,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..color = Colors.white.withValues(
            alpha: 0.42 + (averageClarity * 0.16),
          ),
      );
      canvas.drawPath(
        mergedPath,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            7.0 + (visitsPeak.clamp(1, 12) * 0.72),
          )
          ..color = Colors.white.withValues(
            alpha: 0.22 + (averageClarity * 0.10),
          ),
      );
    }
  }

  void _paintHexTexture(Canvas canvas, List<_VisibleHexRender> visibleHexes) {
    for (final render in visibleHexes) {
      final outerGlowBlur = (4.0 + (render.visits.clamp(1, 10) * 0.68))
          .toDouble();

      if (lightMapMode) {
        final warmGlow = Color.lerp(
          const Color(0xFF955200),
          const Color(0xFFC77E18),
          render.whiteness,
        )!;
        final edgeColor = render.transportMode == FootprintTransportMode.vehicle
            ? const Color(0xFF55AFFF)
            : warmGlow;
        canvas.drawPath(
          render.path,
          Paint()
            ..blendMode = BlendMode.plus
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, outerGlowBlur)
            ..color = warmGlow.withValues(
              alpha: 0.05 + (render.clarity * 0.05),
            ),
        );
        canvas.drawPath(
          render.path,
          Paint()
            ..blendMode = BlendMode.srcOver
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.65
            ..color = edgeColor.withValues(
              alpha: render.transportMode == FootprintTransportMode.vehicle
                  ? 0.16 + (render.clarity * 0.10)
                  : 0.04 + (render.clarity * 0.05),
            ),
        );
      } else {
        final edgeColor = render.transportMode == FootprintTransportMode.vehicle
            ? const Color(0xFF7BC7FF)
            : Colors.white;
        canvas.drawPath(
          render.path,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = Colors.white.withValues(
              alpha: (0.04 + (render.clarity * 0.05)) * render.whiteness,
            ),
        );
        canvas.drawPath(
          render.path,
          Paint()
            ..blendMode = BlendMode.srcOver
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.55
            ..color = edgeColor.withValues(
              alpha: render.transportMode == FootprintTransportMode.vehicle
                  ? 0.14 + (render.clarity * 0.08)
                  : (0.02 + (render.clarity * 0.04)) * render.whiteness,
            ),
        );
      }
    }
  }

  ui.Path? _mergedVisibleHexPath(List<_VisibleHexRender> visibleHexes) {
    if (visibleHexes.isEmpty) {
      return null;
    }

    var merged = ui.Path.from(visibleHexes.first.path);
    for (final render in visibleHexes.skip(1)) {
      merged = ui.Path.combine(ui.PathOperation.union, merged, render.path);
    }
    return merged;
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

  bool _isPathVisible(ui.Path path, Size size) {
    return path.getBounds().overlaps(Offset.zero & size);
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

class _VisibleHexRender {
  const _VisibleHexRender({
    required this.path,
    required this.clarity,
    required this.whiteness,
    required this.visits,
    required this.transportMode,
  });

  final ui.Path path;
  final double clarity;
  final double whiteness;
  final int visits;
  final FootprintTransportMode transportMode;
}
