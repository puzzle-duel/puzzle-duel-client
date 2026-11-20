import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/app_icon_composer.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/optical_tier.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/premium_piece_renderer.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Pixel evidence for the single-stroke chevron decision.
///
/// Run with:
///   PZD47_EXPORT_CHEVRON_EVIDENCE=1 flutter test \\
///     test/presentation/simple_chevron_evidence_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export 3×4 matrix + icon sizes when enabled', () async {
    if (Platform.environment['PZD47_EXPORT_CHEVRON_EVIDENCE'] != '1') {
      return;
    }
    final root = _repoRoot();
    final out = Directory('$root/docs/features/pzd-47/uat/polish');
    await out.create(recursive: true);

    // Dense 7×7 cell ≈ 48–52px; use 52 for readability in the matrix.
    const cell = 52.0;
    final matrix = await _renderMatrix(cellSize: cell);
    await File('${out.path}/10-simple-chevron-matrix-7x7.png')
        .writeAsBytes(await encodePng(matrix));

    for (final entry in [
      (64.0, '11-simple-chevron-tray.png'),
      (72.0, '11-simple-chevron-6x6.png'),
      (88.0, '11-simple-chevron-5x5.png'),
    ]) {
      final strip = await _renderStrip(entry.$1);
      await File('${out.path}/${entry.$2}')
          .writeAsBytes(await encodePng(strip));
    }

    final icon = await PremiumAppIconComposer.renderImage(size: 1024);
    final iconBytes = await encodePng(icon);
    await File(
      '$root/apps/mobile/assets/branding/app_icon_master_1024.png',
    ).writeAsBytes(iconBytes);
    await File('${out.path}/12-app-icon-1024.png').writeAsBytes(iconBytes);

    for (final s in [60, 120]) {
      final scaled = await _scalePng(iconBytes, s);
      await File('${out.path}/12-app-icon-$s.png').writeAsBytes(scaled);
    }
  });
}

String _repoRoot() {
  final cwd = Directory.current.path;
  if (cwd.endsWith('/apps/mobile') || cwd.endsWith('\\apps\\mobile')) {
    return Directory.current.parent.parent.path;
  }
  return cwd;
}

Future<ui.Image> _renderMatrix({required double cellSize}) async {
  const gap = 10.0;
  const label = 18.0;
  final w = (cellSize + gap) * 4 + gap;
  final h = label + (cellSize + gap) * 3 + gap;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()..color = GameTokens.bgDeep,
  );
  var row = 0;
  for (final shape in Shape.values) {
    var col = 0;
    for (final dir in Direction.values) {
      final x = gap + col * (cellSize + gap);
      final y = label + gap + row * (cellSize + gap);
      canvas.save();
      canvas.translate(x, y);
      PremiumPieceRenderer(
        shape: shape,
        direction: dir,
        tier: ProtoOpticalTier.board,
      ).paint(canvas, Size.square(cellSize));
      canvas.restore();
      col++;
    }
    row++;
  }
  return recorder.endRecording().toImage(w.ceil(), h.ceil());
}

Future<ui.Image> _renderStrip(double size) async {
  const gap = 12.0;
  final w = gap + (size + gap) * 3;
  final h = size + gap * 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()..color = GameTokens.bgDeep,
  );
  var i = 0;
  for (final shape in Shape.values) {
    final x = gap + i * (size + gap);
    canvas.save();
    canvas.translate(x, gap);
    PremiumPieceRenderer(
      shape: shape,
      direction: Direction.up,
      tier: ProtoOpticalTierX.forSize(size),
    ).paint(canvas, Size.square(size));
    canvas.restore();
    i++;
  }
  return recorder.endRecording().toImage(w.ceil(), h.ceil());
}

Future<List<int>> _scalePng(List<int> png, int size) async {
  final codec = await ui.instantiateImageCodec(
    Uint8List.fromList(png),
    targetWidth: size,
    targetHeight: size,
  );
  final frame = await codec.getNextFrame();
  return encodePng(frame.image);
}
