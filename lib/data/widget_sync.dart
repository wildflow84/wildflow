import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../models/item.dart';

/// 안드로이드 홈화면 위젯에 일정/할 일을 밀어 넣는다.
/// 네이티브 쪽은 android/.../OurDayWidget.kt 가 SharedPreferences에서 읽는다.
///  - body: 목록형 위젯에 보일 앞으로 며칠치 일정/할 일 (글자)
///  - eventDays: 달력형 위젯에 표시할 "일정이 있는 날" (yyyyMMdd를 쉼표로)
class WidgetSync {
  static const _provider = 'OurDayWidget';
  static const _agendaDays = 7;
  static const _maxLines = 10;

  static String _line(Item i, DateTime day) {
    final t = timeLabel(i);
    final title = t == null ? i.title : '$t ${i.title}';
    if (i.type == ItemType.todo) return '${isDoneOn(i, day) ? '☑' : '☐'} $title';
    return '• $title';
  }

  static List<Item> _on(List<Item> visible, DateTime day) => visible.where((i) => occursOn(i, day)).toList()
    ..sort((a, b) {
      if (a.type != b.type) return a.type == ItemType.event ? -1 : 1;
      return a.start.compareTo(b.start);
    });

  /// 목록형 위젯 글자: 오늘 + 앞으로 며칠 (날짜 머리글 포함, 최대 [_maxLines]줄)
  static String agendaText(List<Item> visible, DateTime today) {
    final lines = <String>[];
    final df = DateFormat('M/d (E)', 'ko');
    final todays = _on(visible, today);
    if (todays.isEmpty) {
      lines.add('오늘은 일정이 없어');
    } else {
      for (final i in todays) {
        lines.add(_line(i, today));
      }
    }
    for (var d = 1; d <= _agendaDays && lines.length < _maxLines; d++) {
      final day = DateTime(today.year, today.month, today.day + d);
      final items = _on(visible, day);
      if (items.isEmpty) continue;
      lines.add(df.format(day));
      for (final i in items) {
        lines.add(_line(i, day));
      }
    }
    return lines.take(_maxLines).join('\n');
  }

  /// 달력형 위젯용: 지난달 1일부터 다음 달 말일까지 일정/할 일이 있는 날
  static String eventDays(List<Item> visible, DateTime today) {
    final start = DateTime(today.year, today.month - 1, 1);
    final end = DateTime(today.year, today.month + 2, 0);
    final f = DateFormat('yyyyMMdd');
    final out = <String>[];
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      if (visible.any((i) => occursOn(i, d))) out.add(f.format(d));
    }
    return out.join(',');
  }

  static Future<void> push(List<Item> visible, String myUid) async {
    if (kIsWeb) return;
    final today = dateOnly(DateTime.now());
    try {
      await HomeWidget.saveWidgetData<String>('title', DateFormat('M월 d일 (E)', 'ko').format(today));
      await HomeWidget.saveWidgetData<String>('body', agendaText(visible, today));
      await HomeWidget.saveWidgetData<String>('eventDays', eventDays(visible, today));
      await HomeWidget.updateWidget(androidName: _provider);
    } catch (_) {
      // 위젯 갱신 실패는 앱 동작에 영향 없음
    }
  }
}
