import 'lunar.dart' show dayNumber, solarToLunar, lunarToSolar;

/// 구글 캘린더(RFC 5545 RRULE)와 같은 구조의 반복 규칙.
///
///  - 간격: N일/주/개월/년마다
///  - 주: 요일 여러 개 (1=월 ... 7=일), 주 시작은 일요일
///  - 월: 날짜 기준(1~31, -1=마지막 날) 또는 요일 기준(첫째~넷째/마지막 + 요일)
///  - 종료: 없음 / 날짜(포함) / 횟수
///  - [clampMonthEnd]: 31일처럼 없는 날짜가 있는 달에 말일로 조정 (구글은 기본적으로 건너뜀)
enum Freq { daily, weekly, monthly, yearly }

class Recurrence {
  final Freq freq;
  final int interval;
  final List<int> weekdays;
  final List<int> monthDays;
  final int? nth; // null이 아니면 월간 "요일 기준"
  final int? nthWeekday;
  final bool clampMonthEnd;
  final DateTime? until;
  final int? count;
  /// 음력 반복. 매년(음력 생일/기일) 또는 매월(음력 15일 등). 시작일의 음력 날짜를 따른다.
  /// 시작일이 윤달이어도 평달에 챙기고, 30일인데 29일까지인 달은 29일에 챙긴다.
  final bool lunar;

  const Recurrence({
    required this.freq,
    this.interval = 1,
    this.weekdays = const [],
    this.monthDays = const [],
    this.nth,
    this.nthWeekday,
    this.clampMonthEnd = false,
    this.until,
    this.count,
    this.lunar = false,
  });

  bool get isNthWeekday => freq == Freq.monthly && nth != null;

  Recurrence copyWith({
    int? interval,
    List<int>? weekdays,
    List<int>? monthDays,
    int? nth,
    bool clearNth = false,
    int? nthWeekday,
    bool? clampMonthEnd,
    DateTime? until,
    bool clearUntil = false,
    int? count,
    bool clearCount = false,
  }) =>
      Recurrence(
        freq: freq,
        interval: interval ?? this.interval,
        weekdays: weekdays ?? this.weekdays,
        monthDays: monthDays ?? this.monthDays,
        nth: clearNth ? null : (nth ?? this.nth),
        nthWeekday: nthWeekday ?? this.nthWeekday,
        clampMonthEnd: clampMonthEnd ?? this.clampMonthEnd,
        until: clearUntil ? null : (until ?? this.until),
        count: clearCount ? null : (count ?? this.count),
        lunar: lunar,
      );

  // ---------- 저장 ----------
  Map<String, dynamic> toMap() => {
        'freq': freq.name,
        'interval': interval,
        'weekdays': weekdays,
        'monthDays': monthDays,
        'nth': nth,
        'nthWeekday': nthWeekday,
        'clamp': clampMonthEnd,
        'until': until == null ? null : _key(until!),
        'count': count,
        'lunar': lunar,
      };

