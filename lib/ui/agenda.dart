import 'package:flutter/material.dart';
import 'palette.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/item.dart';
import '../models/lunar.dart';
import 'home_screen.dart' show ItemTile;

/// 앞으로의 일정/할 일을 날짜별로 쭉 보여주는 목록 (오늘부터 30일씩 더 보기).
class AgendaView extends StatefulWidget {
  const AgendaView({super.key});

  @override
  State<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<AgendaView> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final today = dateOnly(DateTime.now());
    final df = DateFormat('M월 d일 (E)', 'ko');
    final rows = <Widget>[];
    for (var i = 0; i < _days; i++) {
      final day = DateTime(today.year, today.month, today.day + i);
      final items = s.itemsOn(day);
      final holidays = s.cal.marksOn(day).where((m) => m.isHoliday).toList();
      final custom = s.customDaysOn(day);
      if (items.isEmpty && holidays.isEmpty && custom.isEmpty) continue;
      final lunar = solarToLunar(day);
      final isToday = i == 0;
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(isToday ? '오늘 · ${df.format(day)}' : df.format(day),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isToday
                      ? kAccent
                      : day.weekday == DateTime.sunday || holidays.isNotEmpty
                          ? kRed
                          : day.weekday == DateTime.saturday
                              ? kBlue
                              : null)),
          const SizedBox(width: 8),
          if (lunar != null)
            Text('음력 ${lunar.monthLabel} ${lunar.day}일', style: const TextStyle(fontSize: 11, color: kMuted)),
          const Spacer(),
          for (final h in holidays.take(2))
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(h.name, style: const TextStyle(fontSize: 12, color: Color(0xFF3FA796))),
            ),
        ]),
      ));
      for (final c in custom) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text(c.name, style: const TextStyle(fontSize: 12, color: kMuted)),
        ));
      }
      if (items.isNotEmpty) {
        // 하루치 항목을 둥근 카드로 묶어 날짜별 구분이 한눈에 보이게
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
          child: Material(
            color: kCard,
            elevation: 1,
            shadowColor: kCardShadow,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                ItemTile(item: items[i], day: day),
              ],
            ]),
          ),
        ));
      }
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          if (rows.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('앞으로 30일은 비어 있어'))),
          ...rows,
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: OutlinedButton(
                onPressed: () => setState(() => _days += 30),
                child: Text('${_days + 30}일까지 더 보기'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 제목, 메모, 위치, 체크리스트로 일정/할 일 찾기.
bool itemMatches(Item i, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  bool has(String t) => t.toLowerCase().contains(q);
  return has(i.title) || has(i.note) || has(i.location) || i.checklist.any((c) => has(c.text));
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final today = dateOnly(DateTime.now());
    // 가까운 날짜순: 오늘 이후 먼저, 그 다음 지난 항목 (최근 순)
    final hits = s.visibleItems.where((i) => itemMatches(i, _q)).toList();
    DateTime keyOf(Item i) => i.isRecurring ? today : dateOnly(i.start);
    hits.sort((a, b) {
      final da = keyOf(a), db = keyOf(b);
      final fa = !da.isBefore(today), fb = !db.isBefore(today);
      if (fa != fb) return fa ? -1 : 1;
      return fa ? da.compareTo(db) : db.compareTo(da);
    });
    final df = DateFormat('y.M.d (E)', 'ko');
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '일정, 할 일, 위치, 메모 검색', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _q.trim().isEmpty
              ? const Center(child: Text('찾을 말을 입력해', style: TextStyle(color: kMuted)))
              : hits.isEmpty
                  ? const Center(child: Text('없어', style: TextStyle(color: kMuted)))
                  : ListView(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text('${hits.length}건', style: const TextStyle(color: kMuted, fontSize: 12)),
                      ),
                      for (final i in hits) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text(i.isRecurring ? '반복 · ${df.format(i.start)}부터' : df.format(i.start),
                              style: const TextStyle(fontSize: 11, color: kMuted)),
                        ),
                        ItemTile(item: i, day: keyOf(i)),
                      ],
                    ]),
        ),
      ),
    );
  }
}
