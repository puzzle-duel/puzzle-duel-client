part of '../puzzle_duel_rules.dart';

/// JSON-safe integer upper bound (2^53 - 1).
const int kJsonMaxSafeInteger = 9007199254740991;

bool isJsonSafeNonNegativeInt(int value) =>
    value >= 0 && value <= kJsonMaxSafeInteger;

/// Fail-closed checked arithmetic for CORE-001.v3 scoring/turns.
int checkedNonNegAdd(
  int left,
  int right, {
  required void Function() onOverflow,
}) {
  if (left < 0 || right < 0) {
    onOverflow();
    return 0;
  }
  final sum = left + right;
  if (sum < 0 || sum > kJsonMaxSafeInteger) {
    onOverflow();
    return 0;
  }
  return sum;
}

int checkedNonNegMul(
  int left,
  int right, {
  required void Function() onOverflow,
}) {
  if (left < 0 || right < 0) {
    onOverflow();
    return 0;
  }
  if (left == 0 || right == 0) return 0;
  final product = left * right;
  if (product < 0 || product > kJsonMaxSafeInteger) {
    onOverflow();
    return 0;
  }
  // Detect wrap for platforms that truncate (Dart does not); still bound-check.
  if (product ~/ right != left) {
    onOverflow();
    return 0;
  }
  return product;
}
