/// Prestige tier identifiers for Badge Evolution (PZD-56).
enum BadgePrestige {
  bronze('bronze'),
  silver('silver'),
  gold('gold'),
  platinum('platinum'),
  diamond('diamond'),
  mythic('mythic');

  const BadgePrestige(this.wire);
  final String wire;

  static BadgePrestige? tryParse(String? value) {
    for (final item in BadgePrestige.values) {
      if (item.wire == value) return item;
    }
    return null;
  }

  bool get showsFirstOrnamentLayer => this != BadgePrestige.bronze;

  bool get showsSecondOrnamentLayer =>
      this == BadgePrestige.diamond || this == BadgePrestige.mythic;

  bool get showsMythicOrbit => this == BadgePrestige.mythic;

  double get firstOrnamentOpacity => switch (this) {
    BadgePrestige.silver || BadgePrestige.gold => 0.55,
    BadgePrestige.platinum ||
    BadgePrestige.diamond ||
    BadgePrestige.mythic => 1.0,
    BadgePrestige.bronze => 0.0,
  };

  double get outerStrokeWidth => switch (this) {
    BadgePrestige.bronze || BadgePrestige.silver => 5,
    BadgePrestige.gold ||
    BadgePrestige.platinum ||
    BadgePrestige.diamond ||
    BadgePrestige.mythic => 9,
  };
}
