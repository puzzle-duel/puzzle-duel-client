import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_feedback.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_top_banner.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

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

  testWidgets('N01/N02 logout shows exactly one info Top Banner, no SnackBar', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n01');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi(
      (_, _, _) async => const UatHttpResult(0, {'error': 'OFFLINE'}),
    );
    final controller = await _pumpHome(tester, api, directory);
    controller.tournamentNoticeCode = null;
    controller.notifyListeners();
    await tester.pump();
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'Signed out. You are playing as a guest.',
      semanticsKey: 'auth-logout-success',
    );
    await tester.pump();

    expect(find.byKey(const Key('auth-logout-success')), findsOneWidget);
    expect(find.byKey(const Key('tournament-status-info')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('tournament-status-error')), findsNothing);
  });

  testWidgets('N03 info warning success share the same presenter', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n03');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);

    controller.presentAppFeedback(
      kind: AppFeedbackKind.success,
      message: 'ok',
      semanticsKey: 'fb-success',
    );
    await tester.pump();
    expect(find.byKey(const Key('tournament-status-success')), findsOneWidget);

    controller.presentAppFeedback(
      kind: AppFeedbackKind.warning,
      message: 'warn',
      semanticsKey: 'fb-warn',
    );
    await tester.pump();
    expect(find.byKey(const Key('tournament-status-error')), findsOneWidget);
    expect(find.byKey(const Key('tournament-status-success')), findsNothing);
    expect(find.byKey(const Key('tournament-status')), findsOneWidget);
  });

  testWidgets('N04 auto-dismiss after hold duration', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n04');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAccessibilityFeaturesTestValue();
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: false,
      reduceMotion: false,
    );
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'auto',
      semanticsKey: 'fb-auto',
    );
    await tester.pump();
    expect(find.byKey(const Key('fb-auto')), findsOneWidget);
    // App feedback uses the longer warning hold (4000ms).
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('fb-auto')), findsNothing);
  });

  testWidgets('N05/N06 sufficient upward drag dismisses banner', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n05');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'drag me',
      semanticsKey: 'fb-drag',
    );
    await tester.pump();
    expect(find.byKey(const Key('fb-drag')), findsOneWidget);

    final center = tester.getCenter(find.byKey(const Key('tournament-status')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -80));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('fb-drag')), findsNothing);
    expect(controller.appFeedback, isNull);
  });

  testWidgets('N07 insufficient drag snaps back', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n07');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'short',
      semanticsKey: 'fb-short',
    );
    await tester.pump();
    final center = tester.getCenter(find.byKey(const Key('tournament-status')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -10));
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const Key('fb-short')), findsOneWidget);
    expect(controller.appFeedback?.semanticsKey, 'fb-short');
  });

  testWidgets('N08 downward drag does not dismiss', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n08');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'down',
      semanticsKey: 'fb-down',
    );
    await tester.pump();
    final center = tester.getCenter(find.byKey(const Key('tournament-status')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, 80));
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const Key('fb-down')), findsOneWidget);
  });

  testWidgets('N10 old timer cannot dismiss newer banner', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n10');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAccessibilityFeaturesTestValue();
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: false,
      reduceMotion: false,
    );
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'old',
      semanticsKey: 'fb-old',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'new',
      semanticsKey: 'fb-new',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byKey(const Key('fb-new')), findsOneWidget);
    expect(find.byKey(const Key('fb-old')), findsNothing);
  });

  testWidgets('N14 rapid sequential feedback never shows two banners', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n14');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'a',
      semanticsKey: 'fb-a',
    );
    controller.presentAppFeedback(
      kind: AppFeedbackKind.warning,
      message: 'b',
      semanticsKey: 'fb-b',
    );
    await tester.pump();
    expect(find.byKey(const Key('tournament-status')), findsOneWidget);
    expect(find.byKey(const Key('fb-b')), findsOneWidget);
    expect(find.byKey(const Key('fb-a')), findsNothing);
  });

  testWidgets(
    'N18 RANKED_AUTH notice suppressed; logout info uses Top Banner',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('pzd54-n18');
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final api = ScriptedUatApi(
        (_, _, _) async => const UatHttpResult(200, {}),
      );
      final controller = await _pumpHome(tester, api, directory);
      controller.tournamentNoticeCode = 'RANKED_AUTH_REQUIRED';
      controller.rankedAuthRequired = true;
      controller.notifyListeners();
      await tester.pump();
      expect(find.byKey(const Key('tournament-status-error')), findsNothing);

      controller.presentAppFeedback(
        kind: AppFeedbackKind.info,
        message: 'Signed out. You are playing as a guest.',
        semanticsKey: 'auth-logout-success',
      );
      await tester.pump();
      expect(find.byKey(const Key('auth-logout-success')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'N19 identical successive app feedback presents again (generation identity)',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('pzd54-n19');
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
          .clearAccessibilityFeaturesTestValue();
      TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
        disableAnimations: false,
        reduceMotion: false,
      );
      final api = ScriptedUatApi(
        (_, _, _) async => const UatHttpResult(200, {}),
      );
      final controller = await _pumpHome(tester, api, directory);
      const message = 'Signed out. You are playing as a guest.';
      controller.presentAppFeedback(
        kind: AppFeedbackKind.info,
        message: message,
        semanticsKey: 'auth-logout-success',
      );
      await tester.pump();
      final firstGen = controller.appFeedback!.generation;
      expect(find.byKey(const Key('auth-logout-success')), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 4100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('auth-logout-success')), findsNothing);
      expect(controller.appFeedback, isNull);

      controller.presentAppFeedback(
        kind: AppFeedbackKind.info,
        message: message,
        semanticsKey: 'auth-logout-success',
      );
      await tester.pump();
      expect(controller.appFeedback!.generation, isNot(firstGen));
      expect(find.byKey(const Key('auth-logout-success')), findsOneWidget);
    },
  );

  testWidgets('N20 identical feedback after manual dismiss presents again', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n20');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    const message = 'Same text again';
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: message,
      semanticsKey: 'fb-same',
    );
    await tester.pump();
    final center = tester.getCenter(find.byKey(const Key('tournament-status')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -80));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('fb-same')), findsNothing);

    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: message,
      semanticsKey: 'fb-same',
    );
    await tester.pump();
    expect(find.byKey(const Key('fb-same')), findsOneWidget);
    expect(controller.appFeedback, isNotNull);
  });

  testWidgets('N21 account epoch change invalidates prior feedback ownership', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n21');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'old account',
      semanticsKey: 'fb-old-account',
    );
    await tester.pump();
    expect(find.byKey(const Key('fb-old-account')), findsOneWidget);
    controller.markAccountStateUpdated();
    await tester.pump();
    expect(controller.appFeedback, isNull);
    expect(find.byKey(const Key('fb-old-account')), findsNothing);
  });

  testWidgets('N22 old timer cannot dismiss identical-text newer generation', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n22');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAccessibilityFeaturesTestValue();
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: false,
      reduceMotion: false,
    );
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    const message = 'identical';
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: message,
      semanticsKey: 'fb-identical',
    );
    await tester.pump();
    final firstGen = controller.appFeedback!.generation;
    await tester.pump(const Duration(milliseconds: 1000));
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: message,
      semanticsKey: 'fb-identical',
    );
    await tester.pump();
    final secondGen = controller.appFeedback!.generation;
    expect(secondGen, isNot(firstGen));
    // First hold would fire around 4000ms from first present (~3000 left).
    await tester.pump(const Duration(milliseconds: 3200));
    expect(controller.appFeedback?.generation, secondGen);
    expect(find.byKey(const Key('fb-identical')), findsOneWidget);
  });

  testWidgets('N23 short drag while syncing still auto-dismisses app feedback', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n23');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAccessibilityFeaturesTestValue();
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: false,
      reduceMotion: false,
    );
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    controller.tournamentSync = TournamentSyncState.syncing;
    controller.notifyListeners();
    await tester.pump();
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'during sync',
      semanticsKey: 'fb-sync-drag',
    );
    await tester.pump();
    expect(find.byKey(const Key('fb-sync-drag')), findsOneWidget);

    final center = tester.getCenter(find.byKey(const Key('tournament-status')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -12));
    await gesture.up();
    await tester.pump();
    // Smooth snap-back in flight / completed; banner must remain then dismiss.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('fb-sync-drag')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('fb-sync-drag')), findsNothing);
    expect(controller.appFeedback, isNull);
  });

  testWidgets('N24 insufficient drag animates snap-back then keeps banner', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n24');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAccessibilityFeaturesTestValue();
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: false,
      reduceMotion: false,
    );
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'snap',
      semanticsKey: 'fb-snap',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final center = tester.getCenter(find.byKey(const Key('tournament-status')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -20));
    await gesture.up();
    // Mid snap-back frame — banner still owned.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('fb-snap')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('fb-snap')), findsOneWidget);
    expect(controller.appFeedback?.semanticsKey, 'fb-snap');
  });

  testWidgets('N25 stale dismiss generation is ignored (idempotent)', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd54-n25');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {}));
    final controller = await _pumpHome(tester, api, directory);
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'one',
      semanticsKey: 'fb-one',
    );
    await tester.pump();
    final firstGen = controller.appFeedback!.generation;
    controller.presentAppFeedback(
      kind: AppFeedbackKind.info,
      message: 'two',
      semanticsKey: 'fb-two',
    );
    await tester.pump();
    controller.dismissAppFeedback(reason: 'auto', generation: firstGen);
    await tester.pump();
    expect(find.byKey(const Key('fb-two')), findsOneWidget);
    expect(controller.appFeedback?.semanticsKey, 'fb-two');
  });
}

Future<TournamentController> _pumpHome(
  WidgetTester tester,
  ScriptedUatApi api,
  Directory directory,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TournamentUatApp(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'pzd54-banner',
      ),
      api: api,
      stateDirectory: directory,
      haptics: const SilentTournamentHaptics(),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 60; i++) {
    if (find.byKey(const Key('practice')).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byKey(const Key('practice')), findsOneWidget);
  return tester
      .widget<AppTopBannerHost>(find.byKey(const Key('tournament-status-host')))
      .controller;
}
