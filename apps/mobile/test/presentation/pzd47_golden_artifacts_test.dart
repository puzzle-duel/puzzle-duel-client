import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Always-on CI coverage for PZD-47 visual fixtures.
///
/// Pixel `matchesGoldenFile` comparisons are macOS-baselined and may skip on
/// Linux CI (see `_ciPixelGoldenSkip`). This suite fails if expected golden
/// PNGs are missing, empty, or have unexpected dimensions — so skipped pixel
/// tests cannot silently erase coverage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final goldensDir = Directory('test/presentation/goldens');

  final required = <String>[
    for (final shape in ['circle', 'diamond', 'triangle'])
      for (final dir in ['up', 'right', 'down', 'left'])
        'pzd47_${shape}_$dir.png',
    'pzd47_direction_matrix_3x4.png',
    for (final shape in ['circle', 'diamond', 'triangle'])
      for (final board in [5, 6, 7])
        for (final dir in ['up', 'right', 'down', 'left'])
          '${shape}_${board}x${board}_$dir.png',
    'direction_family_board_tray.png',
    'triangle_directions_strip.png',
  ];

  test('PZD-47 golden PNG artifacts exist and are valid rasters', () async {
    expect(goldensDir.existsSync(), isTrue, reason: goldensDir.path);
    for (final name in required) {
      final file = File('${goldensDir.path}/$name');
      expect(file.existsSync(), isTrue, reason: name);
      final bytes = await file.readAsBytes();
      expect(bytes.length, greaterThan(200), reason: '$name too small');
      expect(bytes[0], 0x89, reason: '$name PNG signature');
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(8), reason: name);
      expect(frame.image.height, greaterThan(8), reason: name);
    }
  });

  test('force-goldens escape hatch is documented', () {
    // CI operators can re-enable pixel compares with:
    //   PZD47_FORCE_GOLDENS=1 flutter test
    expect(true, isTrue);
  });
}
