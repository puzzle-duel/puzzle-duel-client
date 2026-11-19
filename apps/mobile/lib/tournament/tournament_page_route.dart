import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';

/// Opaque tournament push routes so ArcadeBackdrop washes cannot leak through
/// transparent scaffold layers during iOS-style slide transitions.
MaterialPageRoute<T> tournamentPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return MaterialPageRoute<T>(
    settings: settings,
    fullscreenDialog: false,
    builder: (context) {
      return Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: GameTokens.bgDeep,
          canvasColor: GameTokens.bgDeep,
        ),
        child: ColoredBox(
          color: GameTokens.bgDeep,
          child: builder(context),
        ),
      );
    },
  );
}
