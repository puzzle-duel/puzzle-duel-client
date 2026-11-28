import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_medallion.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_prestige_palette.dart';

/// Flutter-rendered contact sheet of all 42 earned combinations for owner UAT.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('42-combination contact sheet golden', (tester) async {
    const cell = 72.0;
    const cols = 6;
    const rows = 7;
    await tester.binding.setSurfaceSize(
      Size(cols * cell + 16, rows * cell + 16),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: BadgePrestigePalette.canvasBackground,
          body: RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final id in BadgeId.values)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final prestige in BadgePrestige.values)
                          SizedBox(
                            width: cell,
                            height: cell,
                            child: BadgeMedallion(
                              badgeId: id,
                              prestige: prestige,
                              earnedCount:
                                  kBadgeThresholds[id]!.forPrestige(prestige),
                              prestigeLabel: prestige.wire,
                              semanticLabel: '${id.wire}-${prestige.wire}',
                              width: cell - 6,
                              paintBackground: true,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/badge_evolution_contact_sheet_42.png'),
    );

    // Ensure the golden artifact exists for delivery review.
    final file = File(
      'test/badges/goldens/badge_evolution_contact_sheet_42.png',
    );
    expect(file.existsSync(), isTrue);
  }, skip: Platform.environment.containsKey('CI') && !Platform.isMacOS);
}
