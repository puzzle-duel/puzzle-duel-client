import 'dart:async';
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
    testWidgets('${entry.$2} board frame stays fixed across selection, pending, score, and rejection', (
      tester,
    ) async {
      final initial = parseInitialGameState(
        (jsonDecode(File('test/tournament/fixtures/v4/${entry.$1}').readAsStringSync()) as Map<String, Object?>)['initialState']!
            as Map<String, Object?>,
      );
      expect(initial.boardSize, entry.$3);
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

      var seriesScore = 0;
      var commands = 0;
      Completer<UatHttpResult>? held;
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
          commands += 1;
          if (commands == 1) {
            held = Completer<UatHttpResult>();
            return held!.future;
          }
          if (commands == 2) {
            seriesScore = 12;
            return const UatHttpResult(200, {'duplicateReplay': false});
          }
          return const UatHttpResult(400, {'error': 'ILLEGAL_MOVE'});
        }
        if (path.endsWith('/board')) {
          return UatHttpResult(200, {
            'ordinal': 1,
            'ordinalLabel': entry.$2,
            'seriesScore': seriesScore,
            'score': seriesScore,
            'awaitAdvance': false,
            'resultsPublished': false,
            'boardRevision': commands,
            'writerGeneration': 1,
            'state': initial.toJson(),
          });
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        TournamentUatApp(
          config: UatConfig(
            baseUrl: 'http://127.0.0.1',
            bearer: 'Bearer test',
            playerLabel: 'layout-${entry.$2}',
          ),
          api: api,
          stateDirectory: Directory.systemTemp.createTempSync('pzd42-layout'),
          haptics: const SilentTournamentHaptics(),
        ),
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final before = _frame(tester);
      final cellBefore = tester.getSize(find.byKey(const ValueKey('board-cell-0-0')));
      expect(before.board.width, before.board.height);
      expect(before.tray.height, 152);
      expect(before.board.left, moreOrLessEquals(8, epsilon: 0.5));
      expect(before.board.top, moreOrLessEquals(251, epsilon: 0.5));
      expect(before.board.width, moreOrLessEquals(374, epsilon: 0.5));
      expect(before.tray.top, moreOrLessEquals(692, epsilon: 0.5));

      await tester.tap(find.byKey(const ValueKey('offer-slot-0')));
      await tester.pump();
      final selected = _frame(tester);
      _expectSameFrame(selected, before);
      expect(tester.getSize(find.byKey(const ValueKey('board-cell-0-0'))), cellBefore);
      expect(find.byKey(ValueKey('board-legal-${legal!.row}-${legal.column}')), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('board-ink-${legal.row}-${legal.column}')));
      await tester.pump();
      final pending = _frame(tester);
      _expectSameFrame(pending, before);
      expect(find.text('Sending this move…'), findsOneWidget);

      held!.complete(const UatHttpResult(200, {'duplicateReplay': false}));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final zero = _frame(tester);
      _expectSameFrame(zero, before);
      expect(find.byKey(const Key('score-delta')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('offer-slot-0')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('board-ink-${legal.row}-${legal.column}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final scored = _frame(tester);
      _expectSameFrame(scored, before);
      // The scripted server changes its score but returns the unchanged board.
      // A mismatched authoritative state must not invent a +score animation.
      expect(find.text('+12'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('offer-slot-0')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('board-ink-${legal.row}-${legal.column}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final rejected = _frame(tester);
      _expectSameFrame(rejected, before);
      expect(find.byKey(const Key('score-delta')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

final class _Frames {
  const _Frames(this.board, this.tray);

  final Rect board;
  final Rect tray;
}

_Frames _frame(WidgetTester tester) {
  Rect of(Key key) {
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    return box.localToGlobal(Offset.zero) & box.size;
  }

  return _Frames(of(const Key('play-board')), of(const Key('offer-tray-frame')));
}

void _expectSameFrame(_Frames next, _Frames origin) {
  for (final pair in [(next.board, origin.board), (next.tray, origin.tray)]) {
    expect((pair.$1.left - pair.$2.left).abs(), lessThan(0.5));
    expect((pair.$1.top - pair.$2.top).abs(), lessThan(0.5));
    expect((pair.$1.width - pair.$2.width).abs(), lessThan(0.5));
    expect((pair.$1.height - pair.$2.height).abs(), lessThan(0.5));
  }
}

Future<void> _pumpFrames(WidgetTester tester, [int frames = 20]) async {
  await tester.pump();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

