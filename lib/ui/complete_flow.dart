import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/item.dart';
import 'checklist.dart';

/// 할 일 완료 체크/해제: 남은 체크리스트가 있으면 확인한다.
/// 목록의 체크박스와 편집 화면의 "완료" 버튼이 같이 쓴다. 취소하면 false를 돌려준다.
Future<bool> toggleDoneWithPrompts(BuildContext context, Store s, Item item, DateTime day) async {
  final done = isDoneOn(item, day);
  var checkAll = false;
  if (!done) {
    final c = await confirmIncompleteChecklist(context, item, day);
    if (c == CompleteChoice.cancel) return false;
    checkAll = c == CompleteChoice.checkAll;
  }
  await s.toggleDone(item, day, checkAll: checkAll);
  return true;
}
