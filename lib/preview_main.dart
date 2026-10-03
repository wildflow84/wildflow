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
import 'ui/category_dialog.dart';
import 'ui/category_manager.dart';
import 'ui/color_picker.dart';
import 'ui/date_picker.dart';
import 'ui/recurrence_editor.dart';
import 'models/recurrence.dart';
import 'ui/login_screen.dart';
import 'ui/space_screen.dart';
import 'ui/edit_sheet.dart';
import 'ui/home_screen.dart';
import 'models/category.dart';
import 'ui/settings_screen.dart';
import 'ui/time_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  Item ev(String t, DateTime s, {DateTime? e, String c = 'default', Repeat r = Repeat.none, String owner = 'me', m.Visibility v = m.Visibility.shared, bool timed = false}) =>
      Item(id: t + s.toString(), type: ItemType.event, title: t, start: s, end: e, categories: [c], repeat: r, ownerUid: owner, visibility: v, allDay: !timed, location: timed ? '판교 사옥' : '');
  Item todo(String t, DateTime s, {String c = 'default', Repeat r = Repeat.none, String owner = 'me', bool done = false, m.Visibility v = m.Visibility.shared, bool roll = false}) =>
      Item(id: t + s.toString(), type: ItemType.todo, title: t, start: s, categories: [c], repeat: r, ownerUid: owner, done: done, visibility: v, rollEvery: roll ? 1 : 0);
  final items = [
    ev('오키나와 여행', DateTime(2026, 10, 14), e: DateTime(2026, 10, 17), c: 'travel'),
    ev('Arsenal vs Leeds', DateTime(2026, 10, 10), c: 'family'),
    ev('출장 (판교→부산)', DateTime(2026, 10, 10), e: DateTime(2026, 10, 14), c: 'work'),
    ev('아이 방학 캠프', DateTime(2026, 10, 12), e: DateTime(2026, 10, 15), c: 'kid', owner: 'mina'),
    ev('Arsenal vs Everton', DateTime(2026, 10, 24), c: 'family'),
    ev('정기점검', DateTime(2026, 10, 7, 15, 0), e: DateTime(2026, 10, 7, 16, 30), c: 'work', timed: true),
    ev('정기점검', DateTime(2026, 10, 21), c: 'work'),
    ev('파트너 회식', DateTime(2026, 10, 9), c: 'family', owner: 'mina'),
    ev('아이 축구 교실', DateTime(2026, 10, 27), c: 'kid'),
    todo('복권 구매', DateTime(2026, 9, 28), c: 'money', r: Repeat.weekly),
    todo('청소연구소', DateTime(2026, 9, 28), r: Repeat.weekly, owner: 'mina'),
    todo('펀드 적립', DateTime(2026, 9, 29), c: 'money', r: Repeat.monthly),
    todo('정기 적금 확인', DateTime(2026, 10, 1), c: 'money', r: Repeat.weekly),
    todo('면도기 청소', DateTime(2026, 10, 2), done: true),
    m.Item(id: 'rr', type: ItemType.todo, title: '목요일 점검', start: DateTime(2026, 10, 8), ownerUid: 'me', categories: const ['work'], rollRule: const Recurrence(freq: Freq.weekly, weekdays: [4])),
    todo('아침 약', DateTime(2026, 10, 2), c: 'family', v: m.Visibility.private, roll: true),
    todo('저녁 약', DateTime(2026, 10, 2), c: 'family', v: m.Visibility.private, roll: true),
    todo('아이 예방접종', DateTime(2026, 10, 30), c: 'kid'),
  ];
  runApp(ChangeNotifierProvider(
    create: (_) => Store.preview(Repository(),
        uid: 'me', names: {'me': '나', 'mina': '파트너'}, items: items),
    child: OurDayApp(home: _start()),
  ));
}

