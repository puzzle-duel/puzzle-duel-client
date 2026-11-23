import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolves durable on-device storage for settings, practice, and local identity.
///
/// Uninstall removes this directory. OS temp is never the default for practice
/// records. Automated tests inject an explicit [Directory] override instead.
abstract final class AppStateDirectory {
  static const subdirectory = 'puzzle_duel';

  /// Application-support root used by the real app.
  /// Separate each explicitly chosen UAT guest's local session vault,
  /// home cache and practice state. Existing legacy storage is untouched.
  static Future<Directory> resolveForGuestSlot(String slot) async {
    final root = await resolve();
    if (slot == 'legacy') return root;
    if (slot != 'player-a' && slot != 'player-b') {
      throw ArgumentError.value(slot, 'slot', 'Invalid staging guest slot');
    }
    final directory = Directory('${root.path}/staging-guests/$slot');
    await directory.create(recursive: true);
    return directory;
  }

  static Future<Directory> resolve() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/$subdirectory');
    await directory.create(recursive: true);
    return directory;
  }
}
