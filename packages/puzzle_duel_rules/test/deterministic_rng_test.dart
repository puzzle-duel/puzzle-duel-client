import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';
import 'package:test/test.dart';

/// Expected values copied from Accepted
/// `docs/engine/PZD-21-GENERATOR-DECISIONS.md` — not from this implementation.
const _seed0 = [
  903765998,
  2422751314,
  1652705799,
  1618866650,
  1060317981,
  2689674566,
  1577384509,
  1403947984,
  255367340,
  3521512243,
];

const _seed1 = [
  4022946169,
  586434100,
  778513971,
  4210363984,
  465824167,
  3279466709,
  2798243867,
  2464351017,
  356655726,
  566711777,
];

const _seedMax = [
  451480749,
  2087654271,
  3085751845,
  2110723429,
  2880235874,
  856832213,
  2237111505,
  552382290,
  1572602624,
  2704297521,
];

void main() {
  test('PCG32 seed 0 first 10 uint32 match Accepted vectors', () {
    final rng = Pcg32()..seed32(0);
    expect([for (var i = 0; i < 10; i++) rng.nextU32()], _seed0);
  });

  test('PCG32 seed 1 first 10 uint32 match Accepted vectors', () {
    final rng = Pcg32()..seed32(1);
    expect([for (var i = 0; i < 10; i++) rng.nextU32()], _seed1);
  });

  test('PCG32 seed 4294967295 first 10 uint32 match Accepted vectors', () {
    final rng = Pcg32()..seed32(4294967295);
    expect([for (var i = 0; i < 10; i++) rng.nextU32()], _seedMax);
  });

  test('Accepted randBound vectors for seed 0', () {
    const cases = <(int, int, int)>[
      (1, 0, 1),
      (2, 0, 1),
      (3, 2, 1),
      (4, 2, 1),
      (5, 3, 1),
      (24, 14, 1),
      (25, 23, 1),
      (32, 14, 1),
      (4294967296, 903765998, 1),
    ];
    for (final (n, expected, draws) in cases) {
      var count = 0;
      final rng = Pcg32()..seed32(0);
      int next() {
        count += 1;
        return rng.nextU32();
      }

      final value = randomBound(next, n);
      expect(value, expected, reason: 'n=$n');
      expect(count, draws, reason: 'draws for n=$n');
    }
  });

  test('n=4 accepts the first draw immediately', () {
    var draws = 0;
    final rng = Pcg32()..seed32(0);
    final value = randomBound(() {
      draws += 1;
      return rng.nextU32();
    }, 4);
    expect(draws, 1);
    expect(value, 2);
  });

  test('successive randBound(4) on seed 0 stream', () {
    final rng = Pcg32()..seed32(0);
    expect([for (var i = 0; i < 5; i++) rng.randBound(4)], [2, 2, 3, 2, 1]);
  });

  test('forced rejection for n=3 consumes exactly two draws', () {
    final values = <int>[4294967295, 4294967294];
    var index = 0;
    var draws = 0;
    final result = randomBound(() {
      draws += 1;
      return values[index++];
    }, 3);
    expect(draws, 2);
    expect(result, 4294967294 % 3);
  });

  test('rejects out-of-range seeds', () {
    expect(() => Pcg32().seed32(-1), throwsArgumentError);
    expect(() => Pcg32().seed32(4294967296), throwsArgumentError);
  });
}
