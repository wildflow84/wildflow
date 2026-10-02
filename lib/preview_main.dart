// Firebase 없이 샘플 데이터로 화면만 띄우는 미리보기.
//   flutter run -d chrome -t lib/preview_main.dart
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'data/repository.dart';
import 'data/store.dart';
import 'main.dart';
import 'models/item.dart' as m;
import 'models/item.dart' show Item, ItemType, Repeat;
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  Item ev(String t, DateTime s, {DateTime? e, String c = 'default', Repeat r = Repeat.none, String owner = 'me', m.Visibility v = m.Visibility.shared}) =>
      Item(id: t + s.toString(), type: ItemType.event, title: t, start: s, end: e, category: c, repeat: r, ownerUid: owner, visibility: v);
  Item todo(String t, DateTime s, {String c = 'default', Repeat r = Repeat.none, String owner = 'me', bool done = false, m.Visibility v = m.Visibility.shared}) =>
      Item(id: t + s.toString(), type: ItemType.todo, title: t, start: s, category: c, repeat: r, ownerUid: owner, done: done, visibility: v);
  final items = [
    ev('오키나와 여행', DateTime(2026, 10, 14), e: DateTime(2026, 10, 17), c: 'travel'),
    ev('Arsenal vs Leeds', DateTime(2026, 10, 10), c: 'family'),
    ev('Arsenal vs Everton', DateTime(2026, 10, 24), c: 'family'),
    ev('정기점검', DateTime(2026, 10, 7), c: 'work'),
    ev('정기점검', DateTime(2026, 10, 21), c: 'work'),
    ev('민아 발주', DateTime(2026, 10, 9), c: 'family', owner: 'mina'),
    ev('대희 축구 교실', DateTime(2026, 10, 27), c: 'kid'),
    todo('로또 구매', DateTime(2026, 9, 28), c: 'money', r: Repeat.weekly),
    todo('청소연구소', DateTime(2026, 9, 28), r: Repeat.weekly, owner: 'mina'),
    todo('퇴직연금 매수', DateTime(2026, 9, 29), c: 'money', r: Repeat.monthly),
    todo('연금복권 구매', DateTime(2026, 10, 1), c: 'money', r: Repeat.weekly),
    todo('면도기 청소', DateTime(2026, 10, 2), done: true),
    todo('아침 약', DateTime(2026, 10, 2), r: Repeat.daily, v: m.Visibility.private),
    todo('저녁 약', DateTime(2026, 10, 2), r: Repeat.daily, v: m.Visibility.private),
    todo('대희 증여세', DateTime(2026, 10, 30), c: 'kid'),
  ];
  runApp(ChangeNotifierProvider(
    create: (_) => Store.preview(Repository(),
        uid: 'me', names: {'me': '대희 아빠', 'mina': '민아'}, items: items),
    child: const OurDayApp(home: HomeScreen()),
  ));
}
