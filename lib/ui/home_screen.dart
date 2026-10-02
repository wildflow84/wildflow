import 'dart:async';

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
import '../models/item.dart' show Item, ItemType, dateOnly, isDoneOn, isOverdue, moveItemByDays, nextRollDate, rollLabel, timeLabel, chipTimeLabel;
import 'category_manager.dart';
import 'date_picker.dart';
import 'settings_screen.dart';
import 'snack.dart';
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
  bool _dragging = false; // 일정을 끌고 있는 동안: 달력 양 끝에 월 이동 영역을 보여준다
  double _swipeDx = 0;

  /// 원하는 날짜로 바로 이동 (1901~2200)
  Future<void> _jump(BuildContext context) async {
    final d = await pickDate(context, initial: _selected, title: '이동할 날짜');
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

    final grid = _MonthGrid(
      month: _month,
      selected: _selected,
      dragging: _dragging,
      onDragStarted: () => setState(() => _dragging = true),
      onBlankTap: (d) {
        setState(() => _selected = d);
        _quickAdd(context, d, wide);
      },
      onItemTap: (item, d) => showEditSheet(context, item: item, day: d),
      onMove: _moveItem,
    );

    // 달력을 좌우로 밀면(마우스 드래그, 터치 스와이프) 월이 넘어간다.
    // 일정을 끌고 있을 때는 양 끝 영역에 대고 있으면 월이 계속 넘어가 다른 달로 옮길 수 있다.
    final calendar = Listener(
      onPointerUp: (_) {
        if (_dragging) setState(() => _dragging = false);
      },
      onPointerCancel: (_) {
        if (_dragging) setState(() => _dragging = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _swipeDx = 0,
        onHorizontalDragUpdate: (d) => _swipeDx += d.delta.dx,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (_swipeDx < -80 || v < -400) {
            _shift(1);
          } else if (_swipeDx > 80 || v > 400) {
            _shift(-1);
          }
          _swipeDx = 0;
        },
        child: Stack(children: [
          Positioned.fill(child: grid),
          if (_dragging) ...[
            Positioned(left: 0, top: 30, bottom: 0, width: 44, child: _EdgeZone(left: true, onFlip: () => _shift(-1))),
            Positioned(right: 0, top: 30, bottom: 0, width: 44, child: _EdgeZone(left: false, onFlip: () => _shift(1))),
          ],
        ]),
      ),
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
      bottomNavigationBar: _BottomBar(
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.calendar_month), label: '캘린더'),
            NavigationDestination(icon: Icon(Icons.checklist), label: '할 일'),
          ],
        ),
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
    showTimedSnack(
      messenger,
      '"${item.title}" → ${DateFormat('M월 d일 (E)', 'ko').format(to)}로 이동',
      actionLabel: '되돌리기',
      onAction: () => s.save(item),
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

/// 내 항목은 항상 보이고, 상대가 올린 같이 보기 항목만 이 알약 버튼으로 켜고 끈다.
/// 넓은 화면(PC)에서 하단 탭이 끝까지 늘어나지 않게 가운데로 모은다.
class _BottomBar extends StatelessWidget {
  final Widget child;
  const _BottomBar({required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: child),
      ),
    );
  }
}

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

/// 일정을 끌고 있을 때 달력 양 끝에 나타나는 월 이동 영역. 위에 대고 있으면 월이 넘어간다.
class _EdgeZone extends StatefulWidget {
  final bool left;
  final VoidCallback onFlip;
  const _EdgeZone({required this.left, required this.onFlip});

  @override
  State<_EdgeZone> createState() => _EdgeZoneState();
}

class _EdgeZoneState extends State<_EdgeZone> {
  Timer? _timer;
  bool _hover = false;

