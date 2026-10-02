import 'package:cloud_firestore/cloud_firestore.dart';

enum ItemType { event, todo }

enum Visibility { shared, private }

enum Repeat { none, daily, weekly, monthly, yearly }

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
  final Repeat repeat;

  /// 이동형 반복 (약 먹기처럼 "항상 하나만" 존재하는 할 일).
  /// [rollEvery] > 0 이면 완료 처리할 때 완료되는 대신 날짜가 다음 일정으로 옮겨진다.
  final int rollEvery;
  final RollUnit rollUnit;
  final bool rollFromCompletion; // true: 완료한 날 기준, false: 예정일 기준

  /// 마지막으로 완료한 사람/시각 (알림, 이력용)
  final String? lastDoneBy;
  final DateTime? lastDoneAt;

  bool get isRolling => rollEvery > 0;

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
    this.rollEvery = 0,
    this.rollUnit = RollUnit.day,
    this.rollFromCompletion = true,
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
    int? rollEvery,
    RollUnit? rollUnit,
    bool? rollFromCompletion,
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
        rollEvery: rollEvery ?? this.rollEvery,
        rollUnit: rollUnit ?? this.rollUnit,
        rollFromCompletion: rollFromCompletion ?? this.rollFromCompletion,
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
        'rollEvery': rollEvery,
        'rollUnit': rollUnit.name,
        'rollFrom': rollFromCompletion ? 'completion' : 'schedule',
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
      rollEvery: (m['rollEvery'] as num?)?.toInt() ?? 0,
      rollUnit: byName(RollUnit.values, m['rollUnit'], RollUnit.day),
      rollFromCompletion: (m['rollFrom'] ?? 'completion') == 'completion',
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
  switch (item.repeat) {
    case Repeat.none:
      final e = item.end == null ? s : dateOnly(item.end!);
      return !d.isAfter(e);
    case Repeat.daily:
      return true;
    case Repeat.weekly:
      return d.difference(s).inDays % 7 == 0;
    case Repeat.monthly:
      // 31일 같은 날짜는 해당 달 말일로 보정
      final last = DateTime(d.year, d.month + 1, 0).day;
      return d.day == (s.day > last ? last : s.day);
    case Repeat.yearly:
      return d.month == s.month && d.day == s.day;
  }
}

bool isDoneOn(Item item, DateTime day) => item.repeat == Repeat.none
    ? item.done
    : item.doneDates.contains(dateKey(day));


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
///  - 완료한 날 기준: 오늘 + 간격 (약 먹기: 오늘 먹으면 내일)
///  - 예정일 기준: 예정일 + 간격. 밀려서 이미 지난 날짜가 되면 오늘 이후가 될 때까지 건너뛴다.
DateTime nextRollDate(Item item, DateTime today) {
  final t = dateOnly(today);
  if (item.rollFromCompletion) return _addRoll(t, item.rollEvery, item.rollUnit);
  var next = _addRoll(dateOnly(item.start), item.rollEvery, item.rollUnit);
  while (!next.isAfter(t)) {
    next = _addRoll(next, item.rollEvery, item.rollUnit);
  }
  return next;
}

/// 예: 매일, 3일마다, 매주, 2주마다, 매월, 매년
String rollLabel(Item item) {
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
  final sameDay = i.repeat != Repeat.none || dateOnly(e) == dateOnly(i.start);
  return sameDay ? '$s–${_hhmm(e)}' : '$s → ${e.month}/${e.day} ${_hhmm(e)}';
}

/// 이동형 반복 완료 후의 새 시작 일시: 다음 날짜로 옮기되 시각은 유지한다.
DateTime rollStart(Item item, DateTime today) {
  final d = nextRollDate(item, today);
  return item.allDay ? d : DateTime(d.year, d.month, d.day, item.start.hour, item.start.minute);
}

/// 캘린더 칸 칩 앞에 붙이는 짧은 시각. 일정은 "15:00", 할 일은 마감이라 "~15:00".
String? chipTimeLabel(Item i) {
  if (i.allDay) return null;
  return i.type == ItemType.todo ? '~${_hhmm(i.start)}' : _hhmm(i.start);
}

/// 할 일이 마감을 넘겼는지. 시각이 있으면 그 시각 기준, 없으면 날짜가 오늘 이전일 때.
bool isOverdue(Item i, DateTime now) {
  if (i.type != ItemType.todo || i.repeat != Repeat.none) return false;
  return i.allDay ? dateOnly(i.start).isBefore(dateOnly(now)) : i.start.isBefore(now);
}
