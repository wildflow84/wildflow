import 'lunar_table.g.dart';

/// 음력 변환. 1900~2049는 한국천문연구원(KASI) 공식 데이터, 2050~2200은 천문 계산으로 만든 표를 쓴다.
/// (tool/gen_calendar_data.py 참고. 천문 계산은 KASI와 1913~2049 전 구간 일 단위로 일치 확인됨)
/// 표 범위 밖의 날짜는 null을 돌려준다.
final _epoch = DateTime.utc(1900, 1, 1);

/// 1900-01-01을 0으로 하는 일수.
int dayNumber(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(_epoch).inDays;

DateTime dateFromDayNumber(int dn) => DateTime(1900, 1, 1 + dn);

/// 일수 -> (연, 월, 일). DateTime 을 만들지 않는 정수 계산이라 반복 규칙을 수천 번 검사할 때 훨씬 빠르다.
(int, int, int) civilFromDayNumber(int dn) {
  final z = dn - 25567 + 719468; // 1900-01-01 은 1970-01-01 의 25567일 전
  final era = (z >= 0 ? z : z - 146096) ~/ 146097;
  final doe = z - era * 146097;
  final yoe = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
  final doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100);
  final mp = (5 * doy + 2) ~/ 153;
  final d = doy - (153 * mp + 2) ~/ 5 + 1;
  final m = mp < 10 ? mp + 3 : mp - 9;
  return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d);
}

/// 일수의 요일 (1=월 ... 7=일). 1900-01-01 이 월요일이다.
int weekdayOfDayNumber(int dn) => dn % 7 + 1;

class LunarDate {
  final int year, month, day;
  final bool leap;
  const LunarDate(this.year, this.month, this.day, {this.leap = false});

  String get monthLabel => '${leap ? '윤' : ''}$month월';

  @override
  String toString() => '$year-${leap ? '윤' : ''}$month-$day';

  @override
  bool operator ==(Object other) =>
      other is LunarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.leap == leap;

  @override
  int get hashCode => Object.hash(year, month, day, leap);
}

class _LunarYear {
  final int year;
  final List<int> starts; // 각 달의 시작 일수 (윤달 포함, 시간순)
  final List<int> numbers;
  final List<bool> leaps;
  final int end; // 다음 해 설날
  _LunarYear(this.year, this.starts, this.numbers, this.leaps, this.end);
}

final List<_LunarYear> _years = _build();

List<_LunarYear> _build() {
  final out = <_LunarYear>[];
  for (final r in lunarTable) {
    final year = r[0], start = r[1], leapMonth = r[2], mask = r[3], n = r[4];
    final starts = <int>[], nums = <int>[], leaps = <bool>[];
    var cur = start, no = 1, isLeap = false;
    for (var i = 0; i < n; i++) {
      starts.add(cur);
      nums.add(no);
      leaps.add(isLeap);
      cur += ((mask >> i) & 1) == 1 ? 30 : 29;
      if (leapMonth != 0 && no == leapMonth && !isLeap) {
        isLeap = true; // 다음 달이 윤달
      } else {
        isLeap = false;
        no++;
      }
    }
    out.add(_LunarYear(year, starts, nums, leaps, cur));
  }
  return out;
}

/// 변환 가능한 양력 범위 (1900-01-31 ~ 2200년 말 무렵)
DateTime get lunarRangeStart => dateFromDayNumber(_years.first.starts.first);
DateTime get lunarRangeEnd => dateFromDayNumber(_years.last.end - 1);

LunarDate? solarToLunar(DateTime date) => solarToLunarDn(dayNumber(date));

LunarDate? solarToLunarDn(int dn) {
  if (dn < _years.first.starts.first || dn >= _years.last.end) return null;
  var lo = 0, hi = _years.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (_years[mid].starts.first <= dn) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  final y = _years[lo];
  var i = y.starts.length - 1;
  while (y.starts[i] > dn) {
    i--;
  }
  return LunarDate(y.year, y.numbers[i], dn - y.starts[i] + 1, leap: y.leaps[i]);
}

DateTime? lunarToSolar(int year, int month, int day, {bool leap = false}) {
  final dn = lunarToSolarDn(year, month, day, leap: leap);
  return dn == null ? null : dateFromDayNumber(dn);
}

int? lunarToSolarDn(int year, int month, int day, {bool leap = false}) {
  final idx = year - lunarTableFirstYear;
  if (idx < 0 || idx >= _years.length) return null;
  final y = _years[idx];
  for (var i = 0; i < y.starts.length; i++) {
    if (y.numbers[i] == month && y.leaps[i] == leap) {
      final next = i + 1 < y.starts.length ? y.starts[i + 1] : y.end;
      if (day < 1 || day > next - y.starts[i]) return null;
      return y.starts[i] + day - 1;
    }
  }
  return null;
}

/// 음력 해의 간지 이름 (예: 2026 -> 병오)
String ganjiYear(int year) {
  const stems = '갑을병정무기경신임계';
  const branches = '자축인묘진사오미신유술해';
  return '${stems[(year - 4) % 10]}${branches[(year - 4) % 12]}';
}
