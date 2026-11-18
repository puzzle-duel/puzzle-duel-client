import 'dart:convert';
import 'dart:io';

/// Sound and haptics preferences for this install.
///
/// Stored in the app's state directory. The OS can clear a temporary directory,
/// and uninstall removes the file. These flags never change ranked results.
final class LocalSettings {
  LocalSettings({required this.file, this.sound = true, this.haptics = true});

  factory LocalSettings.load(Directory directory) {
    final file = File('${directory.path}/pzd-settings.json');
    var sound = true;
    var haptics = true;
    if (file.existsSync()) {
      try {
        final raw = jsonDecode(file.readAsStringSync());
        if (raw is Map) {
          if (raw['sound'] is bool) sound = raw['sound'] as bool;
          if (raw['haptics'] is bool) haptics = raw['haptics'] as bool;
        }
      } catch (_) {
        sound = true;
        haptics = true;
      }
    }
    return LocalSettings(file: file, sound: sound, haptics: haptics);
  }

  final File file;
  bool sound;
  bool haptics;

  void save() {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode({'sound': sound, 'haptics': haptics}));
  }
}
