import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/app/puzzle_duel_app.dart';
import 'package:puzzle_duel_mobile/application/challenge_session.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void main() {
  testWidgets('app shell renders without backend or sign-in', (tester) async {
    final session = ChallengeSession();
    await tester.pumpWidget(PuzzleDuelApp(session: session));
    await tester.pump();

    expect(find.text('Puzzle Duel'), findsOneWidget);
    expect(find.textContaining('No network or sign-in required'), findsOneWidget);
    expect(find.textContaining('Sign in'), findsNothing);
    expect(find.textContaining('Login'), findsNothing);
  });

  testWidgets('generator integration can be exercised from the shell', (
    tester,
  ) async {
    final session = ChallengeSession();
    await tester.pumpWidget(PuzzleDuelApp(session: session));
    await tester.pump();

    await tester.tap(find.textContaining('Easy'));
    await tester.pump();

    expect(find.textContaining('Generator OK'), findsOneWidget);
    expect(find.textContaining('gen-001.v1'), findsOneWidget);
    expect(find.textContaining('core-001.v2'), findsOneWidget);
  });

  testWidgets('failure state is displayed safely when injected', (tester) async {
    final session = ChallengeSession();
    await tester.pumpWidget(PuzzleDuelApp(session: session));
    await tester.pump();

    session.injectFailure(ChallengeGenerationError.generationExhausted);
    await tester.pump();

    expect(find.textContaining('generation_exhausted'), findsOneWidget);
  });

  testWidgets('small screen and large text scale do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final session = ChallengeSession();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: PuzzleDuelApp(session: session),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Puzzle Duel'), findsOneWidget);
  });

  testWidgets('Flame smoke host mounts without crash', (tester) async {
    final session = ChallengeSession();
    await tester.pumpWidget(PuzzleDuelApp(session: session));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.bySemanticsLabel('Flame rendering smoke probe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
