import 'lunar_table.g.dart';

/// 음력 변환. 1900~2049는 한국천문연구원(KASI) 공식 데이터, 2050~2200은 천문 계산으로 만든 표를 쓴다.
/// (tool/gen_calendar_data.py 참고. 천문 계산은 KASI와 1913~2049 전 구간 일 단위로 일치 확인됨)
/// 표 범위 밖의 날짜는 null을 돌려준다.
final _epoch = DateTime.utc(1900, 1, 1);

/// 1900-01-01을 0으로 하는 일수.
int dayNumber(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(_epoch).inDays;

DateTime dateFromDayNumber(int dn) => DateTime(1900, 1, 1 + dn);

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

LunarDate? solarToLunar(DateTime date) {
  final dn = dayNumber(date);
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
  final idx = year - lunarTableFirstYear;
  if (idx < 0 || idx >= _years.length) return null;
  final y = _years[idx];
  for (var i = 0; i < y.starts.length; i++) {
    if (y.numbers[i] == month && y.leaps[i] == leap) {
      final next = i + 1 < y.starts.length ? y.starts[i + 1] : y.end;
      if (day < 1 || day > next - y.starts[i]) return null;
      return dateFromDayNumber(y.starts[i] + day - 1);
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
