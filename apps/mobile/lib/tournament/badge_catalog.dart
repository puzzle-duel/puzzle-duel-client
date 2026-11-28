/// Compatibility barrel for PZD-43 / PZD-56 badge catalogue.
///
/// New code should import `package:puzzle_duel_mobile/badges/domain/...`
/// directly. This file re-exports the canonical domain types so existing
/// tournament/profile imports keep compiling.
library;

export 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
export 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';
export 'package:puzzle_duel_mobile/badges/domain/badge_prestige_resolver.dart';
export 'package:puzzle_duel_mobile/badges/domain/badge_progress.dart';
