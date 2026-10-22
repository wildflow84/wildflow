import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/item.dart';
import 'package:ourday/models/lunar.dart';
import 'package:ourday/models/recurrence.dart';

/// functions/golden/golden.json 은 이 앱의 반복 계산이 만든 기준값이다 (서버 함수의 JS 이식이 같은 값을 내는지 비교하는 데도 쓴다).
/// 계산 방식을 바꿔도(예: 속도를 위해 정수 일수로) 결과가 그대로인지 지킨다.
void main() {
  final golden = jsonDecode(File('functions/golden/golden.json').readAsStringSync()) as Map<String, dynamic>;

  DateTime parse(String s) {
    final p = s.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  test('반복 규칙 25가지의 5년치 발생일이 기준값과 같다', () {
    for (final c in (golden['cases'] as List).cast<Map<String, dynamic>>()) {
      final rule = c['rule'] == null ? null : Recurrence.fromMap(Map<String, dynamic>.from(c['rule'] as Map));
      final item = Item(
        id: 'x',
        type: ItemType.event,
        title: '${c['name']}',
        start: parse(c['start'] as String),
        end: c['end'] == null ? null : parse(c['end'] as String),
        ownerUid: 'u',
        rule: rule,
        repeat: Repeat.values.firstWhere((r) => r.name == c['repeat']),
        repeatUntil: c['until'] == null ? null : parse(c['until'] as String),
        exceptions: List<String>.from(c['exceptions'] as List),
      );
      final got = <String>[];
      for (var d = DateTime(2023, 12, 1); d.isBefore(DateTime(2029, 1, 1)); d = DateTime(d.year, d.month, d.day + 1)) {
        if (occursOn(item, d)) got.add(dateKey(d));
      }
      expect(got, List<String>.from(c['days'] as List), reason: '${c['name']}');
    }
  });

  test('음력 변환 표본이 기준값과 같다', () {
    for (final r in (golden['lunar'] as List)) {
      final l = solarToLunar(parse(r[0] as String));
      if (r[1] == null) {
        expect(l, isNull);
      } else {
        expect([l!.year, l.month, l.day, l.leap], [r[1], r[2], r[3], r[4]], reason: '${r[0]}');
      }
    }
  });
}
