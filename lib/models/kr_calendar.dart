import 'lunar.dart';
import 'solar_terms.dart';
import 'special_holidays.dart';

enum MarkKind { holiday, custom, term, observance }

class DayMark {
  final String name;
  final MarkKind kind;
  const DayMark(this.name, this.kind);

  /// 빨간 날(공휴일, 대체공휴일, 선거일, 사용자가 추가한 휴일)인지
  bool get isHoliday => kind == MarkKind.holiday;

  @override
  String toString() => '${kind.name}:$name';
}

/// 사용자가 앱에서 추가한 날 (임시공휴일 등)
class CustomDay {
  final String id;
  final DateTime date;
  final String name;
  final bool holiday;
  const CustomDay({required this.id, required this.date, required this.name, this.holiday = true});
}

enum _Rule { none, seolChuseok, children, weekendFrom2021, weekendFrom2022, weekendFrom2023 }

class _Group {
  final String name;
  final List<int> dns;
  final _Rule rule;
  _Group(this.name, this.dns, this.rule);
}

/// 한국 달력: 공휴일(대체공휴일 포함), 24절기, 명절/절식, 기념일.
///
/// 규칙은 관공서의 공휴일에 관한 규정의 시행 시점을 따른다. 정확도는 대체로 1990년 이후 기준이다.
/// 규칙으로 알 수 없는 임시공휴일/선거일은 [knownSpecialHolidays]와 [custom]으로 보탠다.
class KrCalendar {
  final List<CustomDay> custom;
  KrCalendar({this.custom = const []});

  final Map<int, Map<int, List<DayMark>>> _cache = {};

  List<DayMark> marksOn(DateTime d) => _year(d.year)[dayNumber(d)] ?? const [];

  bool isHoliday(DateTime d) => marksOn(d).any((m) => m.isHoliday);

  Map<int, List<DayMark>> _year(int y) => _cache.putIfAbsent(y, () => _build(y));

