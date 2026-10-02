import 'package:cloud_firestore/cloud_firestore.dart';

import 'recurrence.dart';

enum ItemType { event, todo }

enum Visibility { shared, private }

enum Repeat { none, daily, weekly, monthly, yearly }

/// 반복 일정 삭제 범위
enum RepeatDelete { thisOnly, following, all }

/// 이동형 반복의 단위
enum RollUnit { day, week, month, year }

/// 일정(event)과 할 일(todo)을 한 컬렉션에서 다룬다.
class Item {
  final String id;
  final ItemType type;
  final String title;
  final String note;
  final String location; // 위치(장소 이름/주소). 지도 앱으로 열 수 있다.
  final DateTime start; // 날짜만 쓰는 경우 00:00
  final DateTime? end; // 멀티데이 일정의 마지막 날 (포함)
  final bool allDay;
  final bool done; // todo 전용 (반복 항목은 doneDates 사용)
  final List<String> doneDates; // 반복 todo의 완료 처리된 날짜 yyyy-MM-dd
  /// 카테고리 여러 개 가능. 첫 번째가 대표(색상 기준).
  final List<String> categories;
  final int? color; // 항목별 색 (null이면 카테고리 색)
  final Visibility visibility;
  final String ownerUid;
  /// 이전 버전의 단순 반복(매일/매주/매월/매년). [rule]이 있으면 rule이 우선하고, 이 값은 호환용으로 같이 저장한다.
  final Repeat repeat;

  /// 구글 캘린더 방식의 반복 규칙 (간격, 요일, 매월 N일/마지막 날/n번째 요일, 종료 조건).
  final Recurrence? rule;

  /// 반복의 마지막 날(포함). null이면 끝없이 반복. "이 날짜 이후 삭제"로 설정된다.
  final DateTime? repeatUntil;

  /// 반복에서 빠진 날짜(yyyy-MM-dd). "이 날짜만 삭제"로 추가된다.
  final List<String> exceptions;

  /// 이동형 반복 (약 먹기처럼 "항상 하나만" 존재하는 할 일).
  /// [rollEvery] > 0 이면 완료 처리할 때 완료되는 대신 날짜가 다음 일정으로 옮겨진다.
  final int rollEvery;
  final RollUnit rollUnit;
  final bool rollFromCompletion; // true: 완료한 날 기준, false: 예정일 기준 (기본)

  /// 이동형 반복에 구글 캘린더식 규칙을 쓰는 경우 (예: 매주 목요일, 평일, 매월 마지막 날).
  /// 달력에는 다음 1회만 보이고, 완료하면 규칙에 맞는 다음 날짜로 옮겨진다. [rule]과는 별개다.
  final Recurrence? rollRule;

  /// 마지막으로 완료한 사람/시각 (알림, 이력용)
  final String? lastDoneBy;
  final DateTime? lastDoneAt;

  bool get isRolling => rollRule != null || rollEvery > 0;

  /// 실제로 적용되는 반복 규칙. 옛 데이터(repeat만 있는 항목)는 같은 의미의 규칙으로 바꿔서 쓴다.
  Recurrence? get effectiveRule => rule ?? legacyRule(repeat, start);

  bool get isRecurring => effectiveRule != null;

  String get category => categories.first;

  const Item({
    required this.id,
    required this.type,
    required this.title,
    required this.start,
    required this.ownerUid,
    this.note = '',
    this.location = '',
    this.end,
    this.allDay = true,
    this.done = false,
    this.doneDates = const [],
    this.categories = const ['default'],
    this.color,
    this.visibility = Visibility.shared,
    this.repeat = Repeat.none,
    this.rule,
    this.repeatUntil,
    this.exceptions = const [],
    this.rollEvery = 0,
    this.rollUnit = RollUnit.day,
    this.rollFromCompletion = false,
    this.rollRule,
    this.lastDoneBy,
    this.lastDoneAt,
  });

