import 'dart:io';

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
      'pzd47-hexagon-identity-v1',
    );
    expect(PremiumPieceRenderer, isNotNull);
  });

  test('1024 layout fits launcher safe mask with positive gaps', () {
    expect(PremiumAppIconComposer.layoutFitsSafeMask(1024), isTrue);
    expect(PremiumAppIconComposer.gapsPositive(1024), isTrue);
  });

  test('renderImage produces raster via PremiumPieceRenderer + Canvas trophy',
      () async {
    final image = await PremiumAppIconComposer.renderImage(size: 256);
    expect(image.width, 256);
    expect(image.height, 256);
    final png = await encodePng(image);
    expect(png.length, greaterThan(1000));
    expect(png[0], 0x89);
    expect(png[1], 0x50);
  });

  test('export master when PZD47_EXPORT_ICON=1 (Canvas trophy only)', () async {
    if (Platform.environment['PZD47_EXPORT_ICON'] != '1') {
      return;
    }
    final root = Directory.current.path.contains('/apps/mobile')
        ? Directory.current.parent.parent.path
        : Directory.current.path;

    // Trophy is painted procedurally — never load a raster crop (avoids
    // purple-plate artifacts from historical trophy.png extracts).
    final image = await PremiumAppIconComposer.renderImage(size: 1024);
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
| Owner reference | `docs/features/pzd-47/reference/hexagon-icon-visual-reference.png` |
| Master | `apps/mobile/assets/branding/app_icon_master_1024.png` |
| Top-left | Green circle (`Shape.circle`) Up |
| Top-right | Purple diamond (`Shape.diamond`) Up |
| Bottom-left | Golden hexagon (`Shape.triangle` → hexagon presentation) Up |
| Bottom-right | Clean Canvas trophy (no rectangular plate; no raster load) |
| Direction glyph | One shared dark stroke chevron (`ProtoShapeGeometry.directionInk`) |
| Export | `PZD47_EXPORT_ICON=1 flutter test test/presentation/premium_app_icon_composer_test.dart` |
| Platform icons | `python3 tools/pzd47/generate_app_icons.py` |

Shared implementation — not palette-only parity. See `DOMAIN_VISUAL_MAPPING.md`.
''');
  });
}
