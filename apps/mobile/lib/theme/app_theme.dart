import 'package:material_ui/material_ui.dart';

/// Minimal readable theme for the PZD-22 bootstrap shell.
abstract final class PuzzleDuelTheme {
  static ThemeData light() {
    const seed = Color(0xFF1B4D3E);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      textTheme: Typography.material2021().black.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    );
  }
}