  Item copyWith({
    ItemType? type,
    String? title,
    String? note,
    String? location,
    DateTime? start,
    DateTime? end,
    bool clearEnd = false,
    bool? allDay,
    bool? done,
    List<String>? doneDates,
    List<String>? categories,
    int? color,
    bool clearColor = false,
    Visibility? visibility,
    Repeat? repeat,
    Recurrence? rule,
    bool clearRule = false,
    DateTime? repeatUntil,
    bool clearRepeatUntil = false,
    List<String>? exceptions,
    int? rollEvery,
    RollUnit? rollUnit,
    bool? rollFromCompletion,
    Recurrence? rollRule,
    bool clearRollRule = false,
    String? lastDoneBy,
    DateTime? lastDoneAt,
  }) =>
      Item(
        id: id,
        ownerUid: ownerUid,
        type: type ?? this.type,
        title: title ?? this.title,
        note: note ?? this.note,
        location: location ?? this.location,
        start: start ?? this.start,
        end: clearEnd ? null : (end ?? this.end),
        allDay: allDay ?? this.allDay,
        done: done ?? this.done,
        doneDates: doneDates ?? this.doneDates,
        categories: categories ?? this.categories,
        color: clearColor ? null : (color ?? this.color),
        visibility: visibility ?? this.visibility,
        repeat: repeat ?? this.repeat,
        rule: clearRule ? null : (rule ?? this.rule),
        repeatUntil: clearRepeatUntil ? null : (repeatUntil ?? this.repeatUntil),
        exceptions: exceptions ?? this.exceptions,
        rollEvery: rollEvery ?? this.rollEvery,
        rollUnit: rollUnit ?? this.rollUnit,
        rollFromCompletion: rollFromCompletion ?? this.rollFromCompletion,
        rollRule: clearRollRule ? null : (rollRule ?? this.rollRule),
        lastDoneBy: lastDoneBy ?? this.lastDoneBy,
        lastDoneAt: lastDoneAt ?? this.lastDoneAt,
      );

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'title': title,
        'note': note,
        'location': location,
        'start': Timestamp.fromDate(start),
        'end': end == null ? null : Timestamp.fromDate(end!),
        'allDay': allDay,
        'done': done,
        'doneDates': doneDates,
        'category': categories.first, // 이전 버전 호환
        'categories': categories,
        'color': color,
        'visibility': visibility.name,
        'ownerUid': ownerUid,
        'repeat': repeat.name,
        'rule': rule?.toMap(),
        'repeatUntil': repeatUntil == null ? null : Timestamp.fromDate(repeatUntil!),
        'exceptions': exceptions,
        'rollEvery': rollEvery,
        'rollUnit': rollUnit.name,
        'rollFrom': rollFromCompletion ? 'completion' : 'schedule',
        'rollRule': rollRule?.toMap(),
        'lastDoneBy': lastDoneBy,
        'lastDoneAt': lastDoneAt == null ? null : Timestamp.fromDate(lastDoneAt!),
      };

  factory Item.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data()!;
    T byName<T extends Enum>(List<T> values, String? n, T fallback) =>
        values.firstWhere((v) => v.name == n, orElse: () => fallback);
    return Item(
      id: doc.id,
      type: byName(ItemType.values, m['type'], ItemType.todo),
      title: m['title'] ?? '',
      note: m['note'] ?? '',
      location: m['location'] ?? '',
      start: (m['start'] as Timestamp).toDate(),
      end: (m['end'] as Timestamp?)?.toDate(),
      allDay: m['allDay'] ?? true,
      done: m['done'] ?? false,
      doneDates: List<String>.from(m['doneDates'] ?? const []),
      categories: _readCategories(m),
      color: (m['color'] as num?)?.toInt(),
      visibility: byName(Visibility.values, m['visibility'], Visibility.shared),
      ownerUid: m['ownerUid'] ?? '',
      repeat: byName(Repeat.values, m['repeat'], Repeat.none),
      rule: m['rule'] is Map ? Recurrence.fromMap(Map<String, dynamic>.from(m['rule'] as Map)) : null,
      repeatUntil: (m['repeatUntil'] as Timestamp?)?.toDate(),
      exceptions: List<String>.from(m['exceptions'] ?? const []),
      rollEvery: (m['rollEvery'] as num?)?.toInt() ?? 0,
      rollUnit: byName(RollUnit.values, m['rollUnit'], RollUnit.day),
      rollFromCompletion: m['rollFrom'] == 'completion',
      rollRule: m['rollRule'] is Map ? Recurrence.fromMap(Map<String, dynamic>.from(m['rollRule'] as Map)) : null,
      lastDoneBy: m['lastDoneBy'] as String?,
      lastDoneAt: (m['lastDoneAt'] as Timestamp?)?.toDate(),
    );
  }
}

