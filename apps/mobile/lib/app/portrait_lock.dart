import 'package:flutter/services.dart';

/// Portrait upright only. Called from [main] after the binding exists and
/// before [runApp]. Widget tests do not call this.
Future<void> lockPortraitOrientation() {
  return SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
}
