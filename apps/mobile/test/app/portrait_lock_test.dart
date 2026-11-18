import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/app/portrait_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup requests upright portrait only', () async {
    final requested = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        requested.addAll((call.arguments as List).cast<String>());
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await lockPortraitOrientation();

    expect(requested, ['DeviceOrientation.portraitUp']);
  });
}