List<String> _readCategories(Map<String, dynamic> m) {
  final list = (m['categories'] as List?)?.cast<String>() ?? const [];
  if (list.isNotEmpty) return list;
  return [(m['category'] as String?) ?? 'default'];
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [day]에 [item]이 나타나는지 (반복 규칙 + 멀티데이 포함).
bool occursOn(Item item, DateTime day) {
  final d = dateOnly(day);
  final s = dateOnly(item.start);
  if (d.isBefore(s)) return false;
  final rule = item.effectiveRule;
  if (rule != null) {
    if (item.repeatUntil != null && d.isAfter(dateOnly(item.repeatUntil!))) return false;
    if (item.exceptions.contains(dateKey(d))) return false;
    return rule.occursOn(item.start, d);
  }
  final e = item.end == null ? s : dateOnly(item.end!);
  return !d.isAfter(e);
}

/// 이전 버전의 단순 반복을 같은 의미의 규칙으로: 매월은 시작일의 날짜(없는 달은 말일), 매년도 말일 조정.
Recurrence? legacyRule(Repeat r, DateTime start) {
  switch (r) {
    case Repeat.none:
      return null;
    case Repeat.daily:
      return const Recurrence(freq: Freq.daily);
    case Repeat.weekly:
      return Recurrence(freq: Freq.weekly, weekdays: [start.weekday]);
    case Repeat.monthly:
      return Recurrence(freq: Freq.monthly, monthDays: [start.day], clampMonthEnd: true);
    case Repeat.yearly:
      return const Recurrence(freq: Freq.yearly, clampMonthEnd: true);
  }
}

/// 호환용 repeat 값
Repeat repeatFor(Recurrence? r) {
  if (r == null) return Repeat.none;
  switch (r.freq) {
    case Freq.daily:
      return Repeat.daily;
    case Freq.weekly:
      return Repeat.weekly;
    case Freq.monthly:
      return Repeat.monthly;
    case Freq.yearly:
      return Repeat.yearly;
  }
}

bool isDoneOn(Item item, DateTime day) =>
    item.isRecurring ? item.doneDates.contains(dateKey(day)) : item.done;


DateTime _addRoll(DateTime d, int every, RollUnit unit) {
  switch (unit) {
    case RollUnit.day:
      return DateTime(d.year, d.month, d.day + every);
    case RollUnit.week:
      return DateTime(d.year, d.month, d.day + 7 * every);
    case RollUnit.month:
      final last = DateTime(d.year, d.month + every + 1, 0).day; // 31일 -> 짧은 달 말일로 보정
      return DateTime(d.year, d.month + every, d.day > last ? last : d.day);
    case RollUnit.year:
      final last = DateTime(d.year + every, d.month + 1, 0).day; // 2/29 보정
      return DateTime(d.year + every, d.month, d.day > last ? last : d.day);
  }
}

/// 이동형 반복 항목을 [today]에 완료했을 때의 다음 날짜.
///  - 규칙형(rollRule): 예정일·오늘 중 더 늦은 날 다음으로 규칙에 처음 맞는 날. (매주 목요일, 매월 마지막 날 등)
///  - 간격형 / 예정일 기준(기본): 예정일 + 간격. 밀려서 이미 지난 날짜가 되면 오늘 이후가 될 때까지 건너뛴다.
///  - 간격형 / 완료한 날 기준: (오늘과 예정일 중 더 늦은 날) + 간격.
///    약 먹기: 오늘 먹으면 내일, 며칠 밀려서 먹어도 내일, **내일 것을 미리 오늘 먹으면 모레**.
DateTime nextRollDate(Item item, DateTime today) {
  final t = dateOnly(today);
  final due = dateOnly(item.start);
  final rule = item.rollRule;
  if (rule != null) {
    // 규칙대로: 예정일과 오늘 중 더 늦은 날 다음으로 처음 맞는 날. (미리 완료하면 그 다음 회차로 한 칸 전진)
    final after = due.isAfter(t) ? due : t;
    return rule.nextAfter(due, after) ?? due;
  }
  if (item.rollFromCompletion) {
    final base = due.isAfter(t) ? due : t; // 미리 완료하면 예정일 기준으로 한 칸 전진
    return _addRoll(base, item.rollEvery, item.rollUnit);
  }
  var next = _addRoll(due, item.rollEvery, item.rollUnit);
  while (!next.isAfter(t)) {
    next = _addRoll(next, item.rollEvery, item.rollUnit);
  }
  return next;
}

/// 예: 매일, 3일마다, 매주, 2주마다, 매월, 매년
String rollLabel(Item item) {
  if (item.rollRule != null) return item.rollRule!.describe(item.start);
  final e = item.rollEvery;
  const unit = {RollUnit.day: '일', RollUnit.week: '주', RollUnit.month: '개월', RollUnit.year: '년'};
  if (e == 1) {
    return const {RollUnit.day: '매일', RollUnit.week: '매주', RollUnit.month: '매월', RollUnit.year: '매년'}[item.rollUnit]!;
  }
  return '$e${unit[item.rollUnit]}마다';
}


String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 종료 시각이 설정되어 있는지 (종일이 아닐 때 종료 시각이 00:00이 아니면 설정된 것으로 본다)
bool hasEndTime(Item i) => !i.allDay && i.end != null && (i.end!.hour != 0 || i.end!.minute != 0);

/// 시간 표기. 종일이면 null. 예: "15:00", "15:00–16:30", "15:00 → 10/17 12:00"
String? timeLabel(Item i) {
  if (i.allDay) return null;
  final s = _hhmm(i.start);
  if (i.type == ItemType.todo) return '$s까지'; // 할 일의 시각은 시작이 아니라 마감
  if (!hasEndTime(i)) return s;
  final e = i.end!;
  final sameDay = i.isRecurring || dateOnly(e) == dateOnly(i.start);
  return sameDay ? '$s–${_hhmm(e)}' : '$s → ${e.month}/${e.day} ${_hhmm(e)}';
}

/// 이동형 반복 완료 후의 새 시작 일시: 다음 날짜로 옮기되 시각은 유지한다.
DateTime rollStart(Item item, DateTime today) {
  final d = nextRollDate(item, today);
  return item.allDay ? d : DateTime(d.year, d.month, d.day, item.start.hour, item.start.minute);
}

/// 이동형 반복 항목을 [now]에 완료했을 때의 새 항목.
///  - 다음 날짜가 있으면 시작일을 옮긴다(시각 유지). 횟수 종료가 있으면 1 줄인다.
///  - 규칙이 끝났으면(종료일 지남/횟수 소진) 완료 처리한다.
Item rollNextItem(Item item, DateTime now, String? byUid) {
  final log = [...item.doneDates, dateKey(now)];
  final trimmed = log.length > 60 ? log.sublist(log.length - 60) : log; // 최근 60회만
  final rule = item.rollRule;
  if (rule != null) {
    final due = dateOnly(item.start);
    final t = dateOnly(now);
    final after = due.isAfter(t) ? due : t;
    final next = rule.nextAfter(due, after);
    final remaining = rule.count == null ? null : rule.count! - 1;
    if (next == null || (remaining != null && remaining <= 0)) {
      return item.copyWith(done: true, doneDates: trimmed, lastDoneBy: byUid, lastDoneAt: now);
    }
    return item.copyWith(
      start: item.allDay ? next : DateTime(next.year, next.month, next.day, item.start.hour, item.start.minute),
      rollRule: remaining == null ? rule : rule.copyWith(count: remaining),
      done: false,
      doneDates: trimmed,
      lastDoneBy: byUid,
      lastDoneAt: now,
    );
  }
  return item.copyWith(
    start: rollStart(item, now),
    done: false,
    doneDates: trimmed,
    lastDoneBy: byUid,
    lastDoneAt: now,
  );
}

/// 캘린더 칸 칩 앞에 붙이는 짧은 시각. 일정은 "15:00", 할 일은 마감이라 "~15:00".
String? chipTimeLabel(Item i) {
  if (i.allDay) return null;
  return i.type == ItemType.todo ? '~${_hhmm(i.start)}' : _hhmm(i.start);
}

/// 할 일이 마감을 넘겼는지. 시각이 있으면 그 시각 기준, 없으면 날짜가 오늘 이전일 때.
bool isOverdue(Item i, DateTime now) {
  if (i.type != ItemType.todo || i.isRecurring) return false;
  return i.allDay ? dateOnly(i.start).isBefore(dateOnly(now)) : i.start.isBefore(now);
}


/// 반복 항목에서 [day] 회차를 [scope] 범위로 삭제한 결과.
/// 항목 전체를 지워야 하면 null, 아니면 수정된 항목을 돌려준다.
Item? applyRepeatDelete(Item item, DateTime day, RepeatDelete scope) {
  final d = dateOnly(day);
  switch (scope) {
    case RepeatDelete.all:
      return null;
    case RepeatDelete.thisOnly:
      final key = dateKey(d);
      if (item.exceptions.contains(key)) return item;
      return item.copyWith(exceptions: [...item.exceptions, key]);
    case RepeatDelete.following:
      // 첫 회차부터 지우면 남는 게 없으니 전체 삭제와 같다.
      if (!d.isAfter(dateOnly(item.start))) return null;
      return item.copyWith(repeatUntil: DateTime(d.year, d.month, d.day - 1));
  }
}


/// 항목을 [deltaDays]일만큼 옮긴다 (드래그로 날짜 변경). 시각과 기간(여러 날 일정)은 그대로 유지.
Item moveItemByDays(Item item, int deltaDays) {
  DateTime shift(DateTime d) => DateTime(d.year, d.month, d.day + deltaDays, d.hour, d.minute);
  return item.copyWith(
    start: shift(item.start),
    end: item.end == null ? null : shift(item.end!),
  );
}
