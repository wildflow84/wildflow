import 'package:cloud_firestore/cloud_firestore.dart';

enum ItemType { event, todo }

enum Visibility { shared, private }

enum Repeat { none, daily, weekly, monthly, yearly }

/// 일정(event)과 할 일(todo)을 한 컬렉션에서 다룬다.
class Item {
  final String id;
  final ItemType type;
  final String title;
  final String note;
  final DateTime start; // 날짜만 쓰는 경우 00:00
  final DateTime? end; // 멀티데이 일정의 마지막 날 (포함)
  final bool allDay;
  final bool done; // todo 전용 (반복 항목은 doneDates 사용)
  final List<String> doneDates; // 반복 todo의 완료 처리된 날짜 yyyy-MM-dd
  final String category;
  final Visibility visibility;
  final String ownerUid;
  final Repeat repeat;

  const Item({
    required this.id,
    required this.type,
    required this.title,
    required this.start,
    required this.ownerUid,
    this.note = '',
    this.end,
    this.allDay = true,
    this.done = false,
    this.doneDates = const [],
    this.category = 'default',
    this.visibility = Visibility.shared,
    this.repeat = Repeat.none,
  });

  Item copyWith({
    ItemType? type,
    String? title,
    String? note,
    DateTime? start,
    DateTime? end,
    bool clearEnd = false,
    bool? allDay,
    bool? done,
    List<String>? doneDates,
    String? category,
    Visibility? visibility,
    Repeat? repeat,
  }) =>
      Item(
        id: id,
        ownerUid: ownerUid,
        type: type ?? this.type,
        title: title ?? this.title,
        note: note ?? this.note,
        start: start ?? this.start,
        end: clearEnd ? null : (end ?? this.end),
        allDay: allDay ?? this.allDay,
        done: done ?? this.done,
        doneDates: doneDates ?? this.doneDates,
        category: category ?? this.category,
        visibility: visibility ?? this.visibility,
        repeat: repeat ?? this.repeat,
      );

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'title': title,
        'note': note,
        'start': Timestamp.fromDate(start),
        'end': end == null ? null : Timestamp.fromDate(end!),
        'allDay': allDay,
        'done': done,
        'doneDates': doneDates,
        'category': category,
        'visibility': visibility.name,
        'ownerUid': ownerUid,
        'repeat': repeat.name,
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
      start: (m['start'] as Timestamp).toDate(),
      end: (m['end'] as Timestamp?)?.toDate(),
      allDay: m['allDay'] ?? true,
      done: m['done'] ?? false,
      doneDates: List<String>.from(m['doneDates'] ?? const []),
      category: m['category'] ?? 'default',
      visibility: byName(Visibility.values, m['visibility'], Visibility.shared),
      ownerUid: m['ownerUid'] ?? '',
      repeat: byName(Repeat.values, m['repeat'], Repeat.none),
    );
  }
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
