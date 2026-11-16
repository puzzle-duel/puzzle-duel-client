import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architectural dependency guard for PZD-22.
///
/// Fails if the pure rules package imports forbidden platform/framework deps,
/// or if application-owned code uses deprecated Material/Cupertino imports.
void main() {
  final repoRoot = _findRepoRoot();

  test('puzzle_duel_rules must not import Flutter, Flame, or dart:ui', () {
    final rulesLib = Directory(
      '${repoRoot.path}/packages/puzzle_duel_rules/lib',
    );
    expect(rulesLib.existsSync(), isTrue);

    final forbidden = <String>[
      'package:flutter/',
      'package:flame/',
      'package:firebase',
      'package:http/',
      'dart:ui',
      'dart:io',
      'dart:html',
      'dart:js',
    ];

    final violations = <String>[];
    for (final file in rulesLib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final text = file.readAsStringSync();
      for (final pattern in forbidden) {
        if (text.contains("import '$pattern") ||
            text.contains('import "$pattern') ||
            text.contains("export '$pattern") ||
            text.contains('export "$pattern')) {
          violations.add('${file.path}: $pattern');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Forbidden imports in puzzle_duel_rules:\n${violations.join('\n')}',
    );
  });

  test('app-owned Dart must not import deprecated material/cupertino', () {
    final appLib = Directory('${repoRoot.path}/apps/mobile/lib');
    final appTest = Directory('${repoRoot.path}/apps/mobile/test');
    expect(appLib.existsSync(), isTrue);

    final forbidden = <String>[
      'package:flutter/material.dart',
      'package:flutter/cupertino.dart',
    ];

    final violations = <String>[];
    for (final dir in [appLib, appTest]) {
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        for (final pattern in forbidden) {
          if (text.contains("import '$pattern'") ||
              text.contains('import "$pattern"')) {
            violations.add('${file.path}: $pattern');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Deprecated design imports in app-owned code:\n${violations.join('\n')}',
    );
  });

  test('rules package pubspec has no Flutter or Flame dependency', () {
    final pubspec = File(
      '${repoRoot.path}/packages/puzzle_duel_rules/pubspec.yaml',
    );
    final text = pubspec.readAsStringSync();
    expect(text.contains('flutter:'), isFalse);
    expect(text.contains('flame:'), isFalse);
    expect(text.contains('sdk: flutter'), isFalse);
  });
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final marker = File('${dir.path}/packages/puzzle_duel_rules/pubspec.yaml');
    if (marker.existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate repository root from ${Directory.current.path}');
}