/// ?page=settings | edit 로 설정 화면/등록 시트를 바로 확인
Widget _start() {
  switch (Uri.base.queryParameters['page']) {
    case 'settings':
      return const SettingsScreen();
    case 'edit':
      return const _OpenEdit();
    case 'edit-timed':
      return const _OpenEdit(timed: true);
    case 'time':
      return const _OpenTime();
    case 'jump':
      return _Opener((c) => pickDate(c, initial: DateTime(2026, 10, 8), title: '이동할 날짜'));
    case 'color':
      return _Opener((c) => pickColor(c, initial: 0xFF6C74D8));
    case 'catdialog':
      return _Opener((c) => showCategoryDialog(c, edit: defaultCategories[2]));
    case 'holiday':
      return _Opener((c) => addCustomDayDialog(c, DateTime(2026, 10, 5)));
    case 'login':
      return const LoginScreen();
    case 'space':
      return const SpaceScreen();
    case 'recur':
      return _Opener((c) => showRecurrenceEditor(c,
          start: DateTime(2026, 10, 30),
          initial: const Recurrence(freq: Freq.monthly, monthDays: [1, 15, -1], clampMonthEnd: true)));
    case 'recur-week':
      return _Opener((c) => showRecurrenceEditor(c, start: DateTime(2026, 10, 7)));
    case 'recur-nth':
      return _Opener((c) => showRecurrenceEditor(c,
          start: DateTime(2026, 10, 13),
          initial: const Recurrence(freq: Freq.monthly, nth: 2, nthWeekday: 2, count: 12)));
    case 'edit-weekly':
      return _Opener((c) => showEditSheet(c,
          day: DateTime(2026, 10, 14),
          item: m.Item(
              id: 'w', type: ItemType.event, title: '정기점검', start: DateTime(2026, 10, 7, 15, 0),
              end: DateTime(2026, 10, 7, 16, 30), allDay: false, ownerUid: 'me',
              categories: const ['work', 'kid'], repeat: Repeat.weekly, location: '판교 사옥')));
    case 'edit-roll-rule':
      return _Opener((c) => showEditSheet(c,
          day: DateTime(2026, 10, 8),
          item: m.Item(
              id: 'rr', type: ItemType.todo, title: '목요일 점검', start: DateTime(2026, 10, 8),
              ownerUid: 'me', categories: const ['work'],
              rollRule: const Recurrence(freq: Freq.weekly, weekdays: [4]))));
    case 'edit-roll':
      return const _OpenEdit(roll: true);
    case 'categories':
      return const CategoryManagerScreen();
  }
  return const HomeScreen();
}

class _OpenEdit extends StatefulWidget {
  final bool roll, timed;
  const _OpenEdit({this.roll = false, this.timed = false});
  @override
  State<_OpenEdit> createState() => _OpenEditState();
}

class _OpenEditState extends State<_OpenEdit> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final item = widget.roll
          ? m.Item(
              id: 'r', type: ItemType.todo, title: '아침 약', start: DateTime(2026, 10, 2), ownerUid: 'me',
              categories: const ['family', 'kid'], rollEvery: 1, visibility: m.Visibility.private)
          : widget.timed
              ? m.Item(
                  id: 't', type: ItemType.event, title: '정기점검', start: DateTime(2026, 10, 7, 15, 0),
                  end: DateTime(2026, 10, 7, 16, 30), allDay: false, location: '판교 사옥', ownerUid: 'me',
                  categories: const ['work'])
              : null;
      showEditSheet(context, day: DateTime(2026, 10, 14), item: item);
    });
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}

class _OpenTime extends StatefulWidget {
  const _OpenTime();
  @override
  State<_OpenTime> createState() => _OpenTimeState();
}

class _OpenTimeState extends State<_OpenTime> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => pickTimeDigital(context, initial: const TimeOfDay(hour: 9, minute: 0)));
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}

/// 점검용: 홈 위에 원하는 대화상자/시트를 첫 프레임 뒤에 연다.
class _Opener extends StatefulWidget {
  final void Function(BuildContext) open;
  const _Opener(this.open);
  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.open(context));
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