  void _enter() {
    if (_hover) return;
    setState(() => _hover = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 450), () {
      widget.onFlip();
      _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => widget.onFlip());
    });
  }

  void _leave() {
    _timer?.cancel();
    if (mounted) setState(() => _hover = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return DragTarget<_DragData>(
      onWillAcceptWithDetails: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _enter();
        });
        return true;
      },
      onLeave: (_) => _leave(),
      onAcceptWithDetails: (_) => _leave(), // 여기에 놓으면 아무것도 바꾸지 않는다
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: widget.left ? Alignment.centerLeft : Alignment.centerRight,
            end: widget.left ? Alignment.centerRight : Alignment.centerLeft,
            colors: [accent.withValues(alpha: _hover ? 0.55 : 0.28), accent.withValues(alpha: 0)],
          ),
        ),
        child: Align(
          alignment: widget.left ? Alignment.centerLeft : Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(widget.left ? Icons.chevron_left : Icons.chevron_right, size: 28, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month, selected;
  final bool dragging;
  final VoidCallback onDragStarted;
  final ValueChanged<DateTime> onBlankTap;
  final void Function(Item item, DateTime day) onItemTap;
  final void Function(Item item, DateTime from, DateTime to) onMove;
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.dragging,
    required this.onDragStarted,
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
            Expanded(child: _weekRow(context, s, gridStart.add(Duration(days: w * 7)), today)),
        ]),
      ),
    ]);
  }

  /// 한 주: 날짜 칸 7개 + 여러 날에 걸친 일정을 이어진 바로 (구글 캘린더처럼)
  Widget _weekRow(BuildContext context, Store s, DateTime ws, DateTime today) {
    final we = ws.add(const Duration(days: 6));
    final wsn = dayNumber(ws);

    // 이번 주와 겹치는 기간 일정 -> 조각
    final segs = <_Seg>[];
    for (final i in s.visibleItems.where(isSpanning)) {
      final sd = dateOnly(i.start), ed = dateOnly(i.end!);
      if (ed.isBefore(ws) || sd.isAfter(we)) continue;
      final from = sd.isBefore(ws) ? ws : sd;
      final to = ed.isAfter(we) ? we : ed;
      segs.add(_Seg(i, dayNumber(from) - wsn, dayNumber(to) - wsn, !sd.isBefore(ws), !ed.isAfter(we), from));
    }
    segs.sort((a, b) {
      final c = a.c0.compareTo(b.c0);
      if (c != 0) return c;
      final l = (b.c1 - b.c0).compareTo(a.c1 - a.c0);
      return l != 0 ? l : a.item.title.compareTo(b.item.title);
    });
    // 겹치지 않게 줄(lane) 배정
    final lanes = <List<_Seg>>[];
    for (final g in segs) {
      var placed = false;
      for (final lane in lanes) {
        if (lane.last.c1 < g.c0) {
          lane.add(g);
          placed = true;
          break;
        }
      }
      if (!placed) lanes.add([g]);
    }

    return LayoutBuilder(builder: (context, c) {
      final cellW = c.maxWidth / 7;
      return Stack(children: [
        Row(children: [
          for (var d = 0; d < 7; d++)
            Expanded(
              child: Builder(builder: (context) {
                final day = ws.add(Duration(days: d));
                return _DayCell(
                  day: day,
                  inMonth: day.month == month.month,
                  isToday: day == today,
                  isSelected: day == selected,
                  items: s.itemsOn(day).where((i) => !isSpanning(i)).toList(),
                  laneCount: lanes.length,
                  onTap: onBlankTap,
                  onTapItem: onItemTap,
                  onDropItem: onMove,
                  onDragStarted: onDragStarted,
                );
              }),
            ),
        ]),
        for (var li = 0; li < lanes.length; li++)
          for (final g in lanes[li])
            Positioned(
              left: g.c0 * cellW + 1,
              top: _barTop + li * _laneH,
              width: (g.c1 - g.c0 + 1) * cellW - 2,
              height: _laneH - 1,
              // 끌고 있는 동안엔 바가 아래 날짜 칸으로의 놓기를 가로막지 않게 한다
              child: IgnorePointer(
                ignoring: dragging,
                child: _SpanBar(
                  seg: g,
                  color: s.colorOf(g.item),
                  ownerInitial: g.item.ownerUid == s.uid ? null : _initial(s.ownerLabel(g.item)),
                  canEdit: g.item.ownerUid == s.uid || g.item.visibility == m.Visibility.shared,
                  onTap: () => onItemTap(g.item, g.firstDay),
                  onDragStarted: onDragStarted,
                ),
              ),
            ),
      ]);
    });
  }
}

/// 여러 날에 걸친 일정(반복 아님)인지
bool isSpanning(Item i) =>
    i.type == ItemType.event && !i.isRecurring && i.end != null && dateOnly(i.end!).isAfter(dateOnly(i.start));

const double _barTop = 19; // 날짜 숫자 줄 아래
const double _laneH = 14;

class _Seg {
  final Item item;
  final int c0, c1; // 이번 주에서의 시작/끝 칸 (0=일 ... 6=토)
  final bool startsHere, endsHere; // 실제 시작/끝이 이번 주인지 (아니면 이어지는 모양)
  final DateTime firstDay;
  _Seg(this.item, this.c0, this.c1, this.startsHere, this.endsHere, this.firstDay);
}

