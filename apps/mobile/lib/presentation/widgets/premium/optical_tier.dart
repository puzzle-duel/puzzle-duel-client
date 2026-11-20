/// Detail budget for the prototype renderer at different display sizes.
enum ProtoOpticalTier {
  /// 160–200 px hero comparison.
  hero,

  /// ~60–80 px tray.
  tray,

  /// Dense 7×7 board cell.
  board,
}

extension ProtoOpticalTierX on ProtoOpticalTier {
  static ProtoOpticalTier forSize(double side) {
    if (side >= 140) return ProtoOpticalTier.hero;
    if (side >= 56) return ProtoOpticalTier.tray;
    return ProtoOpticalTier.board;
  }

  double get bounceAlpha => switch (this) {
    ProtoOpticalTier.hero => 0.55,
    ProtoOpticalTier.tray => 0.22,
    ProtoOpticalTier.board => 0.08,
  };

  double get extrusionFrac => switch (this) {
    ProtoOpticalTier.hero => 0.11,
    ProtoOpticalTier.tray => 0.095,
    ProtoOpticalTier.board => 0.078,
  };

  double get bevelFrac => switch (this) {
    ProtoOpticalTier.hero => 0.11,
    ProtoOpticalTier.tray => 0.095,
    ProtoOpticalTier.board => 0.078,
  };

  bool get drawSecondarySpecular => this != ProtoOpticalTier.board;

  bool get drawGlints => this == ProtoOpticalTier.hero;

  bool get drawEdgeStreaks => this != ProtoOpticalTier.board;

  double get chevronScale => switch (this) {
    ProtoOpticalTier.hero => 1.22,
    ProtoOpticalTier.tray => 1.28,
    ProtoOpticalTier.board => 1.35,
  };
}
