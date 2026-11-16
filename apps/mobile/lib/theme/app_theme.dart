import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';

/// Dark premium arcade theme for Puzzle Duel.
abstract final class PuzzleDuelTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      surface: GameTokens.surface,
      primary: GameTokens.accent,
      onPrimary: GameTokens.bgDeep,
      secondary: GameTokens.diamondFill,
      tertiary: GameTokens.triangleFill,
      error: GameTokens.danger,
      onSurface: GameTokens.textPrimary,
      onSurfaceVariant: GameTokens.textSecondary,
      outline: GameTokens.border,
      outlineVariant: GameTokens.border.withValues(alpha: 0.6),
      surfaceContainerHighest: GameTokens.surfaceHigh,
      primaryContainer: GameTokens.surfaceHigh,
      onPrimaryContainer: GameTokens.textPrimary,
      tertiaryContainer: GameTokens.cellFlash.withValues(alpha: 0.35),
    );

    final base = Typography.material2021(platform: TargetPlatform.iOS).white;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: GameTokens.bgDeep,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: GameTokens.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: GameTokens.textPrimary,
        ),
      ),
      textTheme: base.copyWith(
        displayLarge: base.displayLarge?.copyWith(
          color: GameTokens.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineMedium: base.headlineMedium?.copyWith(
          color: GameTokens.textPrimary,
          fontWeight: FontWeight.w800,
        ),
        headlineSmall: base.headlineSmall?.copyWith(
          color: GameTokens.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: base.titleLarge?.copyWith(
          color: GameTokens.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.titleMedium?.copyWith(
          color: GameTokens.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.bodyLarge?.copyWith(color: GameTokens.textSecondary),
        bodyMedium: base.bodyMedium?.copyWith(color: GameTokens.textSecondary),
        bodySmall: base.bodySmall?.copyWith(color: GameTokens.textMuted),
        labelLarge: base.labelLarge?.copyWith(
          color: GameTokens.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GameTokens.accent,
          foregroundColor: GameTokens.bgDeep,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GameTokens.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GameTokens.textPrimary,
          side: const BorderSide(color: GameTokens.borderBright),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GameTokens.radiusMd),
          ),
        ),
      ),
    );
  }
}
