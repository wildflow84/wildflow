import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../models/kr_calendar.dart';
import '../models/lunar.dart';
import '../models/map_links.dart';
import '../models/item.dart' as m;
import '../models/item.dart' show Item, ItemType, Repeat, dateOnly, isDoneOn, isOverdue, moveItemByDays, nextRollDate, rollLabel, timeLabel, chipTimeLabel;
import 'category_manager.dart';
import 'settings_screen.dart';
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

  /// 원하는 날짜로 바로 이동 (1901~2200)
  Future<void> _jump(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(1901, 1, 1),
      lastDate: DateTime(2200, 12, 31),
      helpText: '이동할 날짜',
    );
    if (d == null) return;
    setState(() {
      _selected = dateOnly(d);
      _month = DateTime(d.year, d.month);
    });
  }

  /// 예: "병오년 8월 – 9월"
  String _lunarRange(DateTime month) {
    final a = solarToLunar(DateTime(month.year, month.month, 1));
    final b = solarToLunar(DateTime(month.year, month.month + 1, 0));
    if (a == null || b == null) return '';
    final first = '${ganjiYear(a.year)}년 ${a.monthLabel}';
    if (a.year == b.year && a.month == b.month && a.leap == b.leap) return first;
    if (a.year == b.year) return '$first – ${b.monthLabel}';
    return '$first – ${ganjiYear(b.year)}년 ${b.monthLabel}';
  }

  void _shift(int d) =>
      setState(() => _month = DateTime(_month.year, _month.month + d));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final wide = MediaQuery.sizeOf(context).width > 900;

    final calendar = _MonthGrid(
      month: _month,
      selected: _selected,
      onBlankTap: (d) {
        setState(() => _selected = d);
        _quickAdd(context, d, wide);
      },
      onItemTap: (item, d) => showEditSheet(context, item: item, day: d),
      onMove: _moveItem,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: _tab == 0
            ? Row(children: [
                InkWell(
                  onTap: () => _jump(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${_month.year}년 ${_month.month}월',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(_lunarRange(_month),
                            style: const TextStyle(fontSize: 12, color: Colors.white60)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const _SharedToggle(),
              ])
            : const Text('할 일'),
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
              if (v == 'settings') {
                Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              }
              if (v == 'categories') {
                Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const CategoryManagerScreen()));
              }
              if (v == 'out') s.repo.signOut();
              if (v == 'code') {
                Clipboard.setData(ClipboardData(text: s.spaceId!));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('초대 코드를 복사했어')));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'categories', child: Text('카테고리 관리')),
              PopupMenuItem(value: 'settings', child: Text('설정 (기본 공개 범위 등)')),
              PopupMenuItem(value: 'code', child: Text('초대 코드 복사')),
              PopupMenuItem(value: 'out', child: Text('로그아웃')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
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

  /// 달력 빈 공간을 눌렀을 때: 바로 일정/할 일/휴일 추가
  void _quickAdd(BuildContext context, DateTime d, bool wide) {
    final s = context.read<Store>();
    final lunar = solarToLunar(d);
    final count = s.itemsOn(d).length;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(DateFormat('M월 d일 (E)', 'ko').format(d),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: lunar == null ? null : Text('음력 ${lunar.monthLabel} ${lunar.day}일'),
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('일정 추가'),
            onTap: () {
              Navigator.pop(ctx);
              showEditSheet(context, day: d, type: ItemType.event);
            },
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('할 일 추가'),
            onTap: () {
              Navigator.pop(ctx);
              showEditSheet(context, day: d, type: ItemType.todo);
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('휴일 / 기념일 추가'),
            onTap: () {
              Navigator.pop(ctx);
              addCustomDayDialog(context, d);
            },
          ),
          if (!wide)
            ListTile(
              leading: const Icon(Icons.list),
              title: Text(count == 0 ? '이 날 보기' : '이 날 목록 보기 ($count)'),
              onTap: () {
                Navigator.pop(ctx);
                _openDaySheet(context, d);
              },
            ),
        ]),
      ),
    );
  }

  /// 드래그로 다른 날로 이동 (시각/기간 유지). 되돌리기 제공.
  Future<void> _moveItem(Item item, DateTime from, DateTime to) async {
    final s = context.read<Store>();
    final messenger = ScaffoldMessenger.of(context);
    final delta = dayNumber(to) - dayNumber(from);
    if (delta == 0) return;
    await s.save(moveItemByDays(item, delta));
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('"${item.title}" → ${DateFormat('M월 d일 (E)', 'ko').format(to)}로 이동'),
      action: SnackBarAction(label: '되돌리기', onPressed: () => s.save(item)),
    ));
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

