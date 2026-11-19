import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

class _UnauthorizedApi extends UatApi {
  _UnauthorizedApi()
    : super(baseUrl: 'http://127.0.0.1:9', bearer: 'Bearer test');

  @override
  Future<UatHttpResult> get(String path) async {
    return const UatHttpResult(401, {'error': 'UNAUTHENTICATED'});
  }

  @override
  Future<UatHttpResult> post(String path, [Object? body]) async {
    return const UatHttpResult(401, {'error': 'UNAUTHENTICATED'});
  }
}

void main() {
  testWidgets('unauthorized UAT session stays on the error screen', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-uat-unauth');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      TournamentUatApp(
        config: const UatConfig(
          baseUrl: 'http://127.0.0.1:9',
          bearer: 'Bearer test',
          playerLabel: 'Player A',
        ),
        api: _UnauthorizedApi(),
        stateDirectory: directory,
      ),
    );
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      if (find.byKey(const Key('practice')).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Expired bearer must not block Practice behind a global recovery shell.
    expect(find.byKey(const Key('practice')), findsOneWidget);
    expect(find.byKey(const Key('home-title')), findsOneWidget);
    expect(find.byKey(const Key('tournament-status')), findsOneWidget);
    expect(
      find.text('Sign in again to update tournament info.'),
      findsOneWidget,
    );
  });
}
