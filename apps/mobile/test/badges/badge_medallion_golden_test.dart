import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_medallion.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_prestige_palette.dart';

/// Pixel goldens are macOS-baselined. Linux CI skips pixels unless forced.
bool get _ciPixelGoldenSkip {
  if (Platform.environment['PZD_FORCE_BADGE_GOLDENS'] == '1') return false;
  return Platform.environment.containsKey('CI') && !Platform.isMacOS;
}

Future<void> _pumpMedallion(
  WidgetTester tester, {
  required BadgeId id,
  required BadgePrestige? prestige,
  required int count,
  double width = 280,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: BadgePrestigePalette.canvasBackground,
        body: Center(
          child: RepaintBoundary(
            child: BadgeMedallion(
              badgeId: id,
              prestige: prestige,
              earnedCount: count,
              prestigeLabel: prestige?.wire.toUpperCase() ?? '',
              semanticLabel: id.wire,
              width: width,
              paintBackground: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('badge medallion geometry smoke', () {
    testWidgets('renders all 42 earned combinations without throwing', (
      tester,
    ) async {
      for (final id in BadgeId.values) {
        for (final prestige in BadgePrestige.values) {
          final count = kBadgeThresholds[id]!.forPrestige(prestige);
          await _pumpMedallion(
            tester,
            id: id,
            prestige: prestige,
            count: count,
            width: 140,
          );
          expect(find.byType(BadgeMedallion), findsOneWidget);
        }
      }
    });

    testWidgets('renders seven locked states', (tester) async {
      for (final id in BadgeId.values) {
        await _pumpMedallion(
          tester,
          id: id,
          prestige: null,
          count: 0,
          width: 140,
        );
        expect(find.byType(BadgeMedallion), findsOneWidget);
      }
    });
  });

  group('badge medallion pixel goldens', () {
    for (final id in BadgeId.values) {
      for (final prestige in BadgePrestige.values) {
        final name = '${id.wire}_${prestige.wire}';
        testWidgets(name, (tester) async {
          final count = kBadgeThresholds[id]!.forPrestige(prestige);
          await _pumpMedallion(
            tester,
            id: id,
            prestige: prestige,
            count: count,
          );
          await expectLater(
            find.byType(RepaintBoundary).first,
            matchesGoldenFile('goldens/$name.png'),
            skip: _ciPixelGoldenSkip,
          );
        }, skip: _ciPixelGoldenSkip);
      }
    }

    testWidgets('count capsule digit widths', (tester) async {
      for (final count in const [1, 12, 123, 1234]) {
        await _pumpMedallion(
          tester,
          id: BadgeId.onTime,
          prestige: BadgePrestige.gold,
          count: count,
        );
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/on_time_count_$count.png'),
          skip: _ciPixelGoldenSkip,
        );
      }
    }, skip: _ciPixelGoldenSkip);

    testWidgets('beyond mythic', (tester) async {
      await _pumpMedallion(
        tester,
        id: BadgeId.loyalty,
        prestige: BadgePrestige.mythic,
        count: 1500,
      );
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('goldens/loyalty_mythic_beyond.png'),
        skip: _ciPixelGoldenSkip,
      );
    }, skip: _ciPixelGoldenSkip);
  });
}
