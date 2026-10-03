import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/data/location_report.dart';
import 'package:ourday/models/item.dart';
import 'package:ourday/models/recurrence.dart';

void main() {
  final base = Item(
      id: 'a', type: ItemType.event, title: '미용실', start: DateTime(2026, 10, 3, 15), ownerUid: 'me',
      lat: 37.2, lng: 127.0, departAlert: true, allDay: false);

  test('출발 알림은 좌표가 있는 시각 일정(반복 아님)에서만 켜짐', () {
    expect(base.departFrom, DateTime(2026, 10, 3, 15));
    expect(base.copyWith(departAlert: false).departFrom, isNull);
    expect(base.copyWith(allDay: true).departFrom, isNull, reason: '종일 일정');
    expect(base.copyWith(rule: const Recurrence(freq: Freq.weekly)).departFrom, isNull);
    expect(base.copyWith(clearCoords: true).departFrom, isNull);
    expect(base.copyWith(type: ItemType.todo).departFrom, isNull);
  });

  test('복제해도 출발 알림 설정이 따라감', () {
    expect(copyOfItem(base).departAlert, isTrue);
  });

  test('위치 전달은 8시간 안에 시작하는 출발 알림 일정이 있을 때만', () {
    final now = DateTime(2026, 10, 3, 9);
    expect(LocationReporter.hasUpcomingDepart([base], now), isTrue); // 6시간 뒤
    expect(LocationReporter.hasUpcomingDepart([base], DateTime(2026, 10, 3, 6)), isFalse); // 9시간 뒤
    expect(LocationReporter.hasUpcomingDepart([base], DateTime(2026, 10, 3, 16)), isFalse); // 이미 지남
    expect(LocationReporter.hasUpcomingDepart([base.copyWith(departAlert: false)], now), isFalse);
  });
}
