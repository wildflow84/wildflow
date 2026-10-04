import 'package:cloud_firestore/cloud_firestore.dart';

import 'category.dart' show subscriptionCategoryId;
import 'lunar.dart' show solarToLunar;
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
  final double? lat; // 장소 검색으로 고른 좌표 (직접 입력한 위치는 null)
  final double? lng;
  final String? photoUrl; // 위치 사진 (위키백과 등에서 찾은 주소)
  final bool overseas; // 해외 장소 (출발 시간 계산에 쓸 서비스 구분)
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

  /// 체크리스트 (장보기, 준비물 등). 같이 보기 항목이면 둘 다 보면서 체크한다.
  final List<CheckEntry> checklist;
  /// 할 일 담당자 uid. 비어 있으면 담당을 정하지 않음(만든 사람 몫).
  final String assignee;
  /// 목록에 D-day(남은 날/지난 날)를 표시할지
  final bool dday;
  /// 출발 시간 알림: 현재 위치에서 이 일정 장소까지 걸리는 시간을 계산해서 출발할 때 알려 준다 (장소 좌표가 있는 시각 일정)
  final bool departAlert;
  /// 출발 시간 계산 기준: car(자동차 길찾기) / walk(도보 어림값). 예전 transit(대중교통)은 car로 본다
  final String departMode;
  /// 기념일 기준 연도. 정해져 있으면 매년 반복 항목에 `N주년`(또는 생일이면 N번째)을 표시. null이면 표시 안 함.
  final int? annivYear;
  /// 일정 구독(.ics)에서 가져온 항목이면 그 구독의 id. 서버가 12시간마다 원본대로 갱신한다.
  final String? subscriptionId;
  /// 알림: 시작(마감) 몇 분 전에 알릴지. null이면 알림 없음. 종일 항목은 그날 오전 9시 기준(1440=전날 오전 9시).
  final int? remindMinutes;
  /// 서버에 저장돼 있는 반복 알림의 다음 시각과 마지막 시각 (앱이 알림 목록을 새로 채울 때인지 가늠하는 데 쓴다)
  final DateTime? remindStoredAt;
  final DateTime? remindStoredLast;
  /// 반복 항목의 회차별 체크 기록: 날짜(yyyy-MM-dd) → 체크한 항목의 글자. 반복이 아니면 안 쓴다.
  final Map<String, List<String>> checksByDate;

  /// 마지막으로 완료한 사람/시각 (알림, 이력용)
  final String? lastDoneBy;
  final DateTime? lastDoneAt;

  /// [day]의 체크리스트. 반복 항목은 회차(날짜)마다 따로 체크 상태를 가진다.
  List<CheckEntry> checklistOn(DateTime day) {
    if (!isRecurring) return checklist;
    final done = checksByDate[dateKey(day)] ?? const <String>[];
    return [for (final c in checklist) CheckEntry(c.text, done: done.contains(c.text))];
  }

  int checksLeftOn(DateTime day) => checklistOn(day).where((c) => !c.done).length;

  /// [day] 회차의 체크 상태를 바꾼 항목을 돌려준다 (반복이면 날짜별 기록, 아니면 본문). [done]이 null이면 토글.
  Item withCheck(DateTime day, int index, [bool? done]) {
    final cur = checklistOn(day);
    if (index < 0 || index >= cur.length) return this;
    final v = done ?? !cur[index].done;
    if (!isRecurring) {
      final l = [...checklist];
      l[index] = l[index].copyWith(done: v);
      return copyWith(checklist: l);
    }
    final key = dateKey(day);
    final set = {...(checksByDate[key] ?? const <String>[])};
    v ? set.add(cur[index].text) : set.remove(cur[index].text);
    return copyWith(checksByDate: _trimChecks({...checksByDate, key: set.toList()}));
  }

  /// [day] 회차의 체크를 모두 켜거나 끈다.
  Item withAllChecks(DateTime day, bool done) {
    if (!isRecurring) return copyWith(checklist: allChecked(checklist, done));
    final key = dateKey(day);
    return copyWith(
        checksByDate: _trimChecks({...checksByDate, key: done ? [for (final c in checklist) c.text] : <String>[]}));
  }

  static Map<String, List<String>> _trimChecks(Map<String, List<String>> m) {
    final live = {for (final e in m.entries) if (e.value.isNotEmpty) e.key: e.value};
    if (live.length <= 60) return live;
    final keys = live.keys.toList()..sort();
    return {for (final k in keys.sublist(keys.length - 60)) k: live[k]!};
  }

  /// 같은 내용으로 새 항목을 만든다 (저장하면 새 id가 붙는다).
  factory Item.fresh(Item i) => Item(
        id: '',
        type: i.type,
        title: i.title,
        note: i.note,
        location: i.location,
        lat: i.lat,
        lng: i.lng,
        overseas: i.overseas,
        photoUrl: i.photoUrl,
        start: i.start,
        end: i.end,
        allDay: i.allDay,
        done: i.done,
        doneDates: i.doneDates,
        categories: i.categories,
        color: i.color,
        visibility: i.visibility,
        ownerUid: i.ownerUid,
        repeat: i.repeat,
        rule: i.rule,
        repeatUntil: i.repeatUntil,
        exceptions: i.exceptions,
        rollEvery: i.rollEvery,
        rollUnit: i.rollUnit,
        rollFromCompletion: i.rollFromCompletion,
        rollRule: i.rollRule,
        lastDoneBy: i.lastDoneBy,
        lastDoneAt: i.lastDoneAt,
        checklist: i.checklist,
        checksByDate: i.checksByDate,
        assignee: i.assignee,
        dday: i.dday,
        departAlert: i.departAlert,
        departMode: i.departMode,
        annivYear: i.annivYear,
        subscriptionId: null, // 복제본은 구독과 무관
        remindMinutes: i.remindMinutes,
      );

  /// 이 할 일이 [uid]의 몫인지: 담당자가 정해져 있으면 그 사람, 아니면 만든 사람.
  bool isMineTo(String uid) => assignee.isNotEmpty ? assignee == uid : ownerUid == uid;

  /// 알림을 보낼 시각. 서버가 이 값으로 푸시를 보낸다.
  /// 반복 일정(규칙)은 앞으로 알릴 시각들([remindTimes])을 함께 저장해 두고, 서버가 하나씩 보내며 다음 시각으로 넘긴다.
  DateTime? get remindAt {
    final r = remindMinutes;
    if (r == null) return null;
    if (isRecurring) {
      final t = remindTimes(DateTime.now());
      return t.isEmpty ? null : t.first;
    }
    final base = allDay ? DateTime(start.year, start.month, start.day, 9) : start;
    return base.subtract(Duration(minutes: r));
  }

  static const remindAhead = 120; // 반복 알림을 미리 저장해 두는 최대 개수
  static const remindRefillDays = 30; // 저장해 둔 알림이 이만큼 남으면 앱이 새로 채운다

  /// 반복 일정에서 [now] 이후로 알릴 시각들 (건너뛴 날과 이미 완료한 회차는 뺀다). 반복이 아니면 빈 목록.
  List<DateTime> remindTimes(DateTime now) {
    final r = remindMinutes;
    if (r == null || !isRecurring) return const [];
    final out = <DateTime>[];
    final today = dateOnly(now);
    for (var i = 0; i <= 400 && out.length < remindAhead; i++) {
      final d = DateTime(today.year, today.month, today.day + i);
      if (!occursOn(this, d) || doneDates.contains(dateKey(d))) continue;
      final base = allDay ? DateTime(d.year, d.month, d.day, 9) : DateTime(d.year, d.month, d.day, start.hour, start.minute);
      final at = base.subtract(Duration(minutes: r));
      if (at.isAfter(now)) out.add(at);
    }
    return out;
  }

  /// 반복 알림 목록을 새로 채워서 저장해야 하는지 (서버가 다음 시각으로 못 넘겼거나, 저장해 둔 게 곧 바닥날 때)
  bool needsRemindRefill(DateTime now) {
    if (remindMinutes == null || !isRecurring) return false;
    final fresh = remindTimes(now);
    if (fresh.isEmpty) return remindStoredAt != null;
    if (remindStoredAt == null || remindStoredAt != fresh.first) return true;
    final last = remindStoredLast;
    return last == null ||
        (last.isBefore(now.add(const Duration(days: remindRefillDays))) && fresh.last.isAfter(last));
  }

  /// 출발 시간 알림을 계산할 일정의 시작 시각 (서버가 이 값으로 곧 시작할 일정을 찾는다). 알림 조건이 안 맞으면 null.
  DateTime? get departFrom =>
      departAlert && type == ItemType.event && lat != null && lng != null && !allDay && !isRecurring ? start : null;

  int get checksLeft => checklist.where((c) => !c.done).length;
  bool get hasChecklist => checklist.isNotEmpty;

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
    this.lat,
    this.lng,
    this.overseas = false,
    this.photoUrl,
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
    this.checklist = const [],
    this.checksByDate = const {},
    this.assignee = '',
    this.dday = false,
    this.departAlert = false,
    this.departMode = 'car',
    this.annivYear,
    this.subscriptionId,
    this.remindMinutes,
    this.remindStoredAt,
    this.remindStoredLast,
  });

  Item copyWith({
    ItemType? type,
    String? title,
    String? note,
    String? location,
    double? lat,
    double? lng,
    bool clearCoords = false,
    bool? overseas,
    String? photoUrl,
    bool clearPhoto = false,
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
    List<CheckEntry>? checklist,
    Map<String, List<String>>? checksByDate,
    String? assignee,
    bool? dday,
    bool? departAlert,
    String? departMode,
    int? annivYear,
    bool clearAnniv = false,
    int? remindMinutes,
    bool clearRemind = false,
  }) =>
      Item(
        id: id,
        ownerUid: ownerUid,
        type: type ?? this.type,
        title: title ?? this.title,
        note: note ?? this.note,
        location: location ?? this.location,
        lat: clearCoords ? null : (lat ?? this.lat),
        lng: clearCoords ? null : (lng ?? this.lng),
        overseas: clearCoords ? false : (overseas ?? this.overseas),
        photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
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
        checklist: checklist ?? this.checklist,
        checksByDate: checksByDate ?? this.checksByDate,
        assignee: assignee ?? this.assignee,
        dday: dday ?? this.dday,
        departAlert: departAlert ?? this.departAlert,
        departMode: departMode ?? this.departMode,
        annivYear: clearAnniv ? null : (annivYear ?? this.annivYear),
        subscriptionId: subscriptionId,
        remindMinutes: clearRemind ? null : (remindMinutes ?? this.remindMinutes),
        remindStoredAt: remindStoredAt,
        remindStoredLast: remindStoredLast,
      );

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'title': title,
        'note': note,
        'location': location,
        'lat': lat,
        'lng': lng,
        'overseas': overseas,
        'photoUrl': photoUrl,
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
        'checklist': [for (final c in checklist) c.toMap()],
        'checksByDate': checksByDate,
        'assignee': assignee,
        'dday': dday,
        'departAlert': departAlert,
        'departMode': departMode,
        'departFrom': departFrom == null ? null : Timestamp.fromDate(departFrom!),
        'annivYear': annivYear,
        'subscriptionId': subscriptionId,
        'remindMinutes': remindMinutes,
        'remindAt': remindAt == null ? null : Timestamp.fromDate(remindAt!),
        'remindTimes': [for (final t in remindTimes(DateTime.now())) Timestamp.fromDate(t)],
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
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      overseas: m['overseas'] ?? false,
      photoUrl: m['photoUrl'] as String?,
      start: (m['start'] as Timestamp).toDate(),
      end: (m['end'] as Timestamp?)?.toDate(),
      allDay: m['allDay'] ?? true,
      done: m['done'] ?? false,
      doneDates: List<String>.from(m['doneDates'] ?? const []),
      categories: m['subscriptionId'] != null ? const [subscriptionCategoryId] : _readCategories(m),
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
      checklist: [
        for (final c in (m['checklist'] as List? ?? const []))
          if (c is Map) CheckEntry.fromMap(Map<String, dynamic>.from(c)),
      ],
      assignee: (m['assignee'] as String?) ?? '',
      dday: m['dday'] == true,
      departAlert: m['departAlert'] == true,
      departMode: m['departMode'] == 'walk' ? 'walk' : 'car',
      annivYear: (m['annivYear'] as num?)?.toInt(),
      subscriptionId: m['subscriptionId'] as String?,
      remindMinutes: (m['remindMinutes'] as num?)?.toInt(),
      remindStoredAt: (m['remindAt'] as Timestamp?)?.toDate(),
      remindStoredLast: () {
        final l = m['remindTimes'];
        return l is List && l.isNotEmpty && l.last is Timestamp ? (l.last as Timestamp).toDate() : null;
      }(),
      checksByDate: {
        for (final e in ((m['checksByDate'] as Map?) ?? const {}).entries)
          '${e.key}': List<String>.from(e.value as List),
      },
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

