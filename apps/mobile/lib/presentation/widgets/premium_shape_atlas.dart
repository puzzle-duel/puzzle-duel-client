import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Loads PZD-47 canonical clipped token sprites shared with the app icon source.
///
/// Bodies are quadrant crops from attachment 10000, clipped to the gameplay
/// silhouette (`tools/pzd47/extract_canonical_shapes.py`). The install icon is
/// the same attachment resized. [PiecePainter] rotates the whole sprite for
/// direction (circle/triangle native UP, diamond native LEFT).
final class PremiumShapeAtlas {
  PremiumShapeAtlas._();

  static PremiumShapeAtlas? _instance;
  static Future<PremiumShapeAtlas>? _loading;

  static PremiumShapeAtlas get instance =>
      _instance ?? (throw StateError('PremiumShapeAtlas.ensureLoaded() first'));

  static bool get isLoaded => _instance != null;

  ui.Image? _circle;
  ui.Image? _diamond;
  ui.Image? _triangle;

  ui.Image bodyFor(Shape shape) => switch (shape) {
    Shape.circle => _circle!,
    Shape.diamond => _diamond!,
    Shape.triangle => _triangle!,
  };

  /// Icon-native orientation in quarter-turns from UP.
  static int nativeTurnsFromUp(Shape shape) => switch (shape) {
    Shape.circle => 0,
    Shape.diamond => 3,
    Shape.triangle => 0,
  };

  static const circleAsset = 'assets/branding/canonical/circle_body.png';
  static const diamondAsset = 'assets/branding/canonical/diamond_body.png';
  static const triangleAsset = 'assets/branding/canonical/triangle_body.png';

  static Future<PremiumShapeAtlas> ensureLoaded() {
    if (_instance != null) return Future.value(_instance!);
    return _loading ??= _load();
  }

  static Future<PremiumShapeAtlas> _load() async {
    final atlas = PremiumShapeAtlas._();
    atlas._circle = await _decode(circleAsset);
    atlas._diamond = await _decode(diamondAsset);
    atlas._triangle = await _decode(triangleAsset);
    _instance = atlas;
    _loading = null;
    return atlas;
  }

  static void debugReset() {
    _loading = null;
    _instance?._circle?.dispose();
    _instance?._diamond?.dispose();
    _instance?._triangle?.dispose();
    _instance = null;
  }

  static Future<ui.Image> _decode(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
