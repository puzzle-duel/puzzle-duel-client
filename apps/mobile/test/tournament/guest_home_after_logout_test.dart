import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_top_banner.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

/// A01 / A19 — Guest Home must not paint previous verified tournament personal data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: true,
      reduceMotion: true,
    );
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAccessibilityFeaturesTestValue();
  });

  testWidgets(
    'A01/A19 guest Home after logout shows invite CTA without prior score/progress',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('pzd54-guest-home');
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final api = ScriptedUatApi((method, path, body) async {
        if (path.endsWith('/session') && method == 'POST') {
          return const UatHttpResult(201, {
            'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'sessionSecret': 'secret',
          });
        }
        if (path.endsWith('/claims/daily')) {
          return const UatHttpResult(201, {
            'seriesId': 'series-1',
            'status': 'COMPLETED',
            'original': true,
          });
        }
        if (path.endsWith('/board')) {
          return const UatHttpResult(200, {
            'ordinal': 6,
            'ordinalLabel': 'H1',
            'seriesScore': 10200,
            'awaitAdvance': false,
            'resultsPublished': true,
            'state': {'turnsUsed': 10, 'moveLimit': 15, 'boardSize': 5},
          });
        }
        if (path.contains('/results')) {
          return const UatHttpResult(200, {
            'all': 10200,
            'onTimeAwarded': true,
            'easy': 3000,
            'medium': 4000,
            'hard': 3200,
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
            bearer: _jwt(
              sub: '11111111-1111-1111-1111-111111111111',
              accountType: 'verified',
            ),
            playerLabel: 'Verified',
          ),
          api: api,
          stateDirectory: directory,
          haptics: const SilentTournamentHaptics(),
          locale: const Locale('en'),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 80; i++) {
        if (find.byKey(const Key('practice')).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const Key('practice')), findsOneWidget);

      final live = tester
          .widget<AppTopBannerHost>(
            find.byKey(const Key('tournament-status-host')),
          )
          .controller;

      live.day = const TournamentDay(
        seriesId: 'series-a',
        original: true,
        claimStatus: 'COMPLETED',
        ordinal: 6,
        ordinalLabel: 'H1',
        seriesScore: 10200,
        resultsPublished: true,
      );
      live.results = {'all': 10200, 'onTimeAwarded': true};
      live.rankedAuthRequired = false;
      live.tournamentNoticeCode = null;
      live.notifyListeners();
      await tester.pump();

      expect(find.textContaining('10,200'), findsWidgets);

      live.applyGuestSessionAfterLogout(rankedAuthRequired: true);
      await tester.pump();

      expect(find.textContaining('10,200'), findsNothing);
      expect(find.textContaining('On-Time'), findsNothing);
      expect(find.textContaining("Today's tournament completed"), findsNothing);
      expect(find.text("Join today's tournament"), findsOneWidget);
      expect(
        find.text('Sign in with Apple or Google to enter the tournament.'),
        findsOneWidget,
      );
      expect(find.text('Sign in to play tournament'), findsOneWidget);
      expect(live.day, isNull);
      expect(live.results, isEmpty);
      expect(live.tournamentNoticeCode, isNull);
    },
  );
}

String _jwt({required String sub, required String accountType}) {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none'})))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'iss': 'https://staging.puzzle-duel.app',
            'aud': 'puzzle-duel-api',
            'sub': sub,
            'account_type': accountType,
            'fid': 'fid',
          }),
        ),
      )
      .replaceAll('=', '');
  return '$header.$payload.sig';
}
