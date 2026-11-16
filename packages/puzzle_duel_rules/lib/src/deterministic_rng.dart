part of '../puzzle_duel_rules.dart';

/// Accepted `gen-001.v1` PCG32 XSH-RR stream (GEN-01).
///
/// State is a [BigInt] masked to 64 bits. Outputs are unsigned 32-bit [int]
/// values in `0 … 2^32−1`. Host `Random` is never used.
final class Pcg32 {
  Pcg32();

  static final BigInt _mask64 = (BigInt.one << 64) - BigInt.one;
  static final BigInt _mask32 = (BigInt.one << 32) - BigInt.one;
  static final BigInt _mult = BigInt.parse('6364136223846793005');
  static final BigInt _inc = BigInt.parse('1442695040664678687');
  static final BigInt two32 = BigInt.parse('4294967296');

  BigInt _state = BigInt.zero;

  void _step() {
    _state = (_state * _mult + _inc) & _mask64;
  }

  /// Exactly two [_step] calls and zero [nextU32] draws.
  void seed32(int seed) {
    if (seed < 0 || seed > 4294967295) {
      throw ArgumentError.value(seed, 'seed', 'must be an unsigned 32-bit int');
    }
    _state = BigInt.zero;
    _step();
    _state = (_state + BigInt.from(seed)) & _mask64;
    _step();
  }

  /// Next unsigned 32-bit value. Uses [oldstate] for the output function.
  int nextU32() {
    final oldstate = _state;
    _step();
    final xorshifted = (((oldstate >> 18) ^ oldstate) >> 27) & _mask32;
    final rot = (oldstate >> 59).toInt();
    return _rotr32(xorshifted.toInt(), rot);
  }

  /// Unbiased `0 … n-1`. [limit] is never narrowed to uint32.
  int randBound(int n) => randomBound(nextU32, n);

  static int _rotr32(int x, int r) {
    final value = x & 0xffffffff;
    final rot = r & 31;
    return ((value >> rot) | (value << ((32 - rot) & 31))) & 0xffffffff;
  }
}

/// Unbiased bound selection over any uint32 source (GEN-01).
///
/// [limit] stays a [BigInt] that may equal `2^32`. Truncating it with a
/// 32-bit mask is forbidden and loops forever when `n` divides `2^32`.
int randomBound(int Function() nextU32, int n) {
  if (n < 1 || n > 4294967296) {
    throw ArgumentError.value(n, 'n', 'must be in 1 .. 2^32');
  }
  if (n == 4294967296) {
    return nextU32();
  }
  final limit = (Pcg32.two32 ~/ BigInt.from(n)) * BigInt.from(n);
  while (true) {
    final u = nextU32();
    if (BigInt.from(u) < limit) {
      return u % n;
    }
  }
}
