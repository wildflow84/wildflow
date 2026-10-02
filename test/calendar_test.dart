import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/kr_calendar.dart';
import 'package:ourday/models/lunar.dart';
import 'package:ourday/models/solar_terms.dart';

String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _p(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// 연도의 공휴일 날짜 목록 (정렬)
List<String> _holidays(KrCalendar cal, int y) {
  final out = <String>[];
  for (var d = DateTime(y, 1, 1); d.year == y; d = DateTime(d.year, d.month, d.day + 1)) {
    if (cal.isHoliday(d)) out.add(_d(d));
  }
  return out;
}

void main() {
  group('음력 변환', () {
    test('KASI 월 시작일 전수 대조 (1900~2050, 하루 단위 양방향)', () {
      final rows = File('test/golden/lunar_month_starts.csv')
          .readAsLinesSync()
          .where((l) => !l.startsWith('#') && l.trim().isNotEmpty)
          .map((l) => l.split(',').map(int.parse).toList())
          .toList();
      var checked = 0;
      for (var i = 0; i < rows.length - 1; i++) {
        final r = rows[i];
        if (r[1] < 1900 || r[0] < dayNumber(lunarRangeStart)) continue;
        final len = rows[i + 1][0] - r[0];
        for (var k = 0; k < len; k++) {
          final solar = dateFromDayNumber(r[0] + k);
          final got = solarToLunar(solar);
          expect(got, LunarDate(r[1], r[2], k + 1, leap: r[3] == 1), reason: _d(solar));
          expect(lunarToSolar(r[1], r[2], k + 1, leap: r[3] == 1), solar, reason: _d(solar));
          checked++;
        }
      }
      expect(checked, greaterThan(54000));
    });

    test('2051~2199 모든 날짜 왕복 변환', () {
      for (var d = DateTime(2051, 1, 1); d.year < 2200; d = DateTime(d.year, d.month, d.day + 1)) {
        final l = solarToLunar(d)!;
        expect(lunarToSolar(l.year, l.month, l.day, leap: l.leap), d, reason: _d(d));
      }
    });

    test('알려진 설날/추석/부처님오신날', () {
      final known = {
        '2024': ['2024-02-10', '2024-09-17', '2024-05-15'],
        '2025': ['2025-01-29', '2025-10-06', '2025-05-05'],
        '2026': ['2026-02-17', '2026-09-25', '2026-05-24'],
        '2027': ['2027-02-07', '2027-09-15', '2027-05-13'], // 한국(UTC+9)은 삭이 2/7 00:56 이라 중국(2/6)보다 하루 늦다
      };
      known.forEach((y, v) {
        final yy = int.parse(y);
        expect(_d(lunarToSolar(yy, 1, 1)!), v[0], reason: '$y 설날');
        expect(_d(lunarToSolar(yy, 8, 15)!), v[1], reason: '$y 추석');
        expect(_d(lunarToSolar(yy, 4, 8)!), v[2], reason: '$y 부처님오신날');
      });
    });

    test('간지', () {
      expect(ganjiYear(2026), '병오');
      expect(ganjiYear(2024), '갑진');
      expect(ganjiYear(1984), '갑자');
    });
  });

  group('24절기', () {
    test('2026 주요 절기', () {
      final exp = {
        '소한': '2026-01-05', '대한': '2026-01-20', '입춘': '2026-02-04', '경칩': '2026-03-05',
        '춘분': '2026-03-20', '청명': '2026-04-05', '입하': '2026-05-05', '망종': '2026-06-06',
        '하지': '2026-06-21', '입추': '2026-08-07', '추분': '2026-09-23', '한로': '2026-10-08',
        '입동': '2026-11-07', '동지': '2026-12-22',
      };
      exp.forEach((name, date) {
        final i = solarTermNames.indexOf(name);
        expect(_d(solarTermDate(2026, i)!), date, reason: name);
        expect(solarTermOn(_p(date)), name);
      });
    });

    test('다른 해 대표 절기', () {
      expect(_d(solarTermDate(2025, 2)!), '2025-02-03'); // 입춘
      expect(_d(solarTermDate(2025, 23)!), '2025-12-22'); // 동지 12/21 15:03 UTC = 12/22 00:03 KST
      expect(_d(solarTermDate(2024, 2)!), '2024-02-04');
    });
  });

  group('공휴일', () {
    final cal = KrCalendar();

    test('2024', () {
      expect(_holidays(cal, 2024), [
        '2024-01-01', '2024-02-09', '2024-02-10', '2024-02-11', '2024-02-12', '2024-03-01',
        '2024-04-10', '2024-05-05', '2024-05-06', '2024-05-15', '2024-06-06', '2024-08-15',
        '2024-09-16', '2024-09-17', '2024-09-18', '2024-10-01', '2024-10-03', '2024-10-09',
        '2024-12-25',
      ]);
    });

    test('2025', () {
      expect(_holidays(cal, 2025), [
        '2025-01-01', '2025-01-27', '2025-01-28', '2025-01-29', '2025-01-30', '2025-03-01',
        '2025-03-03', '2025-05-05', '2025-05-06', '2025-06-03', '2025-06-06', '2025-08-15',
        '2025-10-03', '2025-10-05', '2025-10-06', '2025-10-07', '2025-10-08', '2025-10-09',
        '2025-12-25',
      ]);
    });

    test('2026', () {
      expect(_holidays(cal, 2026), [
        '2026-01-01', '2026-02-16', '2026-02-17', '2026-02-18', '2026-03-01', '2026-03-02',
        '2026-05-05', '2026-05-24', '2026-05-25', '2026-06-03', '2026-06-06', '2026-08-15',
        '2026-08-17', '2026-09-24', '2026-09-25', '2026-09-26', '2026-10-03', '2026-10-05',
        '2026-10-09', '2026-12-25',
      ]);
    });

    test('2027', () {
      expect(_holidays(cal, 2027), [
        '2027-01-01', '2027-02-06', '2027-02-07', '2027-02-08', '2027-02-09', '2027-03-01',
        '2027-05-05', '2027-05-13', '2027-06-06', '2027-08-15', '2027-08-16', '2027-09-14',
        '2027-09-15', '2027-09-16', '2027-10-03', '2027-10-04', '2027-10-09', '2027-10-11',
        '2027-12-25', '2027-12-27',
      ]);
    });

    test('2026 개천절 대체공휴일 이름', () {
      expect(cal.marksOn(DateTime(2026, 10, 5)).map((m) => m.name), contains('개천절 대체공휴일'));
      expect(cal.marksOn(DateTime(2026, 10, 1)).where((m) => m.isHoliday), isEmpty); // 국군의날은 평일 기념일
    });

    test('임시공휴일 사용자 추가', () {
      final c = KrCalendar(custom: [
        CustomDay(id: 'x', date: DateTime(2026, 7, 1), name: '임시공휴일'),
      ]);
      expect(c.isHoliday(DateTime(2026, 7, 1)), true);
      expect(cal.isHoliday(DateTime(2026, 7, 1)), false);
    });

    test('삼복', () {
      String? find(KrCalendar c, int y, String name) {
        for (var d = DateTime(y, 6, 1); d.month < 10; d = DateTime(y, d.month, d.day + 1)) {
          if (c.marksOn(d).any((m) => m.name == name)) return _d(d);
        }
        return null;
      }

      expect([find(cal, 2025, '초복'), find(cal, 2025, '중복'), find(cal, 2025, '말복')],
          ['2025-07-20', '2025-07-30', '2025-08-09']);
      expect([find(cal, 2024, '초복'), find(cal, 2024, '중복'), find(cal, 2024, '말복')],
          ['2024-07-15', '2024-07-25', '2024-08-14']);
    });

    test('1950~2199 모든 해에 설날/추석/부처님오신날이 정확히 한 번', () {
      for (var y = 1975; y < 2200; y++) {
        final names = <String>[];
        for (var d = DateTime(y, 1, 1); d.year == y; d = DateTime(d.year, d.month, d.day + 1)) {
          names.addAll(cal.marksOn(d).map((m) => m.name));
        }
        expect(names.where((n) => n == '설날').length, 1, reason: '$y 설날');
        expect(names.where((n) => n == '추석').length, 1, reason: '$y 추석');
        expect(names.where((n) => n == '부처님오신날').length, 1, reason: '$y 부처님오신날');
        expect(names.where((n) => n == '동지').length, 1, reason: '$y 동지');
      }
    });
  });
}
