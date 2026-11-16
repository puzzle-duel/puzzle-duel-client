import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';

/// Provides [GameSfx] to the presentation tree.
final class GameSfxScope extends InheritedWidget {
  const GameSfxScope({super.key, required this.sfx, required super.child});

  final GameSfx sfx;

  static GameSfx of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GameSfxScope>();
    assert(scope != null, 'GameSfxScope missing');
    return scope!.sfx;
  }

  static GameSfx? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GameSfxScope>()?.sfx;
  }

  @override
  bool updateShouldNotify(covariant GameSfxScope oldWidget) =>
      sfx != oldWidget.sfx;
}