  factory Recurrence.fromMap(Map<String, dynamic> m) => Recurrence(
        freq: Freq.values.firstWhere((f) => f.name == m['freq'], orElse: () => Freq.daily),
        interval: ((m['interval'] as num?)?.toInt() ?? 1).clamp(1, 999),
        weekdays: List<int>.from(m['weekdays'] ?? const []),
        monthDays: List<int>.from(m['monthDays'] ?? const []),
        nth: (m['nth'] as num?)?.toInt(),
        nthWeekday: (m['nthWeekday'] as num?)?.toInt(),
        clampMonthEnd: m['clamp'] == true,
        until: m['until'] == null ? null : _parse(m['until'] as String),
        count: (m['count'] as num?)?.toInt(),
        lunar: m['lunar'] == true,
      );

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime _parse(String s) {
    final p = s.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  @override
  bool operator ==(Object other) => other is Recurrence && _id == other._id;
  @override
  int get hashCode => _id.hashCode;

  String get _id => [
        freq.name, interval, (List<int>.of(weekdays)..sort()).join(','),
        (List<int>.of(monthDays)..sort()).join(','), nth, nthWeekday, clampMonthEnd,
        until == null ? '' : _key(until!), count, lunar,
      ].join('|');

  // ---------- 발생 계산 ----------
  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
  static int _daysIn(int y, int m) => DateTime(y, m + 1, 0).day;
  static bool _leap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
  static int _weekStart(DateTime d) => dayNumber(d) - (d.weekday % 7); // 일요일 기준 주 시작

  /// [start]에서 시작하는 규칙이 [day]에 해당하는지. (종료 조건, 예외 날짜는 보지 않음)
  bool matches(DateTime start, DateTime day) {
    final s = _d(start), d = _d(day);
    if (d.isBefore(s)) return false;
    if (lunar && (freq == Freq.yearly || freq == Freq.monthly)) return _lunarMatch(s, d);
    switch (freq) {
      case Freq.daily:
        return (dayNumber(d) - dayNumber(s)) % interval == 0;
      case Freq.weekly:
        final days = weekdays.isEmpty ? [s.weekday] : weekdays;
        if (!days.contains(d.weekday)) return false;
        return ((_weekStart(d) - _weekStart(s)) ~/ 7) % interval == 0;
      case Freq.monthly:
        final months = (d.year - s.year) * 12 + d.month - s.month;
        if (months % interval != 0) return false;
        return isNthWeekday ? _nthMatch(s, d) : _dateMatch(s, d);
      case Freq.yearly:
        if ((d.year - s.year) % interval != 0) return false;
        if (d.month == s.month && d.day == s.day) return true;
        return clampMonthEnd && s.month == 2 && s.day == 29 && d.month == 2 && d.day == 28 && !_leap(d.year);
    }
  }

  bool _lunarMatch(DateTime s, DateTime d) {
    final ls = solarToLunar(s), ld = solarToLunar(d);
    if (ls == null || ld == null) return false;
    if (freq == Freq.yearly) {
      if ((ld.year - ls.year) % interval != 0) return false;
      if (ld.leap || ld.month != ls.month) return false; // 윤달은 평달에 챙긴다
    }
    if (ld.day == ls.day) return true;
    // 30일이 없는 달(29일까지)은 29일에
    return ls.day == 30 && ld.day == 29 && lunarToSolar(ld.year, ld.month, 30, leap: ld.leap) == null;
  }

  bool _dateMatch(DateTime s, DateTime d) {
    final days = monthDays.isEmpty ? [s.day] : monthDays;
    final last = _daysIn(d.year, d.month);
    for (final md in days) {
      if (md == -1 && d.day == last) return true;
      if (md > 0) {
        if (md == d.day) return true;
        if (clampMonthEnd && md > last && d.day == last) return true;
      }
    }
    return false;
  }

  bool _nthMatch(DateTime s, DateTime d) {
    if (d.weekday != (nthWeekday ?? s.weekday)) return false;
    final last = _daysIn(d.year, d.month);
    if (nth == -1) return d.day + 7 > last;
    return ((d.day - 1) ~/ 7) + 1 == nth;
  }

  static final Map<String, DateTime?> _lastCache = {};

  /// 횟수 종료일 때 마지막 발생일. 횟수 종료가 아니면 null.
  DateTime? lastOccurrence(DateTime start) {
    if (count == null) return null;
    final s = _d(start);
    return _lastCache.putIfAbsent('$_id#${dayNumber(s)}', () {
      var left = count!;
      var d = s;
      for (var i = 0; i < 366 * 120; i++) {
        if (until != null && d.isAfter(_d(until!))) return null;
        if (matches(s, d) && --left == 0) return d;
        d = DateTime(d.year, d.month, d.day + 1);
      }
      return null;
    });
  }

  /// 종료 조건까지 포함한 발생 여부 (예외 날짜는 보지 않음).
  bool occursOn(DateTime start, DateTime day) {
    final d = _d(day), s = _d(start);
    if (d.isBefore(s)) return false;
    if (until != null && d.isAfter(_d(until!))) return false;
    if (!matches(s, d)) return false;
    if (count != null) {
      final last = lastOccurrence(s);
      if (last == null || d.isAfter(last)) return false;
    }
    return true;
  }

  /// [start] 이후(포함) 규칙에 맞는 첫 날짜. 구글처럼 시작일이 규칙과 안 맞으면 첫 발생일로 옮길 때 쓴다.
  DateTime firstOnOrAfter(DateTime start) {
    final s = _d(start);
    var d = s;
    for (var i = 0; i < 366 * 9; i++) {
      if (matches(s, d)) return d;
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return s;
  }

  /// [anchor]를 기준으로 [after] 다음 날부터 처음 맞는 날짜. 종료일이 지났거나 찾지 못하면 null.
  /// (이동형 반복: 완료하면 다음 일정으로 옮길 때 쓴다. 횟수 종료는 호출하는 쪽에서 센다.)
  DateTime? nextAfter(DateTime anchor, DateTime after) {
    final a = _d(anchor);
    var d = DateTime(after.year, after.month, after.day + 1);
    for (var i = 0; i < 366 * 9; i++) {
      if (until != null && d.isAfter(_d(until!))) return null;
      if (matches(a, d)) return d;
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return null;
  }

  // ---------- 설명 ----------
  static const _wdShort = ['월', '화', '수', '목', '금', '토', '일'];
  static String wdShort(int weekday) => _wdShort[weekday - 1];
  static String wdFull(int weekday) => '${_wdShort[weekday - 1]}요일';
  static String nthLabel(int n) => n == -1 ? '마지막' : const ['', '첫째', '둘째', '셋째', '넷째'][n];

  /// "매주 월·수", "2주마다 월", "매월 1일·15일", "매월 둘째 화요일 · 10회" 같은 한 줄 설명
  String describe(DateTime start) {
    final s = _d(start);
    String base;
    final ls = lunar ? solarToLunar(s) : null;
    if (ls != null && (freq == Freq.yearly || freq == Freq.monthly)) {
      final head = freq == Freq.yearly
          ? '${interval == 1 ? '매년' : '$interval년마다'} 음력 ${ls.month}월 ${ls.day}일'
          : '매월 음력 ${ls.day}일';
      var out = head;
      if (until != null) out += ' · ${until!.year}.${until!.month}.${until!.day}까지';
      if (count != null) out += ' · $count회';
      return out;
    }
    switch (freq) {
      case Freq.daily:
        base = interval == 1 ? '매일' : '$interval일마다';
      case Freq.weekly:
        final days = (weekdays.isEmpty ? [s.weekday] : List<int>.of(weekdays))..sort();
        final isWeekdays = days.length == 5 && days.every((x) => x <= 5);
        final label = isWeekdays ? '월~금' : days.map(wdShort).join('·');
        if (interval == 1) {
          base = isWeekdays ? '평일 (월~금)' : days.length == 1 ? '매주 ${wdFull(days.first)}' : '매주 $label';
        } else {
          base = '$interval주마다 $label';
        }
      case Freq.monthly:
        final prefix = interval == 1 ? '매월' : '$interval개월마다';
        if (isNthWeekday) {
          base = '$prefix ${nthLabel(nth!)} ${wdFull(nthWeekday ?? s.weekday)}';
        } else {
          final days = monthDays.isEmpty ? [s.day] : List<int>.of(monthDays);
          final pos = days.where((x) => x > 0).toList()..sort();
          final list = [...pos.map((x) => '$x일'), if (days.contains(-1)) '마지막 날'];
          base = '$prefix ${list.join('·')}';
          if (clampMonthEnd && pos.any((x) => x > 28)) base += ' (없는 달은 말일)';
        }
      case Freq.yearly:
        base = '${interval == 1 ? '매년' : '$interval년마다'} ${s.month}월 ${s.day}일';
    }
    if (until != null) base += ' · ${until!.year}.${until!.month}.${until!.day}까지';
    if (count != null) base += ' · $count회';
    return base;
  }
}

/// 등록 화면의 빠른 선택 항목. 시작 날짜에서 값이 정해진다.
enum RepeatPreset {
  none, daily, weekly, monthlyDate, monthlyNth, monthlyLastWeekday, monthlyLast, yearly, weekdays, lunarYearly, lunarMonthly, custom
}

/// 시작일이 그 달의 마지막 7일 안이면 "마지막 ○요일"도 고를 수 있다.
bool isLastWeekdayOfMonth(DateTime s) => s.day + 7 > DateTime(s.year, s.month + 1, 0).day;

int nthOfMonth(DateTime s) => ((s.day - 1) ~/ 7) + 1;

Recurrence? presetRule(RepeatPreset p, DateTime start) {
  final s = DateTime(start.year, start.month, start.day);
  switch (p) {
    case RepeatPreset.none:
    case RepeatPreset.custom:
      return null;
    case RepeatPreset.daily:
      return const Recurrence(freq: Freq.daily);
    case RepeatPreset.weekly:
      return Recurrence(freq: Freq.weekly, weekdays: [s.weekday]);
    case RepeatPreset.weekdays:
      return const Recurrence(freq: Freq.weekly, weekdays: [1, 2, 3, 4, 5]);
    case RepeatPreset.monthlyDate:
      return Recurrence(freq: Freq.monthly, monthDays: [s.day]);
    case RepeatPreset.monthlyNth:
      return Recurrence(freq: Freq.monthly, nth: nthOfMonth(s) > 4 ? -1 : nthOfMonth(s), nthWeekday: s.weekday);
    case RepeatPreset.monthlyLastWeekday:
      return Recurrence(freq: Freq.monthly, nth: -1, nthWeekday: s.weekday);
    case RepeatPreset.monthlyLast:
      return const Recurrence(freq: Freq.monthly, monthDays: [-1]);
    case RepeatPreset.yearly:
      return const Recurrence(freq: Freq.yearly);
    case RepeatPreset.lunarYearly:
      return const Recurrence(freq: Freq.yearly, lunar: true);
    case RepeatPreset.lunarMonthly:
      return const Recurrence(freq: Freq.monthly, lunar: true);
  }
}

/// [start] 기준으로 선택 가능한 빠른 선택 목록(순서대로)과 표시 이름.
List<(RepeatPreset, String)> presetChoices(DateTime start) {
  final s = DateTime(start.year, start.month, start.day);
  final n = nthOfMonth(s);
  final ls = solarToLunar(s);
  return [
    (RepeatPreset.none, '반복 안 함'),
    (RepeatPreset.daily, '매일'),
    (RepeatPreset.weekly, '매주 ${Recurrence.wdFull(s.weekday)}'),
    (RepeatPreset.monthlyDate, '매월 ${s.day}일'),
    if (n <= 4) (RepeatPreset.monthlyNth, '매월 ${Recurrence.nthLabel(n)} ${Recurrence.wdFull(s.weekday)}'),
    if (isLastWeekdayOfMonth(s))
      (RepeatPreset.monthlyLastWeekday, '매월 마지막 ${Recurrence.wdFull(s.weekday)}'),
    (RepeatPreset.monthlyLast, '매월 마지막 날'),
    (RepeatPreset.yearly, '매년 ${s.month}월 ${s.day}일'),
    if (ls != null) (RepeatPreset.lunarYearly, '매년 음력 ${ls.month}월 ${ls.day}일'),
    if (ls != null) (RepeatPreset.lunarMonthly, '매월 음력 ${ls.day}일'),
    (RepeatPreset.weekdays, '평일 (월~금)'),
    (RepeatPreset.custom, '맞춤 설정…'),
  ];
}

/// 이미 있는 규칙이 어떤 빠른 선택과 같은지. 종료 조건이 있거나 맞는 게 없으면 맞춤.
RepeatPreset presetOf(Recurrence? r, DateTime start) {
  if (r == null) return RepeatPreset.none;
  if (r.until != null || r.count != null) return RepeatPreset.custom;
  for (final p in RepeatPreset.values) {
    if (p == RepeatPreset.none || p == RepeatPreset.custom) continue;
    final pr = presetRule(p, start);
    if (pr != null && pr == r) return p;
  }
  return RepeatPreset.custom;
}
