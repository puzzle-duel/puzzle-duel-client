import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_milestones.dart';

void main() {
  group('nonOverlappingSevenDayWindows', () {
    test('7 consecutive = 1 award', () {
      final days = [
        for (var i = 1; i <= 7; i++) '2026-11-${i.toString().padLeft(2, '0')}',
      ];
      final windows = BadgeMilestones.nonOverlappingSevenDayWindows(days);
      expect(windows, hasLength(1));
      expect(windows.first.startUtcDate, '2026-11-01');
      expect(windows.first.endUtcDate, '2026-11-07');
    });

    test('14 consecutive = 2 awards', () {
      final days = [
        for (var i = 1; i <= 14; i++) '2026-11-${i.toString().padLeft(2, '0')}',
      ];
      expect(BadgeMilestones.nonOverlappingSevenDayWindows(days), hasLength(2));
    });

    test('7 + miss + 7 = 2 awards', () {
      final days = [
        for (var i = 1; i <= 7; i++) '2026-11-${i.toString().padLeft(2, '0')}',
        for (var i = 9; i <= 15; i++) '2026-11-${i.toString().padLeft(2, '0')}',
      ];
      final windows = BadgeMilestones.nonOverlappingSevenDayWindows(days);
      expect(windows, hasLength(2));
      expect(windows[0].evidenceKey, 'unstoppable:window:2026-11-01:2026-11-07');
      expect(windows[1].evidenceKey, 'unstoppable:window:2026-11-09:2026-11-15');
    });

    test('out-of-order input is deterministic', () {
      final a = BadgeMilestones.nonOverlappingSevenDayWindows([
        '2026-11-03',
        '2026-11-01',
        '2026-11-02',
        '2026-11-07',
        '2026-11-05',
        '2026-11-06',
        '2026-11-04',
      ]);
      final b = BadgeMilestones.nonOverlappingSevenDayWindows([
        for (var i = 1; i <= 7; i++) '2026-11-${i.toString().padLeft(2, '0')}',
      ]);
      expect(a.map((w) => w.evidenceKey).toList(), b.map((w) => w.evidenceKey).toList());
    });

    test('duplicates do not create extra awards', () {
      final days = [
        for (var i = 1; i <= 7; i++) '2026-11-${i.toString().padLeft(2, '0')}',
        '2026-11-03',
        '2026-11-03',
      ];
      expect(BadgeMilestones.nonOverlappingSevenDayWindows(days), hasLength(1));
    });
  });
}
