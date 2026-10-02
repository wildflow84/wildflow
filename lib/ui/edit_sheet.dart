import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/item.dart' as m;
import '../models/item.dart' show Item, ItemType, RepeatDelete, dateOnly, hasEndTime, repeatFor;
import '../models/recurrence.dart';
import 'category_manager.dart';
import 'color_picker.dart';
import 'date_picker.dart';
import 'recurrence_editor.dart';
import 'time_picker.dart';

Future<void> showEditSheet(BuildContext context,
    {Item? item, DateTime? day, ItemType type = ItemType.event}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditSheet(item: item, day: day ?? DateTime.now(), type: type),
  );
}

class _EditSheet extends StatefulWidget {
  final Item? item;
  final DateTime day;
  final ItemType type;
  const _EditSheet({this.item, required this.day, required this.type});

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late ItemType _type = widget.item?.type ?? widget.type;
  late final _title = TextEditingController(text: widget.item?.title);
  late final _note = TextEditingController(text: widget.item?.note);
  late final _location = TextEditingController(text: widget.item?.location);
  late DateTime _start = widget.item?.start ?? dateOnly(widget.day);
  late DateTime? _end = widget.item?.end == null ? null : dateOnly(widget.item!.end!);
  late bool _allDay = widget.item?.allDay ?? true;
  late TimeOfDay _startTime = widget.item != null && !widget.item!.allDay
      ? TimeOfDay(hour: widget.item!.start.hour, minute: widget.item!.start.minute)
      : const TimeOfDay(hour: 9, minute: 0);
  late TimeOfDay? _endTime = widget.item != null && hasEndTime(widget.item!)
      ? TimeOfDay(hour: widget.item!.end!.hour, minute: widget.item!.end!.minute)
      : null;
  late List<String> _cats; // 선택 순서 유지. 첫 번째가 대표(색상)
  late m.Visibility _vis;
  late bool _visTouched = widget.item != null; // 직접 바꾸면 카테고리 기본값으로 덮어쓰지 않는다
  late int? _color = widget.item?.color; // null이면 카테고리 색
  // 반복: 빠른 선택(구글 캘린더처럼 시작 날짜에서 값이 정해짐) 또는 맞춤 규칙
  late RepeatPreset _preset = presetOf(widget.item?.effectiveRule, widget.item?.start ?? _start);
  late Recurrence? _custom = widget.item?.effectiveRule;
  late int _rollEvery = widget.item?.rollEvery ?? 0; // 0이면 이동형 반복 아님
  late m.RollUnit _rollUnit = widget.item?.rollUnit ?? m.RollUnit.day;
  late bool _rollFromCompletion = widget.item?.rollFromCompletion ?? true;

  /// 현재 선택한 반복 규칙 (없으면 반복 안 함)
  Recurrence? get _rule => _preset == RepeatPreset.none
      ? null
      : _preset == RepeatPreset.custom
          ? _custom
          : presetRule(_preset, _start);

