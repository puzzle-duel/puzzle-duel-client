import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';

/// Testable key/value file access under a single root directory.
///
/// Production uses [DirectoryKvStore] (disk work off the UI isolate via
/// [Isolate.run] when safe). Widget/unit tests inject [MemoryKvStore], or
/// [DirectoryKvStore] falls back to event-queue scheduling under
/// `TestWidgetsFlutterBinding` because `Isolate.run` does not complete under
/// FakeAsync.
abstract class LocalKvStore {
  Future<bool> exists(String name);

  Future<String?> read(String name);

  /// Crash-safe replace: write temp then rename over [name].
  Future<void> writeAtomic(String name, String contents);

  Future<List<String>> listFileNames();
}

final class MemoryKvStore implements LocalKvStore {
  MemoryKvStore([Map<String, String>? seed]) : _files = {...?seed};

  final Map<String, String> _files;

  @override
  Future<bool> exists(String name) async => _files.containsKey(name);

  @override
  Future<String?> read(String name) async => _files[name];

  @override
  Future<void> writeAtomic(String name, String contents) async {
    _files[name] = contents;
  }

  @override
  Future<List<String>> listFileNames() async => _files.keys.toList()..sort();
}

final class DirectoryKvStore implements LocalKvStore {
  DirectoryKvStore(this.root);

  final Directory root;

  String _path(String name) => '${root.path}/$name';

  /// When true (default on device), filesystem work runs in [Isolate.run].
  /// Tests force false: FakeAsync never completes Isolate ports, which makes
  /// `pumpAndSettle` hang and cold boot stay on Loading.
  static bool offloadToIsolate = true;

  Future<T> _run<T>(T Function() body) {
    var useIsolate = offloadToIsolate;
    try {
      final bindingName = WidgetsBinding.instance.runtimeType.toString();
      if (bindingName.contains('Test')) {
        useIsolate = false;
      }
    } catch (_) {
      useIsolate = false;
    }
    if (!useIsolate) {
      // Compute synchronously, then wrap — `Future(body)` schedules an event
      // that never completes under testWidgets FakeAsync without explicit pumps.
      return Future<T>.value(body());
    }
    return Isolate.run(body);
  }

  @override
  Future<bool> exists(String name) {
    final path = _path(name);
    return _run(() => File(path).existsSync());
  }

  @override
  Future<String?> read(String name) {
    final path = _path(name);
    return _run(() {
      final file = File(path);
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    });
  }

  @override
  Future<void> writeAtomic(String name, String contents) {
    final path = _path(name);
    return _run(() {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final tmp = File('$path.tmp');
      tmp.writeAsStringSync(contents, flush: true);
      // Rename replaces the destination; never delete the last valid file first.
      tmp.renameSync(file.path);
    });
  }

  @override
  Future<List<String>> listFileNames() {
    final rootPath = root.path;
    return _run(() {
      final directory = Directory(rootPath);
      if (!directory.existsSync()) return <String>[];
      final names = <String>[];
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isEmpty
            ? entity.path
            : entity.uri.pathSegments.last;
        names.add(name);
      }
      names.sort();
      return names;
    });
  }
}