/// 내 항목은 항상 보이고, 상대가 올린 같이 보기 항목만 이 알약 버튼으로 켜고 끈다.
class _SharedToggle extends StatelessWidget {
  const _SharedToggle();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final on = s.showShared;
    final partner = s.names.entries.where((e) => e.key != s.uid).map((e) => e.value).firstOrNull;
    final accent = Theme.of(context).colorScheme.primary;
    final narrow = MediaQuery.sizeOf(context).width < 400;
    return Tooltip(
      message: '공유 캘린더 보기 ${on ? '켜짐' : '꺼짐'}${partner == null ? '' : ' · $partner의 같이 보기 항목'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => s.toggleFilter('partner'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 12, vertical: 6),
            decoration: BoxDecoration(
              color: on ? accent.withValues(alpha: 0.22) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? accent : Colors.white24),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(on ? Icons.people : Icons.people_outline,
                  size: 17, color: on ? accent : Colors.white54),
              if (!narrow) ...[
                const SizedBox(width: 6),
                Text('공유',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: on ? accent : Colors.white54)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month, selected;
  final ValueChanged<DateTime> onBlankTap;
  final void Function(Item item, DateTime day) onItemTap;
  final void Function(Item item, DateTime from, DateTime to) onMove;
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.onBlankTap,
    required this.onItemTap,
    required this.onMove,
  });

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
                      onTap: onBlankTap,
                      onTapItem: onItemTap,
                      onDropItem: onMove,
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
  final ValueChanged<DateTime> onTap; // 빈 공간 탭
  final void Function(Item item, DateTime day) onTapItem;
  final void Function(Item item, DateTime from, DateTime to) onDropItem;
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.items,
    required this.onTap,
    required this.onTapItem,
    required this.onDropItem,
  });

  /// 날짜 옆 음력 표기: 평일은 일, 초하루는 "월.1" (윤달은 앞에 윤)
  static String lunarText(DateTime d) {
    final l = solarToLunar(d);
    if (l == null) return '';
    return l.day == 1 ? '${l.leap ? '윤' : ''}${l.month}.1' : '${l.day}';
  }

  @override
  Widget build(BuildContext context) {
    final s0 = context.watch<Store>();
    final marks = s0.cal.marksOn(day);
    final isHoliday = marks.any((m) => m.isHoliday);
    final numColor = (day.weekday == DateTime.sunday || isHoliday)
        ? Colors.redAccent
        : day.weekday == DateTime.saturday
            ? Colors.lightBlueAccent
            : null;

    // 공휴일 → 내 일정/할 일 → 절기·기념일 순으로 채우고, 넘치면 +N
    final lines = <Widget>[];
    for (final m in marks.where((m) => m.isHoliday)) {
      lines.add(_Chip(text: m.name, color: const Color(0xFF3FA796)));
    }
    for (final i in items) {
      lines.add(_itemChip(context, s0, i));
    }
    for (final mk in marks.where((m) => !m.isHoliday)) {
      lines.add(_MarkText(
          text: mk.name,
          color: mk.kind == MarkKind.term ? const Color(0xFFE8A95B) : Colors.white54));
    }

    return DragTarget<_DragData>(
      onWillAcceptWithDetails: (d) => dayNumber(d.data.from) != dayNumber(day),
      onAcceptWithDetails: (d) => onDropItem(d.data.item, d.data.from, day),
      builder: (context, candidates, _) => InkWell(
      onTap: () => onTap(day),
      child: Container(
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? Colors.lightGreenAccent.withValues(alpha: 0.12) : null,
          border: Border.all(
              color: candidates.isNotEmpty
                  ? Colors.lightGreenAccent
                  : isSelected
                      ? Colors.lightBlueAccent
                      : Colors.white12,
              width: (isSelected || candidates.isNotEmpty) ? 1.5 : 0.5),
        ),
        padding: const EdgeInsets.all(2),
        child: Opacity(
          opacity: inMonth ? 1 : 0.4,
          child: LayoutBuilder(builder: (context, c) {
            final room = ((c.maxHeight - 16) / 13).floor().clamp(0, 12);
            final overflow = lines.length > room;
            final shown = overflow ? room - 1 : lines.length;
            return Column(
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
                        style: TextStyle(fontSize: 11, color: numColor)),
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text('(${lunarText(day)})',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(fontSize: 9, color: Colors.white38)),
                  ),
                ]),
                ...lines.take(shown.clamp(0, lines.length)),
                if (overflow && room > 0)
                  Text('+${lines.length - shown}',
                      style: const TextStyle(fontSize: 9, color: Colors.white54)),
              ],
            );
          }),
        ),
      ),
    ));
  }

  /// 내 일정/할 일 칩: 탭하면 바로 편집, 길게 눌러 끌면 다른 날로 이동 (반복 항목은 이동 불가)
  Widget _itemChip(BuildContext context, Store s0, Item i) {
    final canEdit = i.ownerUid == s0.uid || i.visibility == m.Visibility.shared;
    final chip = _Chip(
      text: i.allDay ? i.title : '${chipTimeLabel(i)} ${i.title}',
      color: s0.colorOf(i),
      extraDots: [for (final c in s0.categoriesOf(i).skip(1)) c.color],
      isTodo: i.type == ItemType.todo,
      done: isDoneOn(i, day),
      isPrivate: i.visibility == m.Visibility.private,
      isRolling: i.isRolling,
    );
    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canEdit ? () => onTapItem(i, day) : () => onTap(day),
      child: chip,
    );
    if (!canEdit || i.repeat != Repeat.none) return tappable;
    return LongPressDraggable<_DragData>(
      data: _DragData(i, day),
      delay: const Duration(milliseconds: 180),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 130, child: Opacity(opacity: 0.9, child: chip)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: tappable,
    );
  }
}

