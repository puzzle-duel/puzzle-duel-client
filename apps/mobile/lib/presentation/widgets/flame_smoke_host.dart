import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:material_ui/material_ui.dart';

/// Minimal Flame mount proving GameWidget + ColorEffect resolve on Flutter 3.50.
///
/// Does not own rules state or implement board gameplay (PZD-23).
final class FlameSmokeHost extends StatelessWidget {
  const FlameSmokeHost({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Flame rendering smoke probe',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GameWidget(game: _SmokeGame()),
      ),
    );
  }
}

final class _SmokeGame extends FlameGame {
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final rect = RectangleComponent(
      size: Vector2(48, 48),
      position: Vector2(24, 24),
      paint: Paint()..color = const Color(0xFF2E7D32),
    );
    rect.add(
      ColorEffect(
        const Color(0xFF81C784),
        EffectController(duration: 0.4, alternate: true, infinite: true),
      ),
    );
    await add(rect);
  }
}
