import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/optical_tier.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/premium_piece_renderer.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Composes the PZD-47 launcher master from the **same** [PremiumPieceRenderer]
/// used by board/tray, plus a decorative trophy raster (not a playable piece).
///
/// Provenance: circle / diamond / hexagon (domain triangle) are painted via
/// [PremiumPieceRenderer] — never via approximate palette recreations.
abstract final class PremiumAppIconComposer {
  static const String provenanceRenderer = 'PremiumPieceRenderer';
  static const String provenanceVersion = 'pzd47-hexagon-identity-v1';
  static const Color background = Color(0xFF0B0F28);

  /// 2×2 layout centers in a [canvas] square (normalized 0–1 then scaled).
  static const List<({Shape? shape, Offset norm})> layout = [
    (shape: Shape.circle, norm: Offset(0.28, 0.28)),
    (shape: Shape.diamond, norm: Offset(0.72, 0.28)),
    (shape: Shape.triangle, norm: Offset(0.28, 0.72)),
    (shape: null, norm: Offset(0.72, 0.72)), // trophy slot
  ];

  /// Piece diameter as a fraction of canvas (safe for rounded launcher masks).
  static const double pieceFrac = 0.38;

  /// Paints the full icon into [canvas] of [size]×[size].
  ///
  /// [trophy] is optional decorative artwork for the bottom-right cell.
  static void paint({
    required Canvas canvas,
    required double size,
    ui.Image? trophy,
  }) {
    final bg = Rect.fromLTWH(0, 0, size, size);
    canvas.drawRect(bg, Paint()..color = background);

    // Soft vignette / ambient plate (no central loop arrows).
    canvas.drawCircle(
      Offset(size * 0.5, size * 0.52),
      size * 0.48,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0x221A2460),
            background.withValues(alpha: 0.0),
          ],
        ).createShader(bg),
    );

    final pieceSize = size * pieceFrac;
    for (final slot in layout) {
      final center = Offset(slot.norm.dx * size, slot.norm.dy * size);
      if (slot.shape == null) {
        _paintTrophy(canvas, center, pieceSize, trophy);
        continue;
      }
      _paintCanonicalPiece(canvas, center, pieceSize, slot.shape!);
    }
  }

  /// Rasterize via the live gameplay painter (canonical shared renderer).
  static void _paintCanonicalPiece(
    Canvas canvas,
    Offset center,
    double pieceSize,
    Shape shape,
  ) {
    canvas.save();
    canvas.translate(center.dx - pieceSize / 2, center.dy - pieceSize / 2);
    PremiumPieceRenderer(
      shape: shape,
      direction: Direction.up,
      tier: ProtoOpticalTier.hero,
    ).paint(canvas, Size.square(pieceSize));
    canvas.restore();
  }

  static void _paintTrophy(
    Canvas canvas,
    Offset center,
    double pieceSize,
    ui.Image? trophy,
  ) {
    // Always draw a clean decorative cup on the navy plate — never paste a
    // trophy crop that carries a purple rectangular plate artifact.
    final dst = Rect.fromCenter(
      center: center,
      width: pieceSize * 0.92,
      height: pieceSize * 0.92,
    );
    final r = pieceSize * 0.34;
    // Soft gold ambient only — never a rectangular plate.
    final cup = Path()
      ..moveTo(center.dx - r * 0.55, center.dy - r * 0.38)
      ..lineTo(center.dx + r * 0.55, center.dy - r * 0.38)
      ..quadraticBezierTo(
        center.dx + r * 0.68,
        center.dy + r * 0.12,
        center.dx + r * 0.22,
        center.dy + r * 0.32,
      )
      ..lineTo(center.dx + r * 0.18, center.dy + r * 0.52)
      ..lineTo(center.dx - r * 0.18, center.dy + r * 0.52)
      ..lineTo(center.dx - r * 0.22, center.dy + r * 0.32)
      ..quadraticBezierTo(
        center.dx - r * 0.68,
        center.dy + r * 0.12,
        center.dx - r * 0.55,
        center.dy - r * 0.38,
      )
      ..close();
    canvas.drawPath(
      cup,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF3B0),
            Color(0xFFFFC22A),
            Color(0xFFB86A00),
          ],
        ).createShader(dst),
    );
    // Handles.
    canvas.drawArc(
      Rect.fromCenter(
        center: center.translate(-r * 0.62, -r * 0.05),
        width: r * 0.55,
        height: r * 0.7,
      ),
      -1.2,
      2.2,
      false,
      Paint()
        ..color = const Color(0xFFFFC22A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, r * 0.12),
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: center.translate(r * 0.62, -r * 0.05),
        width: r * 0.55,
        height: r * 0.7,
      ),
      math.pi - 1.0,
      2.2,
      false,
      Paint()
        ..color = const Color(0xFFFFC22A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, r * 0.12),
    );
    // Stem + base.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(0, r * 0.62),
          width: r * 0.22,
          height: r * 0.28,
        ),
        Radius.circular(r * 0.06),
      ),
      Paint()..color = const Color(0xFFE0A010),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(0, r * 0.82),
          width: r * 0.7,
          height: r * 0.16,
        ),
        Radius.circular(r * 0.08),
      ),
      Paint()..color = const Color(0xFFFFC22A),
    );
    // Star mark.
    canvas.drawCircle(
      center.translate(0, -r * 0.05),
      r * 0.12,
      Paint()..color = const Color(0xFFFFF8D0),
    );
    // [trophy] retained for API compatibility; ignored to avoid purple plate.
    assert(() {
      return trophy == null || trophy.width > 0;
    }());
  }

  /// Render to a [ui.Image] for export / tests.
  static Future<ui.Image> renderImage({
    required double size,
    ui.Image? trophy,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paint(canvas: canvas, size: size, trophy: trophy);
    final picture = recorder.endRecording();
    return picture.toImage(size.ceil(), size.ceil());
  }

  /// Sanity: piece boxes stay inside a rounded-rect safe mask (~8% inset).
  static bool layoutFitsSafeMask(double size, {double insetFrac = 0.08}) {
    final pieceSize = size * pieceFrac;
    final half = pieceSize / 2;
    final lo = size * insetFrac;
    final hi = size * (1 - insetFrac);
    for (final slot in layout) {
      final c = Offset(slot.norm.dx * size, slot.norm.dy * size);
      if (c.dx - half < lo - 1e-6 ||
          c.dy - half < lo - 1e-6 ||
          c.dx + half > hi + 1e-6 ||
          c.dy + half > hi + 1e-6) {
        return false;
      }
    }
    return true;
  }

  static double piecePixelSize(double canvas) => canvas * pieceFrac;

  static double minGap(double canvas) {
    final a = layout[0].norm;
    final b = layout[1].norm;
    return (b.dx - a.dx).abs() * canvas - piecePixelSize(canvas);
  }

  static bool gapsPositive(double canvas) => minGap(canvas) > canvas * 0.02;
}

/// Encode [image] as PNG bytes (deterministic for a given raster).
Future<List<int>> encodePng(ui.Image image) async {
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) {
    throw StateError('PNG encode failed');
  }
  return bd.buffer.asUint8List();
}

/// Tiny helper kept for math imports used by layout checks in tests.
double iconLayoutDiagonal(double size) => size * math.sqrt2;
