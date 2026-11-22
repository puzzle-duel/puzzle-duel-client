import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/main.dart' as application;

void main() {
  testWidgets('cold launch shows visible tournament startup before networking',
      (tester) async {
    await tester.pumpWidget(const application.StagingStartupLoadingScreen());
    await tester.pump();
    expect(find.text('Connecting to tournament…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Offline practice'), findsNothing);
    expect(find.text('Easy'), findsNothing);
    expect(find.text('Medium'), findsNothing);
    expect(find.text('Hard'), findsNothing);
  });

  testWidgets('guest auth failure renders explicit error, not legacy practice',
      (tester) async {
    await tester.pumpWidget(
      const application.StagingStartupErrorScreen('AUTH_NETWORK_UNAVAILABLE'),
    );
    expect(find.text('Tournament staging unavailable'), findsOneWidget);
    expect(find.text('AUTH_NETWORK_UNAVAILABLE'), findsOneWidget);
    expect(find.textContaining('Offline practice'), findsNothing);
  });
}
