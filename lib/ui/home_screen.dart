import 'dart:async';
import 'palette.dart';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../models/kr_calendar.dart';
import '../models/lunar.dart';
import '../models/map_links.dart';
import '../models/category.dart' show subscriptionCategory;
import '../models/item.dart' as m;
import '../models/item.dart' show Item, ItemType, dateOnly, isDoneOn, isOverdue, moveItemByDays, nextRollDate, rollLabel, timeLabel, chipTimeLabel;
import 'agenda.dart';
import 'category_manager.dart';
import 'checklist.dart';
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
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);

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
    final wideBar = MediaQuery.sizeOf(context).width >= 600; // 좁은 화면은 화살표 대신 밀기/휠로 월 이동

    final grid = _MonthGrid(
      month: _month,
      selected: _selected,
      dragging: _dragging,
      onDragStarted: () => setState(() => _dragging = true),
      onBlankTap: (d) {
        setState(() => _selected = d);
        // 그날 일정/할 일이 있으면 목록을 보여주고(PC는 오른쪽 패널에 이미 보임), 아무것도 없을 때만 추가 메뉴
        if (context.read<Store>().itemsOn(d).isEmpty) {
          _quickAdd(context, d, wide);
        } else if (!wide) {
          _openDaySheet(context, d);
        }
      },
      // PC: 바로 수정. 폰: 먼저 그날 목록(제목이 안 잘림)을 보여주고, 거기서 눌러야 수정으로 간다.
      onItemTap: (item, d) {
        if (wide) {
          showEditSheet(context, item: item, day: d);
        } else {
          setState(() => _selected = d);
          _openDaySheet(context, d);
        }
      },
      onMove: _moveItem,
    );

    // 달력을 좌우로 밀면(마우스 드래그, 터치 스와이프) 월이 넘어간다.
    // 일정을 끌고 있을 때는 양 끝 영역에 대고 있으면 월이 계속 넘어가 다른 달로 옮길 수 있다.
    final calendar = Listener(
      // 마우스 휠/트랙패드: 아래로 굴리면 다음 달, 위로 굴리면 이전 달 (연속 입력은 0.35초에 한 번만)
      onPointerSignal: (e) {
        if (e is! PointerScrollEvent || e.scrollDelta.dy == 0) return;
        final now = DateTime.now();
        if (now.difference(_lastWheel) < const Duration(milliseconds: 350)) return;
        _lastWheel = now;
        _shift(e.scrollDelta.dy > 0 ? 1 : -1);
      },
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
                            style: const TextStyle(fontSize: 12, color: kMuted)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const _SharedToggle(),
              ])
            : Text(_tab == 1 ? '다가오는 일정' : '할 일'),
        actions: [
          IconButton(
            tooltip: '검색',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          if (_tab == 0 && wideBar) IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
          if (_tab == 0) ...[
            TextButton(
                onPressed: () => setState(() {
                      _month = DateTime(DateTime.now().year, DateTime.now().month);
                      _selected = dateOnly(DateTime.now());
                    }),
                child: const Text('오늘')),
            if (wideBar) IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
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
              if (v == 'filter') _categoryFilter(context);
              if (v == 'out') s.repo.signOut();
              if (v == 'code') {
                Clipboard.setData(ClipboardData(text: s.spaceId!));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('초대 코드를 복사했어')));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'filter',
                  child: Text(s.hiddenCategories.isEmpty ? '카테고리별 보기' : '카테고리별 보기 (${s.hiddenCategories.length}개 숨김)')),
              const PopupMenuItem(value: 'categories', child: Text('카테고리 관리')),
              const PopupMenuItem(value: 'settings', child: Text('설정 (기본 공개 범위 등)')),
              const PopupMenuItem(value: 'code', child: Text('초대 코드 복사')),
              const PopupMenuItem(value: 'out', child: Text('로그아웃')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _tab == 2
                ? const _TodoTab()
                : _tab == 1
                    ? const AgendaView()
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
            day: _selected, type: _tab == 2 ? ItemType.todo : ItemType.event),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: _BottomBar(
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.calendar_month), label: '캘린더'),
            NavigationDestination(icon: Icon(Icons.view_agenda_outlined), label: '목록'),
            NavigationDestination(icon: Icon(Icons.checklist), label: '할 일'),
          ],
        ),
      ),
    );
  }

  /// 카테고리별로 켜고 끄기 (끈 카테고리의 일정/할 일은 달력, 목록, 할 일 탭에서 숨김)
  void _categoryFilter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Consumer<Store>(
        builder: (ctx, s, _) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: const Text('카테고리별 보기', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: TextButton(
                onPressed: s.hiddenCategories.isEmpty ? null : s.showAllCategories,
                child: const Text('모두 보기'),
              ),
            ),
            for (final c in [...s.categories, if (s.items.any((i) => i.subscriptionId != null)) subscriptionCategory])
              SwitchListTile(
                secondary: CircleAvatar(backgroundColor: c.color, radius: 8),
                title: Text(c.name),
                value: !s.hiddenCategories.contains(c.id),
                onChanged: (v) => s.setCategoryHidden(c.id, !v),
              ),
          ]),
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
              border: Border.all(color: on ? accent : kFaint),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(on ? Icons.people : Icons.people_outline,
                  size: 17, color: on ? accent : kMuted),
              if (!narrow) ...[
                const SizedBox(width: 6),
                Text('공유',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: on ? accent : kMuted)),
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
            child: Icon(widget.left ? Icons.chevron_left : Icons.chevron_right, size: 28, color: kAccent),
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
                              ? kRed
                              : i == 6
                                  ? kBlue
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

    // 칸마다 그 칸을 지나는 바가 있는 줄까지만 비워 둔다 (바가 없는 칸은 날짜 바로 아래부터 채움)
    final laneNeed = List<int>.filled(7, 0);
    for (var li = 0; li < lanes.length; li++) {
      for (final g in lanes[li]) {
        for (var col = g.c0; col <= g.c1; col++) {
          if (laneNeed[col] < li + 1) laneNeed[col] = li + 1;
        }
      }
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
                  laneCount: laneNeed[d],
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
    final fg = onColor(color);
    final bar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(seg.startsHere ? 4 : 0),
          right: Radius.circular(seg.endsHere ? 4 : 0),
        ),
      ),
      child: IconTheme(
        data: IconThemeData(color: fg),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: Row(children: [
        if (!seg.startsHere) Icon(Icons.arrow_left, size: 12, color: fg.withValues(alpha: 0.7)),
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
        if (!seg.endsHere) Icon(Icons.arrow_right, size: 12, color: fg.withValues(alpha: 0.7)),
      ]),
        ),
      ),
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

  String? _backdropFor(Store s) {
    for (final i in s.visibleItems) {
      if (i.type == ItemType.event && i.photoUrl != null && i.end != null && !i.isRecurring) {
        final a = dateOnly(i.start), b = dateOnly(i.end!);
        if (b.isAfter(a) && !day.isBefore(a) && !day.isAfter(b)) return i.photoUrl;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s0 = context.watch<Store>();
    final marks = s0.cal.marksOn(day);
    final isHoliday = marks.any((m) => m.isHoliday);
    final numColor = (day.weekday == DateTime.sunday || isHoliday)
        ? kRed
        : day.weekday == DateTime.saturday
            ? kBlue
            : null;

    final backdrop = _backdropFor(s0);

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
          color: mk.kind == MarkKind.term ? const Color(0xFFE8A95B) : kMuted));
    }

    return DragTarget<_DragData>(
      onWillAcceptWithDetails: (d) => dayNumber(d.data.from) != dayNumber(day),
      onAcceptWithDetails: (d) => onDropItem(d.data.item, d.data.from, day),
      builder: (context, candidates, _) => InkWell(
      onTap: () => onTap(day),
      child: Container(
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? kGreen.withValues(alpha: 0.15) : kCard,
          // 사진이 있는 여러 날 일정(여행 등)이 걸친 날은 그 장소 사진을 옅게 깐다
          image: backdrop == null
              ? null
              : DecorationImage(
                  image: NetworkImage(backdrop),
                  fit: BoxFit.cover,
                  opacity: 0.28,
                  onError: (_, _) {}),
          border: Border.all(
              color: candidates.isNotEmpty
                  ? kGreen
                  : isSelected
                      ? kAccent
                      : kLine,
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
                            color: kAccent,
                            borderRadius: BorderRadius.all(Radius.circular(8)))
                        : null,
                    child: Text('${day.day}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isToday ? Colors.white : numColor)),
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text('(${lunarText(day)})',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(fontSize: 9, color: kFaint)),
                  ),
                ]),
                if (laneCount > 0) SizedBox(height: laneCount * _laneH),
                ...lines.take(shown.clamp(0, lines.length)),
                if (overflow && room > 0)
                  Text('+${lines.length - shown}',
                      style: const TextStyle(fontSize: 9, color: kMuted)),
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
    final fg = isTodo ? kInk : onColor(color);
    return Container(
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: isTodo ? color.withValues(alpha: 0.28) : color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: IconTheme(
        data: IconThemeData(color: fg),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
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
        if (isRolling && MediaQuery.sizeOf(context).width >= 600) const Icon(Icons.autorenew, size: 9),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 9,
                  decoration: done ? TextDecoration.lineThrough : null)),
        ),
      ]),
        ),
      ),
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
        trailing: IconButton(
          tooltip: '일정 / 할 일 추가',
          icon: const Icon(Icons.add),
          onPressed: () => showEditSheet(context, day: day),
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
                  label: Text(m.name, style: TextStyle(fontSize: 12, color: m.isHoliday ? Colors.white : kInk)),
                  side: BorderSide.none,
                  backgroundColor: m.isHoliday
                      ? const Color(0xFF3FA796)
                      : m.kind == MarkKind.term
                          ? const Color(0xFFEBD9B4)
                          : kFill,
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
                for (final i in items) ItemTile(item: i, day: day),
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
        if (icon != null) Icon(icon, size: 14, color: kMuted),
        if (dot != null)
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: kSubtle)),
        ),
      ]),
    );
  }
}