  Map<int, List<DayMark>> _build(int y) {
    final marks = <int, List<DayMark>>{};
    void add(DateTime d, String name, MarkKind kind) {
      final list = marks.putIfAbsent(dayNumber(d), () => []);
      if (!list.any((m) => m.name == name)) list.add(DayMark(name, kind));
    }

    final groups = <_Group>[];
    void holiday(String name, List<DateTime> days, [_Rule rule = _Rule.none]) {
      for (final d in days) {
        add(d, name, MarkKind.holiday);
      }
      groups.add(_Group(name, days.map(dayNumber).toList(), rule));
    }

    // ---- 양력 고정 공휴일 ----
    if (y >= 1949) holiday('신정', [DateTime(y, 1, 1)]);
    if (y >= 1949) holiday('삼일절', [DateTime(y, 3, 1)], _Rule.weekendFrom2022);
    if (y >= 1975) holiday('어린이날', [DateTime(y, 5, 5)], _Rule.children);
    if (y >= 1956) holiday('현충일', [DateTime(y, 6, 6)]);
    if (y >= 1949) holiday('광복절', [DateTime(y, 8, 15)], _Rule.weekendFrom2021);
    if (y >= 1949) holiday('개천절', [DateTime(y, 10, 3)], _Rule.weekendFrom2021);
    if (y >= 1949) holiday('성탄절', [DateTime(y, 12, 25)], _Rule.weekendFrom2023);

    // 시기에 따라 공휴일이었다가 빠진(또는 부활한) 날
    final hangeul = (y >= 1949 && y <= 1990) || y >= 2013;
    if (hangeul) {
      holiday('한글날', [DateTime(y, 10, 9)], _Rule.weekendFrom2021);
    } else {
      add(DateTime(y, 10, 9), '한글날', MarkKind.observance);
    }
    if (y >= 1949 && y <= 2005) {
      holiday('식목일', [DateTime(y, 4, 5)]);
    } else {
      add(DateTime(y, 4, 5), '식목일', MarkKind.observance);
    }
    if (y >= 1950 && y <= 2007) {
      holiday('제헌절', [DateTime(y, 7, 17)]);
    } else {
      add(DateTime(y, 7, 17), '제헌절', MarkKind.observance);
    }
    if (y >= 1976 && y <= 1990) {
      holiday('국군의날', [DateTime(y, 10, 1)]);
    } else {
      add(DateTime(y, 10, 1), '국군의날', MarkKind.observance);
    }

    // ---- 음력 공휴일 ----
    final seol = lunarToSolar(y, 1, 1);
    if (seol != null) {
      final days = [-1, 0, 1].map((o) => DateTime(seol.year, seol.month, seol.day + o)).toList();
      add(days[0], '설날 연휴', MarkKind.holiday);
      add(days[1], '설날', MarkKind.holiday);
      add(days[2], '설날 연휴', MarkKind.holiday);
      groups.add(_Group('설날', days.map(dayNumber).toList(), _Rule.seolChuseok));
    }
    final chuseok = lunarToSolar(y, 8, 15);
    if (chuseok != null) {
      final days = [-1, 0, 1].map((o) => DateTime(chuseok.year, chuseok.month, chuseok.day + o)).toList();
      add(days[0], '추석 연휴', MarkKind.holiday);
      add(days[1], '추석', MarkKind.holiday);
      add(days[2], '추석 연휴', MarkKind.holiday);
      groups.add(_Group('추석', days.map(dayNumber).toList(), _Rule.seolChuseok));
    }
    final buddha = lunarToSolar(y, 4, 8);
    if (buddha != null && y >= 1975) holiday('부처님오신날', [buddha], _Rule.weekendFrom2023);

    // ---- 임시공휴일 / 선거일 / 사용자 추가 ----
    for (final s in knownSpecialHolidays) {
      if (s.$1 == y) holiday(s.$4, [DateTime(s.$1, s.$2, s.$3)]);
    }
    for (final c in custom) {
      if (c.date.year != y) continue;
      if (c.holiday) {
        holiday(c.name, [DateTime(c.date.year, c.date.month, c.date.day)]);
        // 사용자 추가 휴일은 모양을 구분한다
        final list = marks[dayNumber(c.date)]!;
        final i = list.indexWhere((m) => m.name == c.name);
        list[i] = DayMark(c.name, MarkKind.holiday);
      } else {
        add(c.date, c.name, MarkKind.custom);
      }
    }

    _addSubstitutes(y, groups, marks);
    _addObservances(y, marks);

    for (final list in marks.values) {
      list.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    }
    return marks;
  }

  /// 대체공휴일: 규정의 시행 시점(설/추석 2014, 어린이날 2014/2018, 광복·개천·한글날 2021,
  /// 삼일절 2022, 부처님오신날·성탄절 2023-05-04)을 따른다.
  void _addSubstitutes(int y, List<_Group> groups, Map<int, List<DayMark>> marks) {
    final coverage = <int, int>{};
    for (final g in groups) {
      for (final dn in g.dns) {
        coverage[dn] = (coverage[dn] ?? 0) + 1;
      }
    }
    final holidayDns = <int>{...coverage.keys};
    groups.sort((a, b) => a.dns.first.compareTo(b.dns.first));

    for (final g in groups) {
      if (g.rule == _Rule.none) continue;
      final dates = g.dns.map(dateFromDayNumber).toList();
      final hasSunday = dates.any((d) => d.weekday == DateTime.sunday);
      final hasSaturday = dates.any((d) => d.weekday == DateTime.saturday);
      final overlap = g.dns.any((dn) => coverage[dn]! > 1);
      final first = dates.first;
      var ok = false;
      switch (g.rule) {
        case _Rule.seolChuseok:
          ok = y >= 2014 && (hasSunday || overlap);
        case _Rule.children:
          ok = (y >= 2014 && hasSunday) || (y >= 2018 && (hasSaturday || overlap));
        case _Rule.weekendFrom2021:
          ok = y >= 2021 && (hasSunday || hasSaturday);
        case _Rule.weekendFrom2022:
          ok = y >= 2022 && (hasSunday || hasSaturday);
        case _Rule.weekendFrom2023:
          ok = !first.isBefore(DateTime(2023, 5, 4)) && (hasSunday || hasSaturday);
        case _Rule.none:
          break;
      }
      if (!ok) continue;
      var dn = g.dns.last + 1;
      while (dateFromDayNumber(dn).weekday >= DateTime.saturday || holidayDns.contains(dn)) {
        dn++;
      }
      holidayDns.add(dn);
      marks.putIfAbsent(dn, () => []).add(DayMark('${g.name} 대체공휴일', MarkKind.holiday));
    }
  }