  Future<void> _editCustom() async {
    final r = await showRecurrenceEditor(context,
        start: _start, initial: _rule ?? presetRule(RepeatPreset.weekly, _start));
    if (r != null) {
      setState(() {
        _custom = r;
        _preset = RepeatPreset.custom;
        _end = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final s = context.read<Store>();
    _cats = [...(widget.item?.categories ?? [s.categories.first.id])];
    _vis = widget.item?.visibility ?? s.visibilityFor(_cats);
  }

  /// 카테고리 선택/해제. 하나는 항상 남긴다.
  void _toggleCategory(String id) {
    final s = context.read<Store>();
    setState(() {
      if (_cats.contains(id)) {
        if (_cats.length > 1) _cats.remove(id);
      } else {
        _cats.add(id);
      }
      if (!_visTouched) _vis = s.visibilityFor(_cats);
    });
  }

  Future<void> _pick(bool isEnd) async {
    final init = isEnd ? (_end ?? _start) : _start;
    final d = await pickDate(context,
        initial: init, title: isEnd ? '종료일' : (_type == ItemType.todo ? '마감일' : '시작일'));
    if (d == null) return;
    setState(() {
      if (isEnd) {
        _end = d.isBefore(_start) ? null : d;
      } else {
        _start = d;
        if (_end != null && _end!.isBefore(d)) _end = null;
      }
    });
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) => pickTimeDigital(context, initial: initial);

  /// 반복 항목 삭제 범위 선택
  Future<RepeatDelete?> _askDeleteScope(Item item) {
    final f = DateFormat('M월 d일 (E)', 'ko');
    final day = f.format(widget.day);
    final isLaterOccurrence = dateOnly(widget.day).isAfter(dateOnly(item.start));
    Widget option(RepeatDelete v, String title, String sub, {Color? color}) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, v),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16, color: color)),
              Text(sub, style: const TextStyle(fontSize: 12, color: Colors.white60)),
            ]),
          ),
        );
    return showDialog<RepeatDelete>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('"${item.title}" 반복 삭제'),
        children: [
          option(RepeatDelete.thisOnly, '이 날짜만', '$day 하루만 삭제'),
          option(RepeatDelete.following, '이 날짜 이후 모두',
              isLaterOccurrence ? '$day부터 이후 전부 삭제' : '첫 회차라서 전체 삭제와 같아'),
          option(RepeatDelete.all, '전체 삭제', '과거·현재·미래 모든 반복', color: Colors.redAccent),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    final s = context.read<Store>();
    // 이동형 반복이 켜진 할 일은 일반 반복을 쓰지 않는다
    final rule = _type == ItemType.todo && _rollEvery > 0 ? null : _rule;
    // 구글처럼, 시작일이 반복 규칙과 안 맞으면 첫 발생일로 옮긴다 (예: 매월 15일인데 시작이 2일이면 15일부터)
    var startDate = rule == null ? dateOnly(_start) : rule.firstOnOrAfter(_start);
    final startDt = _allDay
        ? startDate
        : DateTime(startDate.year, startDate.month, startDate.day, _startTime.hour, _startTime.minute);
    DateTime? endDt = rule == null ? _end : null;
    if (!_allDay && _endTime != null && _type == ItemType.event) {
      final d = endDt ?? startDate;
      endDt = DateTime(d.year, d.month, d.day, _endTime!.hour, _endTime!.minute);
      if (endDt.isBefore(startDt)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('종료 시각이 시작보다 빨라')));
        return;
      }
    }
    final base = widget.item ??
        Item(id: '', type: _type, title: '', start: startDt, ownerUid: s.uid);
    await s.save(base.copyWith(
      type: _type,
      title: _title.text.trim(),
      note: _note.text.trim(),
      location: _type == ItemType.event ? _location.text.trim() : '', // 위치는 일정만
      start: startDt,
      allDay: _allDay,
      end: endDt,
      clearEnd: endDt == null,
      categories: _cats,
      color: _color,
      clearColor: _color == null,
      visibility: _vis,
      repeat: repeatFor(rule),
      rule: rule,
      clearRule: rule == null,
      rollEvery: _type == ItemType.todo ? _rollEvery : 0,
      rollUnit: _rollUnit,
      rollFromCompletion: _rollFromCompletion,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final df = DateFormat('y.M.d (E)', 'ko');
    final catColor = s.categoryOf(_cats.first).color;
    // 상대가 만든 같이 보기 항목은 내용은 같이 고치되, 공개 범위는 만든 사람만 바꾼다.
    final isOwner = widget.item == null || widget.item!.ownerUid == s.uid;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<ItemType>(
              segments: const [
                ButtonSegment(value: ItemType.event, label: Text('일정'), icon: Icon(Icons.event)),
                ButtonSegment(value: ItemType.todo, label: Text('할 일'), icon: Icon(Icons.check_circle_outline)),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _pick(false), child: Text('${_type == ItemType.todo ? '마감 ' : ''}${df.format(_start)}'))),
              if (_type == ItemType.event && _rule == null) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('~')),
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => _pick(true),
                        child: Text(_end == null ? '종료일(선택)' : df.format(_end!)))),
              ],
            ]),
            const SizedBox(height: 12),
            if (_type == ItemType.todo)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('마감 시각 지정'),
                value: !_allDay,
                onChanged: (v) => setState(() => _allDay = !v),
              )
            else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('종일'),
                value: _allDay,
                onChanged: (v) => setState(() => _allDay = v),
              ),
            if (!_allDay)
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('${_type == ItemType.todo ? '마감' : '시작'} ${_hhmm(_startTime)}'),
                    onPressed: () async {
                      final t = await _pickTime(_startTime);
                      if (t != null) setState(() => _startTime = t);
                    },
                  ),
                ),
                if (_type == ItemType.event) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(_endTime == null ? '종료(선택)' : '종료 ${_hhmm(_endTime!)}'),
                      onPressed: () async {
                        final t = await _pickTime(_endTime ?? _startTime);
                        if (t != null) setState(() => _endTime = t);
                      },
                    ),
                  ),
                  if (_endTime != null)
                    IconButton(
                      tooltip: '종료 시각 지우기',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _endTime = null),
                    ),
                ],
              ]),
            const SizedBox(height: 12),
            if (_type == ItemType.event) ...[
              TextField(
                controller: _location,
                decoration: const InputDecoration(
                  labelText: '위치 (선택)',
                  hintText: '장소 이름이나 주소',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(children: [
              const Text('카테고리', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 8),
              const Text('여러 개 선택 가능 · 첫 번째가 대표 색',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final c in s.categories)
                FilterChip(
                  label: Text(c.name),
                  avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
                  selected: _cats.contains(c.id),
                  onSelected: (_) => _toggleCategory(c.id),
                ),
              ActionChip(
                avatar: const Icon(Icons.edit, size: 16),
                label: const Text('카테고리 편집'),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const CategoryManagerScreen())),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Text('색상', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 12),
              InkWell(
                onTap: () async {
                  final c = await pickColor(context, initial: _color ?? catColor.toARGB32());
                  if (c != null) setState(() => _color = c);
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(children: [
                    CircleAvatar(backgroundColor: _color != null ? Color(_color!) : catColor, radius: 11),
                    const SizedBox(width: 8),
                    Text(_color == null ? '카테고리 색' : '직접 지정'),
                  ]),
                ),
              ),
              if (_color != null)
                TextButton(
                    onPressed: () => setState(() => _color = null),
                    child: const Text('카테고리 색으로')),
            ]),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final choices = presetChoices(_start);
              final valid = choices.any((c) => c.$1 == _preset);
              return DropdownButtonFormField<RepeatPreset>(
                key: ValueKey('${_preset.name}|${_start.toIso8601String()}'),
                initialValue: valid ? _preset : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '반복'),
                items: [
                  for (final c in choices)
                    DropdownMenuItem(
                      value: c.$1,
                      child: Text(
                        c.$1 == RepeatPreset.custom && _preset == RepeatPreset.custom && _custom != null
                            ? '맞춤: ${_custom!.describe(_start)}'
                            : c.$2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _rollEvery > 0
                    ? null
                    : (v) async {
                        if (v == RepeatPreset.custom) {
                          await _editCustom();
                        } else if (v != null) {
                          setState(() {
                            _preset = v;
                            if (v != RepeatPreset.none) _end = null;
                          });
                        }
                      },
              );
            }),
            if (_rule != null && _rollEvery == 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  if (_preset == RepeatPreset.custom) ...[
                    const Icon(Icons.repeat, size: 16, color: Colors.white54),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_rule!.describe(_start),
                          style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ),
                    TextButton(onPressed: _editCustom, child: const Text('편집')),
                  ] else ...[
                    const Spacer(),
                    TextButton(onPressed: _editCustom, child: const Text('종료 조건 · 세부 설정')),
                  ],
                ]),
              ),
            if (_type == ItemType.todo) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('완료하면 다음 일정으로 이동'),
                subtitle: const Text('캘린더에는 하나만 보이고, 완료하면 날짜가 자동으로 넘어가. 약 먹기 같은 매일 확인용.',
                    style: TextStyle(fontSize: 12)),
                value: _rollEvery > 0,
                onChanged: (v) => setState(() {
                  _rollEvery = v ? 1 : 0;
                  if (v) _preset = RepeatPreset.none;
                }),
              ),
              if (_rollEvery > 0) ...[
                Row(children: [
                  const Text('매'),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _rollEvery,
                    items: [for (var n = 1; n <= 31; n++) DropdownMenuItem(value: n, child: Text('$n'))],
                    onChanged: (v) => setState(() => _rollEvery = v!),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<m.RollUnit>(
                    value: _rollUnit,
                    items: const [
                      DropdownMenuItem(value: m.RollUnit.day, child: Text('일')),
                      DropdownMenuItem(value: m.RollUnit.week, child: Text('주')),
                      DropdownMenuItem(value: m.RollUnit.month, child: Text('개월')),
                      DropdownMenuItem(value: m.RollUnit.year, child: Text('년')),
                    ],
                    onChanged: (v) => setState(() => _rollUnit = v!),
                  ),
                  const SizedBox(width: 8),
                  const Text('마다'),
                ]),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('완료한 날 기준')),
                    ButtonSegment(value: false, label: Text('예정일 기준')),
                  ],
                  selected: {_rollFromCompletion},
                  onSelectionChanged: (v) => setState(() => _rollFromCompletion = v.first),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _rollFromCompletion
                        ? '늦게 완료해도 완료한 날부터 다시 세어. (약 먹기에 알맞아)'
                        : '늦게 완료해도 원래 주기를 유지해. (월세, 정기 점검에 알맞아)',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            SegmentedButton<m.Visibility>(
              segments: const [
                ButtonSegment(
                    value: m.Visibility.private, icon: Icon(Icons.lock), label: Text('나만 보기')),
                ButtonSegment(
                    value: m.Visibility.shared, icon: Icon(Icons.people), label: Text('같이 보기')),
              ],
              selected: {_vis},
              onSelectionChanged: isOwner
                  ? (v) => setState(() {
                        _vis = v.first;
                        _visTouched = true;
                      })
                  : null,
            ),
            if (!isOwner)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${s.ownerName(widget.item!)}이(가) 만든 같이 보기 항목이라 공개 범위는 만든 사람만 바꿀 수 있어.',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: '메모', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(children: [
              if (widget.item != null && isOwner)
                TextButton(
                  onPressed: () async {
                    final s = context.read<Store>();
                    final item = widget.item!;
                    if (!item.isRecurring) {
                      await s.delete(item);
                    } else {
                      final scope = await _askDeleteScope(item);
                      if (scope == null) return;
                      await s.deleteRepeating(item, widget.day, scope);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
                ),
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('저장')),
            ]),
          ],
        ),
      ),
    );
  }
}