class _DragData {
  final Item item;
  final DateTime from;
  _DragData(this.item, this.from);
}

class _MarkText extends StatelessWidget {
  final String text;
  final Color color;
  const _MarkText({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, top: 1),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(fontSize: 9, color: color)),
      );
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final bool isTodo, done, isPrivate;
  final List<Color> extraDots; // 두 번째 이후 카테고리 색
  final bool isRolling;
  const _Chip({
    required this.text,
    required this.color,
    this.isTodo = false,
    this.done = false,
    this.isPrivate = false,
    this.extraDots = const [],
    this.isRolling = false,
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
        if (isRolling) const Icon(Icons.autorenew, size: 9),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                  fontSize: 9,
                  decoration: done ? TextDecoration.lineThrough : null)),
        ),
        for (final c in extraDots)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
                color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 0.5)),
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
    final marks = s.cal.marksOn(day);
    final custom = s.customDaysOn(day);
    final lunar = solarToLunar(day);
    return Column(children: [
      ListTile(
        title: Text(DateFormat('y년 M월 d일 (E)', 'ko').format(day)),
        subtitle: lunar == null
            ? null
            : Text('음력 ${ganjiYear(lunar.year)}년 ${lunar.monthLabel} ${lunar.day}일'),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.add),
          onSelected: (v) {
            if (v == 'item') showEditSheet(context, day: day);
            if (v == 'day') addCustomDayDialog(context, day);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'item', child: Text('일정 / 할 일 추가')),
            PopupMenuItem(value: 'day', child: Text('휴일 / 기념일 추가 (임시공휴일 등)')),
          ],
        ),
      ),
      if (marks.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final m in marks)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(m.name, style: const TextStyle(fontSize: 12)),
                  backgroundColor: m.isHoliday
                      ? const Color(0xFF3FA796)
                      : m.kind == MarkKind.term
                          ? const Color(0xFF6B5A3A)
                          : Colors.white12,
                  deleteIcon: custom.any((c) => c.name == m.name)
                      ? const Icon(Icons.close, size: 14)
                      : null,
                  onDeleted: custom.any((c) => c.name == m.name)
                      ? () => s.deleteCustomDay(custom.firstWhere((c) => c.name == m.name))
                      : null,
                ),
            ]),
          ),
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
    final mine = item.ownerUid == s.uid;
    final canEdit = mine || item.visibility == m.Visibility.shared; // 같이 보기 항목은 같이 편집
    final itemColor = s.colorOf(item);
    return ListTile(
      leading: item.type == ItemType.todo
          ? Checkbox(
              value: done,
              onChanged: canEdit
                  ? (_) async {
                      final messenger = ScaffoldMessenger.of(context);
                      final prev = await s.toggleDone(item, day);
                      if (prev != null) {
                        final next = DateFormat('M월 d일 (E)', 'ko').format(nextRollDate(prev, DateTime.now()));
                        messenger.hideCurrentSnackBar();
                        messenger.showSnackBar(SnackBar(
                          content: Text('"${item.title}" 완료 → $next(으)로 이동'),
                          action: SnackBarAction(label: '되돌리기', onPressed: () => s.undoRoll(prev)),
                        ));
                      }
                    }
                  : null)
          : Icon(Icons.circle, color: itemColor, size: 14),
      title: Text(item.title,
          style: TextStyle(
              decoration: done ? TextDecoration.lineThrough : null)),
      subtitle: Text([
        if (timeLabel(item) != null) '🕒 ${timeLabel(item)}',
        if (!mine) s.ownerName(item),
        s.categoriesOf(item).map((c) => c.name).join('·'),
        if (item.visibility == m.Visibility.private) '프라이빗',
        if (item.location.isNotEmpty) '📍 ${item.location}',
        if (item.isRolling) '↻ ${rollLabel(item)} (완료하면 다음 일정으로)',
        if (item.repeat != Repeat.none) '반복',
        if (item.note.isNotEmpty) item.note,
      ].join(' · ')),
      trailing: item.location.isEmpty
          ? null
          : PopupMenuButton<MapApp>(
              tooltip: '지도에서 보기',
              icon: const Icon(Icons.map_outlined, size: 20),
              onSelected: (app) =>
                  launchUrl(mapUri(app, item.location), mode: LaunchMode.externalApplication),
              itemBuilder: (_) => [
                for (final a in MapApp.values)
                  PopupMenuItem(value: a, child: Text('${mapAppNames[a]}에서 열기')),
              ],
            ),
      onTap: canEdit ? () => showEditSheet(context, item: item, day: day) : null,
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
    final now = DateTime.now();
    final overdue = open.where((i) => isOverdue(i, now)).toList();
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

/// 휴일/기념일(임시공휴일 등) 추가 대화상자
Future<void> addCustomDayDialog(BuildContext context, DateTime day) async {
  final name = TextEditingController();
  var holiday = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('${day.month}월 ${day.day}일에 추가'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '이름 (예: 임시공휴일)')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('공휴일 (빨간 날)'),
            value: holiday,
            onChanged: (v) => setS(() => holiday = v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('추가')),
        ],
      ),
    ),
  );
  if (ok == true && name.text.trim().isNotEmpty && context.mounted) {
    await context.read<Store>().addCustomDay(day, name.text.trim(), holiday);
  }
}
