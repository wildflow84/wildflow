import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/holidays.dart';
import '../models/item.dart' as m;
import '../models/item.dart' show Item, ItemType, Repeat, dateOnly, isDoneOn;
import 'categories.dart';
import 'edit_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = dateOnly(DateTime.now());
  int _tab = 0;

  void _shift(int d) =>
      setState(() => _month = DateTime(_month.year, _month.month + d));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final wide = MediaQuery.sizeOf(context).width > 900;

    final calendar = _MonthGrid(
      month: _month,
      selected: _selected,
      onSelect: (d) => setState(() {
        _selected = d;
        if (!wide) _openDaySheet(context, d);
      }),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_tab == 0 ? DateFormat('M월', 'ko').format(_month) : '할 일'),
        actions: [
          if (_tab == 0) ...[
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
            TextButton(
                onPressed: () => setState(() {
                      _month = DateTime(DateTime.now().year, DateTime.now().month);
                      _selected = dateOnly(DateTime.now());
                    }),
                child: const Text('오늘')),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
          ],
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'out') s.repo.signOut();
              if (v == 'code') {
                Clipboard.setData(ClipboardData(text: s.spaceId!));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('초대 코드를 복사했어')));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'code', child: Text('초대 코드 복사')),
              PopupMenuItem(value: 'out', child: Text('로그아웃')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(),
          Expanded(
            child: _tab == 1
                ? const _TodoTab()
                : wide
                    ? Row(children: [
                        Expanded(flex: 3, child: calendar),
                        SizedBox(width: 340, child: _DayList(day: _selected)),
                      ])
                    : calendar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showEditSheet(context,
            day: _selected, type: _tab == 1 ? ItemType.todo : ItemType.event),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: '캘린더'),
          NavigationDestination(icon: Icon(Icons.checklist), label: '할 일'),
        ],
      ),
    );
  }

  void _openDaySheet(BuildContext context, DateTime d) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (_, ctrl) => _DayList(day: d, controller: ctrl),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final me = s.user!.uid;
    final partner = s.names.entries.where((e) => e.key != me).map((e) => e.value).firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        FilterChip(
          label: const Text('나'),
          selected: s.filters.contains('mine'),
          onSelected: (_) => s.toggleFilter('mine'),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: Text(partner ?? '상대'),
          selected: s.filters.contains('partner'),
          onSelected: (_) => s.toggleFilter('partner'),
        ),
      ]),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month, selected;
  final ValueChanged<DateTime> onSelect;
  const _MonthGrid(
      {required this.month, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final first = DateTime(month.year, month.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday % 7)); // 일요일 시작
    final weeks = ((first.weekday % 7 + DateTime(month.year, month.month + 1, 0).day) / 7).ceil();
    const dow = ['일', '월', '화', '수', '목', '금', '토'];
    final today = dateOnly(DateTime.now());

    return Column(children: [
      Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(dow[i],
                      style: TextStyle(
                          color: i == 0
                              ? Colors.redAccent
                              : i == 6
                                  ? Colors.lightBlueAccent
                                  : null)),
                ),
              ),
            ),
        ],
      ),
      Expanded(
        child: Column(children: [
          for (var w = 0; w < weeks; w++)
            Expanded(
              child: Row(children: [
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: _DayCell(
                      day: gridStart.add(Duration(days: w * 7 + d)),
                      inMonth: gridStart.add(Duration(days: w * 7 + d)).month == month.month,
                      isToday: gridStart.add(Duration(days: w * 7 + d)) == today,
                      isSelected: gridStart.add(Duration(days: w * 7 + d)) == selected,
                      items: s.itemsOn(gridStart.add(Duration(days: w * 7 + d))),
                      onTap: onSelect,
                    ),
                  ),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth, isToday, isSelected;
  final List<Item> items;
  final ValueChanged<DateTime> onTap;
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final holiday = holidayName(day);
    final holidayColor = (day.weekday == DateTime.sunday || holiday != null)
        ? Colors.redAccent
        : null;
    const maxChips = 3;
    return InkWell(
      onTap: () => onTap(day),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
              color: isSelected ? Colors.lightBlueAccent : Colors.white12,
              width: isSelected ? 1.5 : 0.5),
        ),
        padding: const EdgeInsets.all(2),
        child: Opacity(
          opacity: inMonth ? 1 : 0.4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: isToday
                      ? const BoxDecoration(
                          color: Color(0xFF3B6FF5),
                          borderRadius: BorderRadius.all(Radius.circular(8)))
                      : null,
                  child: Text('${day.day}',
                      style: TextStyle(fontSize: 11, color: holidayColor)),
                ),
              ]),
              if (holiday != null) _Chip(text: holiday, color: const Color(0xFF3FA796)),
              for (final i in items.take(maxChips - (holiday != null ? 1 : 0)))
                _Chip(
                  text: i.title,
                  color: categoryOf(i.category).color,
                  isTodo: i.type == ItemType.todo,
                  done: isDoneOn(i, day),
                  isPrivate: i.visibility == m.Visibility.private,
                ),
              if (items.length > maxChips - (holiday != null ? 1 : 0))
                const Text('•••', style: TextStyle(fontSize: 9, color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final bool isTodo, done, isPrivate;
  const _Chip({
    required this.text,
    required this.color,
    this.isTodo = false,
    this.done = false,
    this.isPrivate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: isTodo ? color.withValues(alpha: 0.45) : color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(children: [
        if (isTodo) Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 9),
        if (isPrivate) const Icon(Icons.lock, size: 8),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                  fontSize: 9,
                  decoration: done ? TextDecoration.lineThrough : null)),
        ),
      ]),
    );
  }
}