/// 같이 보기 항목의 재촉(확인 요청) 버튼과 지도 메뉴
Widget? _trailing(BuildContext context, Store s, Item item, DateTime day, bool done) {
  final hasPartner = s.names.keys.any((k) => k != s.uid);
  final canNudge = item.visibility == m.Visibility.shared && hasPartner && !done && item.id.isNotEmpty;
  final hasMap = item.type == ItemType.event && item.location.isNotEmpty;
  if (!canNudge && !hasMap) return null;
  return Row(mainAxisSize: MainAxisSize.min, children: [
    if (canNudge)
      IconButton(
        tooltip: '확인 요청 (재촉)',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.notifications_active_outlined, size: 20),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final msg = await s.nudge(item);
          showTimedSnack(messenger, msg);
        },
      ),
    if (hasMap)
      PopupMenuButton<MapApp>(
        tooltip: '지도에서 보기',
        icon: const Icon(Icons.map_outlined, size: 20),
        onSelected: (app) => launchUrl(mapUri(app, item.location), mode: LaunchMode.externalApplication),
        itemBuilder: (_) => [
          for (final a in MapApp.values) PopupMenuItem(value: a, child: Text('${mapAppNames[a]}에서 열기')),
        ],
      ),
  ]);
}

class ItemTile extends StatelessWidget {
  final Item item;
  final DateTime day;
  const ItemTile({super.key, required this.item, required this.day});

