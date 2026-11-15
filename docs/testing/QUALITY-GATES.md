# Client quality gates
1. `dart format` and `flutter analyze` once project exists.
2. Unit + golden canonical replay vectors from shared versioned fixture contract (including collisions/cascades).
3. Widget/golden accessibility test at small screens, color independent shape readability and reduced motion.
4. Race test: rapid taps, back navigation during animations, resume after background; test offline free play.
5. CI on PR; report skipped/unrun checks transparently. Current repo may not yet contain executable app code.
