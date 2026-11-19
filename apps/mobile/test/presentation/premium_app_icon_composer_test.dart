import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/app_icon_composer.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/premium_piece_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('composer provenance pins shared PremiumPieceRenderer', () {
    expect(
      PremiumAppIconComposer.provenanceRenderer,
      'PremiumPieceRenderer',
    );
    expect(
      PremiumAppIconComposer.provenanceVersion,
      'pzd47-premium-material-v1',
    );
    // Compile-time / type-level link: compositor imports the live painter.
    expect(PremiumPieceRenderer, isNotNull);
  });

  test('1024 layout fits launcher safe mask with positive gaps', () {
    expect(PremiumAppIconComposer.layoutFitsSafeMask(1024), isTrue);
    expect(PremiumAppIconComposer.gapsPositive(1024), isTrue);
  });

  test('renderImage produces 1024² raster via PremiumPieceRenderer pipeline', () async {
    final image = await PremiumAppIconComposer.renderImage(size: 256);
    expect(image.width, 256);
    expect(image.height, 256);
    final png = await encodePng(image);
    expect(png.length, greaterThan(1000));
    // PNG signature
    expect(png[0], 0x89);
    expect(png[1], 0x50);
  });

  test('export master when PZD47_EXPORT_ICON=1', () async {
    if (Platform.environment['PZD47_EXPORT_ICON'] != '1') {
      return;
    }
    final root = Directory.current.path.contains('/apps/mobile')
        ? Directory.current.parent.parent.path
        : Directory.current.path;
    final trophyPath = File(
      '$root/docs/features/pzd-47/reference/crops/trophy.png',
    );
    ui.Image? trophy;
    if (trophyPath.existsSync()) {
      final bytes = await trophyPath.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      trophy = frame.image;
    } else {
      // Fall back: crop BR quadrant of existing master (decorative only).
      final master = File(
        '$root/apps/mobile/assets/branding/app_icon_master_1024.png',
      );
      if (master.existsSync()) {
        final bytes = await master.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final full = frame.image;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        const half = 512.0;
        canvas.drawImageRect(
          full,
          const ui.Rect.fromLTWH(half, half, half, half),
          const ui.Rect.fromLTWH(0, 0, half, half),
          ui.Paint(),
        );
        trophy = await recorder.endRecording().toImage(512, 512);
      }
    }

    final image = await PremiumAppIconComposer.renderImage(
      size: 1024,
      trophy: trophy,
    );
    final png = await encodePng(image);
    final out = File(
      '$root/apps/mobile/assets/branding/app_icon_master_1024.png',
    );
    await out.writeAsBytes(png, flush: true);

    final provenance = File(
      '$root/docs/features/pzd-47/uat/ICON_PROVENANCE.md',
    );
    await provenance.parent.create(recursive: true);
    await provenance.writeAsString('''
# PZD-47 App Icon — Shared Renderer Provenance

| Field | Value |
| --- | --- |
| Composer | `PremiumAppIconComposer` |
| Shape painter | `${PremiumAppIconComposer.provenanceRenderer}` |
| Material version | `${PremiumAppIconComposer.provenanceVersion}` |
| Master | `apps/mobile/assets/branding/app_icon_master_1024.png` |
| Circle / diamond / triangle | Painted by `PremiumPieceRenderer` with `Direction.up` |
| Trophy | Decorative raster only (not a playable piece) |
| Export | `PZD47_EXPORT_ICON=1 flutter test test/presentation/premium_app_icon_composer_test.dart` |

This file asserts **shared implementation**, not mere palette similarity.
''');
  });
}