  @override
  Widget build(BuildContext context) {
    final s = context.read<Store>();
    final done = isDoneOn(item, day);
    final mine = item.ownerUid == s.uid;
    final canEdit = mine || item.visibility == m.Visibility.shared; // 같이 보기 항목은 같이 편집
    final itemColor = s.colorOf(item);
    final tile = ListTile(
      leading: item.type == ItemType.todo
          ? Checkbox(
              value: done,
              onChanged: canEdit
                  ? (_) async {
                      final messenger = ScaffoldMessenger.of(context);
                      var checkAll = false;
                      if (!done) {
                        // 체크리스트가 남아 있으면 확인
                        final c = await confirmIncompleteChecklist(context, item, day);
                        if (c == CompleteChoice.cancel) return;
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
          if (item.dday) _Meta(icon: Icons.hourglass_bottom, text: m.ddayLabel(day, DateTime.now())),
          if (m.anniversaryLabel(item, day) != null) _Meta(icon: Icons.cake_outlined, text: m.anniversaryLabel(item, day)!),
          if (item.isRolling) _Meta(icon: Icons.autorenew, text: rollLabel(item)),
          if (item.isRecurring) _Meta(icon: Icons.repeat, text: item.effectiveRule!.describe(item.start)),
          if (item.visibility == m.Visibility.private) const _Meta(icon: Icons.lock_outline, text: '나만'),
          if (item.type == ItemType.todo && item.assignee.isNotEmpty)
            _Meta(icon: Icons.assignment_ind_outlined, text: '담당 ${item.assignee == s.uid ? '나' : (s.names[item.assignee] ?? '상대')}'),
          // 같이 보기 항목은 만든 사람을 보여준다
          if (item.visibility == m.Visibility.shared)
            _Meta(icon: Icons.person_outline, text: s.ownerLabel(item)),
          if (item.subscriptionId != null) const _Meta(icon: Icons.rss_feed, text: '구독'),
          if (item.hasChecklist)
            _Meta(icon: Icons.checklist, text: '${item.checklist.length - item.checksLeftOn(day)}/${item.checklist.length}'),
          if (item.note.isNotEmpty) _Meta(icon: Icons.notes, text: item.note),
        ]),
      ),
      trailing: _trailing(context, s, item, day, done),
      onTap: canEdit ? () => showEditSheet(context, item: item, day: day) : null,
    );
    final hasPhoto = item.type == ItemType.event && item.photoUrl != null;
    if (!hasPhoto && !item.hasChecklist) return tile;
    // 위치 사진은 구글 캘린더처럼 일정 위에 배너로, 체크리스트는 바로 아래에 펼쳐서 보여준다
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hasPhoto)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(item.photoUrl!,
                height: 96, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
        ),
      tile,
      if (item.hasChecklist) ChecklistInline(item: item, day: day, canEdit: canEdit),
    ]);
  }
}