/// 선택한 날의 항목 목록 (체크, 수정, 삭제).
class _DayList extends StatelessWidget {
  final DateTime day;
  final ScrollController? controller;
  const _DayList({required this.day, this.controller});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final items = s.itemsOn(day);
    final holiday = holidayName(day);
    return Column(children: [
      ListTile(
        title: Text(DateFormat('M월 d일 (E)', 'ko').format(day)),
        subtitle: holiday == null ? null : Text(holiday),
        trailing: IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => showEditSheet(context, day: day)),
      ),
      Expanded(
        child: items.isEmpty
            ? const Center(child: Text('비어 있어'))
            : ListView(controller: controller, children: [
                for (final i in items) _ItemTile(item: i, day: day),
              ]),
      ),
    ]);
  }
}

class _ItemTile extends StatelessWidget {
  final Item item;
  final DateTime day;
  const _ItemTile({required this.item, required this.day});

  @override
  Widget build(BuildContext context) {
    final s = context.read<Store>();
    final done = isDoneOn(item, day);
    final mine = item.ownerUid == s.user!.uid;
    final cat = categoryOf(item.category);
    return ListTile(
      leading: item.type == ItemType.todo
          ? Checkbox(
              value: done,
              onChanged: mine ? (_) => s.toggleDone(item, day) : null)
          : Icon(Icons.circle, color: cat.color, size: 14),
      title: Text(item.title,
          style: TextStyle(
              decoration: done ? TextDecoration.lineThrough : null)),
      subtitle: Text([
        if (!mine) s.ownerName(item),
        if (item.visibility == m.Visibility.private) '프라이빗',
        if (item.repeat != Repeat.none) '반복',
        if (item.note.isNotEmpty) item.note,
      ].join(' · ')),
      onTap: mine ? () => showEditSheet(context, item: item, day: day) : null,
    );
  }
}

/// 날짜 구분 없이 오늘 기준으로 할 일을 모아 본다.
class _TodoTab extends StatelessWidget {
  const _TodoTab();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final today = dateOnly(DateTime.now());
    final todos = s.visibleItems.where((i) => i.type == ItemType.todo).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final open = todos.where((i) {
      final d = i.repeat == Repeat.none ? i.start : today;
      return !isDoneOn(i, d) && (i.repeat != Repeat.none ? m.occursOn(i, today) : true);
    }).toList();
    final overdue = open.where((i) => i.repeat == Repeat.none && i.start.isBefore(today)).toList();
    final upcoming = open.where((i) => !overdue.contains(i)).toList();

    Widget section(String title, List<Item> list) => list.isEmpty
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
            for (final i in list)
              _ItemTile(
                  item: i,
                  day: i.repeat == Repeat.none ? dateOnly(i.start) : today),
          ]);

    return ListView(children: [
      section('지난 할 일', overdue),
      section('앞으로', upcoming),
      if (open.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('할 일 끝! 순대 산책 ㄱㄱ'))),
    ]);
  }
}
