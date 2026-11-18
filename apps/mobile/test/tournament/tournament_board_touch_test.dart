import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in const [
    ('E1.json', 'E1', 5),
    ('M1.json', 'M1', 6),
    ('H1.json', 'H1', 7),
  ]) {
    testWidgets('${entry.$2} tap hits the selected cell on a phone width', (tester) async {
      final initial = parseInitialGameState(
        (jsonDecode(File('test/tournament/fixtures/v4/${entry.$1}').readAsStringSync())
                as Map<String, Object?>)['initialState']!
            as Map<String, Object?>,
      );
      final piece = initial.offers[0].pieceOrNull!;
      Coordinate? legal;
      for (var row = 0; row < initial.boardSize && legal == null; row++) {
        for (var column = 0; column < initial.boardSize; column++) {
          final tap = Coordinate(row: row, column: column);
          if (canPlaceAt(
            boardSize: initial.boardSize,
            cells: initial.cells,
            blocked: initial.blocked,
            piece: piece,
            tap: tap,
          )) {
            legal = tap;
            break;
          }
        }
      }
      expect(legal, isNotNull);
      var state = initial;
      var revision = 0;
      Object? command;
      final api = ScriptedUatApi((method, path, body) async {
        if (method == 'POST' && path.endsWith('/session')) {
          return const UatHttpResult(201, {'sessionSecret': 'secret'});
        }
        if (path.endsWith('/claims/daily')) {
          return const UatHttpResult(201, {
            'seriesId': '55555555-5555-4555-8555-555555555555',
            'status': 'ACTIVE',
            'original': true,
          });
        }
        if (path.endsWith('/commands')) {
          command = body;
          final applied = applyMove(
            state,
            Move(offerIndex: 0, tap: legal!),
          );
          expect(applied, isA<MoveApplied>());
          state = (applied as MoveApplied).finalState;
          revision += 1;
          return const UatHttpResult(200, {'duplicateReplay': false});
        }
        if (path.endsWith('/board')) {
          return UatHttpResult(200, {
            'ordinal': 1,
            'ordinalLabel': entry.$2,
            'seriesScore': state.score,
            'score': state.score,
            'awaitAdvance': false,
            'resultsPublished': false,
            'boardRevision': revision,
            'writerGeneration': 1,
            'state': state.toJson(),
          });
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync('pzd42-touch');

      await tester.pumpWidget(
        TournamentUatApp(
          config: const UatConfig(
            baseUrl: 'http://127.0.0.1',
            bearer: 'Bearer test',
            playerLabel: 'touch',
          ),
          api: api,
          stateDirectory: directory,
          haptics: const SilentTournamentHaptics(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final cell = find.byKey(ValueKey('board-ink-${legal!.row}-${legal.column}'));
      expect(cell, findsOneWidget);
      expect(tester.getSize(cell).shortestSide, greaterThanOrEqualTo(44));
      expect(find.byKey(ValueKey('board-legal-${legal.row}-${legal.column}')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('offer-slot-0')));
      await tester.pump();
      expect(find.byKey(ValueKey('board-legal-${legal.row}-${legal.column}')), findsOneWidget);

      await tester.tap(cell);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final sent = command! as Map;
      final move = sent['move']! as Map;
      expect(move['offerIndex'], 0);
      expect(move['tap'], [legal.row, legal.column]);
      if (state.score > 0) {
        expect(find.text('+${state.score}'), findsOneWidget);
      } else {
        expect(find.byKey(const Key('score-delta')), findsNothing);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