/// 완료 토글의 결과: 바뀐 항목과, "완료로 표시"한 것인지(상대에게 알릴지 정하는 데 씀)
class DoneToggle {
  final Item item;
  final bool marking;
  const DoneToggle(this.item, this.marking);
}

/// 완료 체크를 누른 결과를 계산한다 (저장은 호출한 쪽이). 앱과 홈 화면 위젯이 같은 규칙을 쓴다.
///  - 이동형 반복: 완료 대신 다음 일정으로 넘어간다
///  - 단일 항목: 완료 토글
///  - 규칙 반복: 그 날짜의 완료 기록을 토글
DoneToggle toggledDone(Item i, DateTime day, String uid, DateTime now) {
  if (i.isRolling) return DoneToggle(rollNextItem(i, now, uid), true);
  if (!i.isRecurring) {
    return DoneToggle(i.copyWith(done: !i.done, lastDoneBy: uid, lastDoneAt: now), !i.done);
  }
  final k = dateKey(day);
  final dd = [...i.doneDates];
  final marking = !dd.contains(k);
  marking ? dd.add(k) : dd.remove(k);
  return DoneToggle(i.copyWith(doneDates: dd, lastDoneBy: uid, lastDoneAt: now), marking);
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
      checklist: allChecked(item.checklist, false), // 다음 회차는 새로 체크
    );
  }
  return item.copyWith(
    start: rollStart(item, now),
    done: false,
    doneDates: trimmed,
    lastDoneBy: byUid,
    lastDoneAt: now,
    checklist: allChecked(item.checklist, false),
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

/// 반복 항목 수정 범위: 이 회차만 / 이 회차 이후 모두 / 전체
enum RepeatEdit { thisOnly, following, all }

/// 반복 항목 [original]의 [day] 회차를 [edited](수정한 내용)로 바꿀 때 저장할 항목들.
/// - 전체: [edited] 그대로
/// - 이 회차만: 원본에 그날 제외를 넣고, 그날 하루짜리 새 일정을 만든다
/// - 이후 모두: 원본은 전날까지로 끊고, 그날부터 [edited] 내용의 새 반복을 만든다 (첫 회차면 전체와 같다)
/// 새로 만들 항목은 id가 빈 문자열이다. [occurrenceStart]는 새 항목의 시작(날짜+시각).
List<Item> applyRepeatEdit(Item original, Item edited, DateTime day, RepeatEdit scope,
    {required DateTime occurrenceStart}) {
  final d = dateOnly(day);
  if (scope == RepeatEdit.following && !d.isAfter(dateOnly(original.start))) scope = RepeatEdit.all;
  switch (scope) {
    case RepeatEdit.all:
      return [edited];
    case RepeatEdit.thisOnly:
      final single = edited.copyWith(
        start: occurrenceStart,
        clearEnd: true,
        repeat: Repeat.none,
        clearRule: true,
        clearRepeatUntil: true,
        exceptions: const [],
        doneDates: const [],
        checksByDate: const {},
        clearRollRule: true,
        rollEvery: 0,
        done: false,
      );
      return [
        Item.fresh(single),
        original.copyWith(exceptions: [...original.exceptions, dateKey(d)]),
      ];
    case RepeatEdit.following:
      bool from(String k) => k.compareTo(dateKey(d)) >= 0;
      final next = edited.copyWith(
        start: occurrenceStart,
        doneDates: [...original.doneDates.where(from)],
        exceptions: [...original.exceptions.where(from)],
        checksByDate: {for (final e in original.checksByDate.entries) if (from(e.key)) e.key: e.value},
      );
      return [
        Item.fresh(next),
        original.copyWith(repeatUntil: DateTime(d.year, d.month, d.day - 1)),
      ];
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

/// 같은 내용의 새 항목(복제). 완료/반복 기록은 비우고 제목 뒤에 "(복사)"를 붙인다.
Item copyOfItem(Item i) => Item.fresh(i.copyWith(
      title: '${i.title} (복사)',
      done: false,
      doneDates: const [],
      exceptions: const [],
      checksByDate: const {},
      checklist: allChecked(i.checklist, false),
    ));

/// D-day 문구: 오늘이면 "D-day", 앞이면 "D-3", 지났으면 "D+2". [day]는 표시 중인 날짜(반복이면 그 회차).
String ddayLabel(DateTime day, DateTime today) {
  final n = dateOnly(day).difference(dateOnly(today)).inDays;
  return n == 0 ? 'D-day' : n > 0 ? 'D-$n' : 'D+${-n}';
}

/// 매년 반복(양력/음력) 일정의 "N주년" 문구. 첫 해이거나 매년 반복이 아니면 null.
String? anniversaryLabel(Item i, DateTime day) {
  final r = i.effectiveRule;
  final base = i.annivYear;
  if (base == null || r == null || r.freq != Freq.yearly || r.interval != 1) return null;
  int? n;
  if (r.lunar) {
    final b = solarToLunar(day);
    if (b == null) return null;
    n = b.year - base;
  } else {
    n = day.year - base;
  }
  return n >= 1 ? '$n주년' : null;
}

/// 체크리스트 한 줄
class CheckEntry {
  final String text;
  final bool done;
  const CheckEntry(this.text, {this.done = false});

  CheckEntry copyWith({String? text, bool? done}) => CheckEntry(text ?? this.text, done: done ?? this.done);

  Map<String, dynamic> toMap() => {'t': text, 'd': done};
  factory CheckEntry.fromMap(Map<String, dynamic> m) => CheckEntry('${m['t'] ?? ''}', done: m['d'] == true);

  @override
  bool operator ==(Object other) => other is CheckEntry && other.text == text && other.done == done;
  @override
  int get hashCode => Object.hash(text, done);
}

/// 모든 체크를 켠 / 끈 체크리스트
List<CheckEntry> allChecked(List<CheckEntry> l, bool done) => [for (final c in l) c.copyWith(done: done)];
