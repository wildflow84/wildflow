import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/store.dart';
import '../models/item.dart';
import 'checklist.dart';
import 'snack.dart';

/// 할 일 완료 체크/해제: 남은 체크리스트가 있으면 확인하고, 이동형 반복은 "다음 날짜로 이동" 안내와 되돌리기를 보여 준다.
/// 목록의 체크박스와 편집 화면의 "완료" 버튼이 같이 쓴다. 취소하면 false를 돌려준다.
Future<bool> toggleDoneWithPrompts(BuildContext context, Store s, Item item, DateTime day) async {
  final messenger = ScaffoldMessenger.of(context);
  final done = isDoneOn(item, day);
  var checkAll = false;
  if (!done) {
    final c = await confirmIncompleteChecklist(context, item, day);
    if (c == CompleteChoice.cancel) return false;
    checkAll = c == CompleteChoice.checkAll;
  }
  final prev = await s.toggleDone(item, day, checkAll: checkAll);
  if (prev != null) {
    final next = DateFormat('M월 d일 (E)', 'ko').format(nextRollDate(prev, DateTime.now()));
    showTimedSnack(
      messenger,
      '"${item.title}" 완료 → $next(으)로 이동',
      actionLabel: '되돌리기',
      onAction: () => s.undoRoll(prev),
    );
  }
  return true;
}
