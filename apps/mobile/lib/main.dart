import 'package:puzzle_duel_mobile/app/puzzle_duel_app.dart';
import 'package:puzzle_duel_mobile/application/challenge_session.dart';

void main() {
  // Guest-first offline bootstrap: no network, auth, ads, or analytics.
  final session = ChallengeSession();
  runPuzzleDuelApp(session);
}