/// 이어진 일정 바. 앞뒤로 이어지는 쪽은 모서리를 각지게 해서 하나로 보이게 한다.
class _SpanBar extends StatelessWidget {
  final _Seg seg;
  final Color color;
  final String? ownerInitial;
  final bool canEdit;
  final VoidCallback onTap;
  final VoidCallback onDragStarted;
  const _SpanBar({
    required this.seg,
    required this.color,
    required this.ownerInitial,
    required this.canEdit,
    required this.onTap,
    required this.onDragStarted,
  });

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(seg.startsHere ? 4 : 0),
          right: Radius.circular(seg.endsHere ? 4 : 0),
        ),
      ),
      child: Row(children: [
        if (!seg.startsHere) const Icon(Icons.arrow_left, size: 12, color: Colors.white70),
        if (ownerInitial != null)
          Container(
            width: 11,
            height: 11,
            margin: const EdgeInsets.only(right: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
            child: Text(ownerInitial!,
                style: const TextStyle(fontSize: 7, color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        if (seg.item.visibility == m.Visibility.private) const Icon(Icons.lock, size: 8),
        Expanded(
          child: Text(seg.item.title,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9)),
        ),
        if (!seg.endsHere) const Icon(Icons.arrow_right, size: 12, color: Colors.white70),
      ]),
    );
    final tappable = GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: bar);
    if (!canEdit) return tappable;
    return LongPressDraggable<_DragData>(
      data: _DragData(seg.item, seg.firstDay),
      delay: const Duration(milliseconds: 180),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      feedback: Material(color: Colors.transparent, child: SizedBox(width: 150, height: _laneH, child: Opacity(opacity: 0.9, child: bar))),
      childWhenDragging: Opacity(opacity: 0.3, child: bar),
      child: tappable,
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth, isToday, isSelected;
  final List<Item> items;
  final ValueChanged<DateTime> onTap; // 빈 공간 탭
  final void Function(Item item, DateTime day) onTapItem;
  final void Function(Item item, DateTime from, DateTime to) onDropItem;
  final VoidCallback onDragStarted;
  final int laneCount; // 이 주에 이어진 일정 바가 차지하는 줄 수
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.items,
    required this.onTap,
    required this.onTapItem,
    required this.onDropItem,
    required this.onDragStarted,
    this.laneCount = 0,
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
            final room = ((c.maxHeight - 16 - laneCount * _laneH) / 13).floor().clamp(0, 12);
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
                if (laneCount > 0) SizedBox(height: laneCount * _laneH),
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
      ownerInitial: i.ownerUid == s0.uid ? null : _initial(s0.ownerLabel(i)),
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
    if (!canEdit || i.isRecurring) return tappable;
    return LongPressDraggable<_DragData>(
      data: _DragData(i, day),
      delay: const Duration(milliseconds: 180),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 130, child: Opacity(opacity: 0.9, child: chip)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: tappable,
    );
  }
}

String _initial(String name) => name.isEmpty ? '?' : String.fromCharCode(name.runes.first);

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
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: color)),
      );
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final bool isTodo, done, isPrivate;
  final String? ownerInitial; // 상대가 만든 항목이면 이름 첫 글자
  final bool isRolling;
  const _Chip({
    required this.text,
    required this.color,
    this.isTodo = false,
    this.done = false,
    this.isPrivate = false,
    this.ownerInitial,
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
        if (ownerInitial != null)
          Container(
            width: 11,
            height: 11,
            margin: const EdgeInsets.only(right: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
            child: Text(ownerInitial!,
                style: const TextStyle(fontSize: 7, color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        if (isTodo) Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 9),
        if (isPrivate) const Icon(Icons.lock, size: 8),
        if (isRolling) const Icon(Icons.autorenew, size: 9),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

/// 항목 부가정보 한 조각 (아이콘 또는 색 점 + 글자). 긴 글자는 말줄임.
class _Meta extends StatelessWidget {
  final IconData? icon;
  final Color? dot;
  final String text;
  const _Meta({this.icon, this.dot, required this.text});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) Icon(icon, size: 14, color: Colors.white54),
        if (dot != null)
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ),
      ]),
    );
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
                        showTimedSnack(
                          messenger,
                          '"${item.title}" 완료 → $next(으)로 이동',
                          actionLabel: '되돌리기',
                          onAction: () => s.undoRoll(prev),
                        );
                      }
                    }
                  : null)
          : Icon(Icons.circle, color: itemColor, size: 14),
      title: Text(item.title,
          style: TextStyle(
              decoration: done ? TextDecoration.lineThrough : null)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Wrap(spacing: 12, runSpacing: 3, children: [
          if (timeLabel(item) != null) _Meta(icon: Icons.schedule, text: timeLabel(item)!),
          if (item.type == ItemType.event && item.location.isNotEmpty)
            _Meta(icon: Icons.place_outlined, text: item.location),
          _Meta(dot: s.categoriesOf(item).first.color, text: s.categoriesOf(item).first.name),
          if (item.isRolling) _Meta(icon: Icons.autorenew, text: rollLabel(item)),
          if (item.isRecurring) _Meta(icon: Icons.repeat, text: item.effectiveRule!.describe(item.start)),
          if (item.visibility == m.Visibility.private) const _Meta(icon: Icons.lock_outline, text: '나만'),
          // 같이 보기 항목은 만든 사람을 보여준다
          if (item.visibility == m.Visibility.shared)
            _Meta(icon: Icons.person_outline, text: s.ownerLabel(item)),
          if (item.note.isNotEmpty) _Meta(icon: Icons.notes, text: item.note),
        ]),
      ),
      trailing: item.type != ItemType.event || item.location.isEmpty
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
      final d = !i.isRecurring ? i.start : today;
      return !isDoneOn(i, d) && (i.isRecurring ? m.occursOn(i, today) : true);
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
                  day: !i.isRecurring ? dateOnly(i.start) : today),
          ]);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(children: [
      section('지난 할 일', overdue),
      section('앞으로', upcoming),
      if (open.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('할 일 끝! 순대 산책 ㄱㄱ'))),
    ]),
      ),
    );
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