/// 날짜 구분 없이 오늘 기준으로 할 일을 모아 본다.
class _TodoTab extends StatefulWidget {
  const _TodoTab();

  @override
  State<_TodoTab> createState() => _TodoTabState();
}

class _TodoTabState extends State<_TodoTab> {
  String _who = 'all'; // all / me / partner
  String _sort = 'due'; // due=마감 순, category=카테고리별
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final today = dateOnly(DateTime.now());
    final partnerUid = s.names.keys.where((k) => k != s.uid).firstOrNull;
    final partnerName = partnerUid == null ? null : s.names[partnerUid];
    final todos = s.visibleItems
        .where((i) => i.type == ItemType.todo)
        .where((i) => _who == 'all' || partnerUid == null
            ? true
            : _who == 'me'
                ? i.isMineTo(s.uid)
                : i.isMineTo(partnerUid))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final open = todos.where((i) {
      final d = !i.isRecurring ? i.start : today;
      return !isDoneOn(i, d) && (i.isRecurring ? m.occursOn(i, today) : true);
    }).toList();
    final now = DateTime.now();
    final overdue = open.where((i) => isOverdue(i, now)).toList();
    final upcoming = open.where((i) => !overdue.contains(i)).toList();
    // 완료한 일: 최근에 완료한 순 (되돌리려면 체크를 풀면 돼)
    final doneList = todos.where((i) {
      final d = !i.isRecurring ? i.start : today;
      return isDoneOn(i, d) && (!i.isRecurring || m.occursOn(i, today));
    }).toList()
      ..sort((a, b) => (b.lastDoneAt ?? b.start).compareTo(a.lastDoneAt ?? a.start));
    final catIndex = {for (var k = 0; k < s.categories.length; k++) s.categories[k].id: k};
    int byCategory(Item a, Item b) {
      final ca = catIndex[a.categories.firstOrNull] ?? 999, cb = catIndex[b.categories.firstOrNull] ?? 999;
      return ca != cb ? ca.compareTo(cb) : a.start.compareTo(b.start);
    }
    if (_sort == 'category') upcoming.sort(byCategory);

    final df = DateFormat('M월 d일 (E)', 'ko');
    Widget card(List<Item> list, DateTime Function(Item) dayOf) => Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
          child: Material(
            color: kCard,
            elevation: 1,
            shadowColor: kCardShadow,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var k = 0; k < list.length; k++) ...[
                if (k > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                ItemTile(item: list[k], day: dayOf(list[k])),
              ],
            ]),
          ),
        );
    DateTime dayOf(Item i) => !i.isRecurring ? dateOnly(i.start) : today;
    Widget header(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color)));

    // 마감 순이면 날짜별로 둥근 카드로 묶고, 카테고리별/완료 목록은 카드 하나로 묶는다.
    Widget section(String title, List<Item> list, {bool byDay = false}) {
      if (list.isEmpty) return const SizedBox.shrink();
      if (!byDay) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [header(title), card(list, dayOf)]);
      final groups = <DateTime, List<Item>>{};
      for (final i in list) {
        groups.putIfAbsent(dayOf(i), () => []).add(i);
      }
      final days = groups.keys.toList()..sort();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header(title),
        for (final d in days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Text(d == today ? '오늘 · ${df.format(d)}' : df.format(d),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: d == today
                        ? kBlue
                        : d.weekday == DateTime.sunday
                            ? kRed
                            : d.weekday == DateTime.saturday
                                ? kBlue
                                : null)),
          ),
          card(groups[d]!, dayOf),
        ],
      ]);
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (partnerUid != null)
            for (final (k, label) in [('all', '전체'), ('me', '내 것'), ('partner', '${partnerName ?? '상대'} 것')])
              ChoiceChip(label: Text(label), selected: _who == k, onSelected: (_) => setState(() => _who = k)),
          FilterChip(
            avatar: const Icon(Icons.task_alt, size: 16),
            label: const Text('완료한 일'),
            selected: _showDone,
            onSelected: (v) => setState(() => _showDone = v),
          ),
          PopupMenuButton<String>(
            tooltip: '정렬',
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'due', child: Text('마감 빠른 순')),
              PopupMenuItem(value: 'category', child: Text('카테고리별')),
            ],
            child: Chip(
              avatar: const Icon(Icons.sort, size: 16),
              label: Text(_sort == 'due' ? '마감 순' : '카테고리별'),
            ),
          ),
        ]),
      ),
      section('지난 할 일', overdue, byDay: _sort == 'due'),
      section(_sort == 'category' ? '카테고리별' : '앞으로', upcoming, byDay: _sort == 'due'),
      if (open.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('할 일 끝! 순대 산책 ㄱㄱ'))),
      if (_showDone) section('완료한 일 (${doneList.length})', doneList.take(30).toList()),
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