  void _addObservances(int y, Map<int, List<DayMark>> marks) {
    void add(DateTime d, String name, MarkKind kind) {
      final list = marks.putIfAbsent(dayNumber(d), () => []);
      if (!list.any((m) => m.name == name)) list.add(DayMark(name, kind));
    }

    // 24절기
    if (hasSolarTerms(y)) {
      for (var i = 0; i < 24; i++) {
        add(solarTermDate(y, i)!, solarTermNames[i], MarkKind.term);
      }
      // 한식: 전년 동지로부터 105일째
      if (hasSolarTerms(y - 1)) {
        final dongji = solarTermDate(y - 1, 23)!;
        add(DateTime(dongji.year, dongji.month, dongji.day + 105), '한식', MarkKind.observance);
      }
      // 삼복: 하지 후 세 번째 경일 = 초복, 네 번째 = 중복, 입추 후 첫 경일 = 말복
      DateTime nthGyeong(DateTime from, int n) {
        var d = from;
        var count = 0;
        while (true) {
          if (_isGyeongDay(d)) {
            count++;
            if (count == n) return d;
          }
          d = DateTime(d.year, d.month, d.day + 1);
        }
      }

      add(nthGyeong(solarTermDate(y, 11)!, 3), '초복', MarkKind.observance);
      add(nthGyeong(solarTermDate(y, 11)!, 4), '중복', MarkKind.observance);
      add(nthGyeong(solarTermDate(y, 14)!, 1), '말복', MarkKind.observance);
    }

    // 음력 명절
    void lunar(int m, int d, String name) {
      final s = lunarToSolar(y, m, d);
      if (s != null) add(s, name, MarkKind.observance);
    }

    lunar(1, 15, '정월대보름');
    lunar(5, 5, '단오');
    lunar(7, 7, '칠석');
    lunar(7, 15, '백중');
    lunar(9, 9, '중양절');

    // 양력 기념일
    const fixed = [
      (2, 14, '발렌타인데이'),
      (3, 14, '화이트데이'),
      (5, 8, '어버이날'),
      (5, 15, '스승의 날'),
      (5, 21, '부부의 날'),
      (11, 11, '빼빼로데이'),
      (12, 24, '크리스마스 이브'),
      (12, 31, '제야'),
    ];
    for (final f in fixed) {
      add(DateTime(y, f.$1, f.$2), f.$3, MarkKind.observance);
    }
    // 성년의 날: 5월 셋째 월요일
    var mondays = 0;
    for (var d = 1; d <= 31; d++) {
      if (DateTime(y, 5, d).weekday == DateTime.monday && ++mondays == 3) {
        add(DateTime(y, 5, d), '성년의 날', MarkKind.observance);
        break;
      }
    }
  }
}

/// 경일(庚日): 일간이 경(庚)인 날. 1900-01-01은 갑술일(일간 갑=0)이므로 일수 % 10 == 6.
bool _isGyeongDay(DateTime d) => dayNumber(d) % 10 == 6;
