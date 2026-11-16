import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';

/// Layered navy gradient backdrop used across home and game.
final class ArcadeBackdrop extends StatelessWidget {
  const ArcadeBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GameTokens.bgDeep,
            GameTokens.bgMid,
            Color(0xFF101C33),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: CustomPaint(painter: _WashPainter())),
          child,
        ],
      ),
    );
  }
}

/// Soft color washes without MaskFilter.blur (perf + screenshot-safe).
final class _WashPainter extends CustomPainter {
  const _WashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.08),
      150,
      Paint()..color = GameTokens.accent.withValues(alpha: 0.09),
    );
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.22),
      170,
      Paint()..color = GameTokens.diamondFill.withValues(alpha: 0.08),
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.98),
      190,
      Paint()..color = GameTokens.triangleFill.withValues(alpha: 0.06),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
