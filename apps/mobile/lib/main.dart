import 'package:puzzle_duel_mobile/app/puzzle_duel_app.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';

void main() {
  const base = String.fromEnvironment('PZD_UAT_BASE_URL');
  const bearer = String.fromEnvironment('PZD_UAT_BEARER');
  const player = String.fromEnvironment('PZD_UAT_PLAYER');
  if (base.isNotEmpty && bearer.isNotEmpty) {
    runTournamentUatApp(
      UatConfig(
        baseUrl: base,
        bearer: bearer,
        playerLabel: player.isEmpty ? 'UAT player' : player,
      ),
    );
    return;
  }
  // Guest-first offline bootstrap: no network, auth, ads, or analytics.
  runPuzzleDuelApp(GameSession());
}
