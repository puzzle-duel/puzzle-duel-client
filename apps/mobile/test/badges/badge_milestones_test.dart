import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_milestones.dart';

void main() {
  group('totalCompleteSevenDayWindows', () {
    test('7 consecutive = 1', () {
      final days = [
        for (var i = 1; i <= 7; i++) '2026-11-${i.toString().padLeft(2, '0')}',
      ];
      expect(BadgeMilestones.totalCompleteSevenDayWindows(days), 1);
    });

    test('14 consecutive = 2', () {
      final days = [
        for (var i = 1; i <= 14; i++) '2026-11-${i.toString().padLeft(2, '0')}',
      ];
      expect(BadgeMilestones.totalCompleteSevenDayWindows(days), 2);
    });

    test('7 + miss + 7 = 2', () {
      final days = [
        for (var i = 1; i <= 7; i++) '2026-11-${i.toString().padLeft(2, '0')}',
        for (var i = 9; i <= 15; i++) '2026-11-${i.toString().padLeft(2, '0')}',
      ];
      expect(BadgeMilestones.totalCompleteSevenDayWindows(days), 2);
    });

    test('days 2–8 then day 1 still exactly 1', () {
      final first = [
        for (var i = 2; i <= 8; i++) '2026-11-${i.toString().padLeft(2, '0')}',
      ];
      expect(BadgeMilestones.totalCompleteSevenDayWindows(first), 1);
      final withHistory = [...first, '2026-11-01'];
      expect(BadgeMilestones.totalCompleteSevenDayWindows(withHistory), 1);
    });

    test('fill gap later does not inflate beyond two runs', () {
      final interrupted = [
        for (var i = 1; i <= 7; i++) '2026-11-${i.toString().padLeft(2, '0')}',
        for (var i = 9; i <= 15; i++) '2026-11-${i.toString().padLeft(2, '0')}',
      ];
      expect(BadgeMilestones.totalCompleteSevenDayWindows(interrupted), 2);
      final filled = [...interrupted, '2026-11-08'];
      // One continuous 15-day run → floor(15/7)=2 — still not 3.
      expect(BadgeMilestones.totalCompleteSevenDayWindows(filled), 2);
    });

    test('random insertion orders yield identical counts', () {
      final base = [
        for (var i = 1; i <= 14; i++) '2026-11-${i.toString().padLeft(2, '0')}',
      ];
      final shuffled = [...base]..shuffle();
      expect(
        BadgeMilestones.totalCompleteSevenDayWindows(shuffled),
        BadgeMilestones.totalCompleteSevenDayWindows(base),
      );
    });
  });
}
