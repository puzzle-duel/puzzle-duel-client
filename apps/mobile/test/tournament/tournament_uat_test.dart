import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

class _UnauthorizedApi extends UatApi {
  _UnauthorizedApi() : super(baseUrl: 'http://127.0.0.1:9', bearer: 'Bearer test');

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
  testWidgets('unauthorized UAT session stays on the error screen', (tester) async {
    await tester.pumpWidget(
      TournamentUatApp(
        config: const UatConfig(
          baseUrl: 'http://127.0.0.1:9',
          bearer: 'Bearer test',
          playerLabel: 'Player A',
        ),
        api: _UnauthorizedApi(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Unauthorized. Issue a new UAT bearer and relaunch.'), findsOneWidget);
    expect(find.textContaining('score'), findsNothing);
  });
}
