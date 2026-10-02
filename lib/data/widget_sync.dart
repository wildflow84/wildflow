import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../models/item.dart';

/// 안드로이드 홈화면 위젯에 오늘 일정/할 일을 밀어 넣는다.
/// 네이티브 쪽은 android/.../OurDayWidget.kt 가 SharedPreferences에서 읽는다.
class WidgetSync {
  static const _provider = 'OurDayWidget';

  static Future<void> push(List<Item> visible, String myUid) async {
    if (kIsWeb) return;
    final today = dateOnly(DateTime.now());
    final todays = visible.where((i) => occursOn(i, today)).toList()
      ..sort((a, b) {
        if (a.type != b.type) return a.type == ItemType.event ? -1 : 1;
        return a.start.compareTo(b.start);
      });
    final lines = todays.map((i) {
      if (i.type == ItemType.todo) {
        return '${isDoneOn(i, today) ? '☑' : '☐'} ${i.title}';
      }
      return '• ${i.title}';
    }).toList();
    try {
      await HomeWidget.saveWidgetData<String>(
          'title', DateFormat('M월 d일 (E)', 'ko').format(today));
      await HomeWidget.saveWidgetData<String>(
          'body', lines.isEmpty ? '오늘은 일정이 없어' : lines.take(8).join('\n'));
      await HomeWidget.updateWidget(androidName: _provider);
    } catch (_) {
      // 위젯 갱신 실패는 앱 동작에 영향 없음
    }
  }
}
