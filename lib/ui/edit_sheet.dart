import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/place_photo.dart';
import '../data/place_search.dart';
import '../data/store.dart';
import '../models/item.dart' as m;
import '../models/item.dart' show Item, ItemType, RepeatDelete, dateOnly, hasEndTime, repeatFor;
import '../models/recurrence.dart';
import 'category_manager.dart';
import 'checklist.dart';
import 'color_picker.dart';
import 'date_picker.dart';
import 'lunar_picker.dart';
import '../models/lunar.dart' show solarToLunar;
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
  late List<m.CheckEntry> _checklist = [...?widget.item?.checklist];
  late final _location = TextEditingController(text: widget.item?.location);
  // 장소 검색으로 고른 좌표 (위치 문구를 직접 고치면 해제)
  late double? _lat = widget.item?.lat;
  late double? _lng = widget.item?.lng;
  late bool _overseas = widget.item?.overseas ?? false;
  late String? _pickedLabel = widget.item?.lat != null ? widget.item!.location : null;
  List<Place> _places = const [];
  bool _searching = false;
  String? _searchError;
  Timer? _searchDebounce;
  Timer? _photoDebounce;
  late String? _photoUrl = widget.item?.photoUrl;
  late DateTime _start = widget.item?.start ?? dateOnly(widget.day);
  late DateTime? _end = widget.item?.end == null ? null : dateOnly(widget.item!.end!);
  late bool _allDay = widget.item?.allDay ?? true;
  late TimeOfDay _startTime = widget.item != null && !widget.item!.allDay
      ? TimeOfDay(hour: widget.item!.start.hour, minute: widget.item!.start.minute)
      : const TimeOfDay(hour: 9, minute: 0);
  // 직접 고르거나 지운 적이 없으면, 시작 시각을 바꿀 때 종료를 시작 + 1시간으로 맞춘다
  late bool _endTouched = widget.item != null;
  late TimeOfDay? _endTime = widget.item != null && hasEndTime(widget.item!)
      ? TimeOfDay(hour: widget.item!.end!.hour, minute: widget.item!.end!.minute)
      : null;
  late List<String> _cats; // 항상 하나 (이전 버전에서 여러 개였던 항목은 첫 번째만 쓴다)
  late m.Visibility _vis;
  late bool _visTouched = widget.item != null; // 직접 바꾸면 카테고리 기본값으로 덮어쓰지 않는다
  late int? _color = widget.item?.color; // null이면 카테고리 색
  // 반복: 빠른 선택(구글 캘린더처럼 시작 날짜에서 값이 정해짐) 또는 맞춤 규칙
  late RepeatPreset _preset = presetOf(widget.item?.rollRule ?? widget.item?.effectiveRule, widget.item?.start ?? _start);
  late Recurrence? _custom = widget.item?.rollRule ?? widget.item?.effectiveRule;
  // 이동형: 완료하면 날짜가 다음 일정으로 넘어간다. 반복 규칙(위 "반복")을 고르면 그 규칙대로,
  // 고르지 않으면 아래 "매 N일/주/개월/년마다"로 옮긴다. 기준은 예정일이 기본.
  late bool _rolling = widget.item?.isRolling ?? false;
  late int _rollEvery = (widget.item?.rollEvery ?? 0) > 0 ? widget.item!.rollEvery : 1;
  late m.RollUnit _rollUnit = widget.item?.rollUnit ?? m.RollUnit.day;
  late bool _rollFromCompletion = widget.item?.rollFromCompletion ?? false;

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
    _cats = [widget.item?.categories.first ?? s.categories.first.id];
    _vis = widget.item?.visibility ?? s.visibilityFor(_cats);
  }

  /// 카테고리는 하나만 고른다.
  void _selectCategory(String id) {
    final s = context.read<Store>();
    setState(() {
      _cats = [id];
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
        _end = d.isAtSameMomentAs(_start) || d.isBefore(_start) ? null : d; // null = 시작일과 같은 날
      } else {
        _start = d;
        if (_end != null && _end!.isBefore(d)) _end = null;
      }
    });
  }

  Future<void> _pickLunar() async {
    final d = await pickLunarDate(context, initial: _start);
    if (d == null) return;
    setState(() {
      _start = d;
      if (_end != null && _end!.isBefore(d)) _end = null;
    });
  }

  /// 시작 + 1시간 (23시대는 같은 날 23:59로 제한)
  static TimeOfDay _plusHour(TimeOfDay t) =>
      t.hour >= 23 ? const TimeOfDay(hour: 23, minute: 59) : TimeOfDay(hour: t.hour + 1, minute: t.minute);

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
    // 이동형(할 일만): 반복 규칙은 "일반 반복"이 아니라 이동 규칙으로 저장한다
    final isRoll = _type == ItemType.todo && _rolling;
    final rollRule = isRoll ? _rule : null; // 규칙형 이동
    final rule = isRoll ? null : _rule;
    final startRule = rollRule ?? rule;
    var startDate = startRule == null ? dateOnly(_start) : startRule.firstOnOrAfter(_start);
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
      checklist: [for (final c in _checklist) if (c.text.trim().isNotEmpty) c.copyWith(text: c.text.trim())],
      location: _type == ItemType.event ? _location.text.trim() : '', // 위치는 일정만
      lat: _type == ItemType.event ? _lat : null,
      lng: _type == ItemType.event ? _lng : null,
      overseas: _type == ItemType.event && _overseas,
      clearCoords: _type != ItemType.event || _lat == null,
      photoUrl: _type == ItemType.event ? _photoUrl : null,
      clearPhoto: _type != ItemType.event || _photoUrl == null,
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
      // 간격형 이동은 규칙을 고르지 않았을 때만
      rollEvery: isRoll && rollRule == null ? _rollEvery : 0,
      rollUnit: _rollUnit,
      rollFromCompletion: _rollFromCompletion,
      rollRule: rollRule,
      clearRollRule: rollRule == null,
    ));
    if (mounted) Navigator.pop(context);
  }

  void _onLocationChanged(String text) {
    if (_pickedLabel != null && text != _pickedLabel) {
      // 고른 장소 문구를 직접 고치면 좌표는 더 이상 맞지 않는다
      _pickedLabel = null;
      _lat = null;
      _lng = null;
      _overseas = false;
    }
    _schedulePhoto(text);
    _searchDebounce?.cancel();
    if (!placeSearchAvailable || text.trim().length < 2) {
      setState(() {
        _places = const [];
        _searchError = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      try {
        final r = await searchPlaces(text);
        if (!mounted || _location.text != text) return;
        setState(() {
          _places = r.take(6).toList();
          _searchError = null;
        });
      } catch (_) {
        if (mounted) setState(() => _searchError = '장소 검색을 못 했어 (직접 입력해도 돼)');
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  /// 위치 문구가 바뀌면 잠시 뒤 그 장소의 사진을 찾아 미리 보여준다 (못 찾으면 사진 없음)
  void _schedulePhoto(String text) {
    _photoDebounce?.cancel();
    if (text.trim().length < 2) {
      if (_photoUrl != null) setState(() => _photoUrl = null);
      return;
    }
    _photoDebounce = Timer(const Duration(milliseconds: 800), () async {
      final url = await fetchPlacePhoto(text);
      if (!mounted || _location.text != text) return;
      setState(() => _photoUrl = url);
    });
  }

  void _pickPlace(Place p) {
    _schedulePhoto(p.label);
    setState(() {
      _pickedLabel = p.label;
      _location.text = p.label;
      _lat = p.lat;
      _lng = p.lng;
      _overseas = p.overseas;
      _places = const [];
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _photoDebounce?.cancel();
    super.dispose();
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
                        child: Text(df.format(_end ?? _start)))), // 기본은 시작일과 같은 날
              ],
            ]),
            // 음력: 고른 날짜의 음력 표시 + 음력으로 날짜 고르기 (생일/기일 등)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.nights_stay_outlined, size: 16),
                label: Text(() {
                  final l = solarToLunar(_start);
                  return l == null ? '음력으로 고르기' : '음력 ${l.monthLabel} ${l.day}일 · 음력으로 고르기';
                }()),
                onPressed: _pickLunar,
              ),
            ),
            const SizedBox(height: 4),
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
                onChanged: (v) => setState(() {
                  _allDay = v;
                  if (!v && !_endTouched && _endTime == null) _endTime = _plusHour(_startTime);
                }),
              ),
            if (!_allDay)
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('${_type == ItemType.todo ? '마감' : '시작'} ${_hhmm(_startTime)}'),
                    onPressed: () async {
                      final t = await _pickTime(_startTime);
                      if (t != null) {
                        setState(() {
                          _startTime = t;
                          if (_type == ItemType.event && !_endTouched) _endTime = _plusHour(t);
                        });
                      }
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
                        if (t != null) {
                          setState(() {
                            _endTime = t;
                            _endTouched = true;
                          });
                        }
                      },
                    ),
                  ),
                  if (_endTime != null)
                    IconButton(
                      tooltip: '종료 시각 지우기',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _endTime = null;
                        _endTouched = true; // 일부러 지웠으면 다시 채우지 않는다
                      }),
                    ),
                ],
              ]),
            const SizedBox(height: 12),
            if (_type == ItemType.event) ...[
              TextField(
                controller: _location,
                onChanged: _onLocationChanged,
                decoration: InputDecoration(
                  labelText: '위치 (선택)',
                  hintText: placeSearchAvailable ? '장소 이름이나 주소를 검색해' : '장소 이름이나 주소',
                  prefixIcon: Icon(_lat != null ? Icons.place : Icons.place_outlined),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : null,
                ),
              ),
              if (_lat != null)
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 12),
                  child: Text('📍 좌표가 저장됐어 (지도/출발 시간 계산용)',
                      style: TextStyle(fontSize: 12, color: Colors.white54)),
                ),
              if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 12),
                  child: Text(_searchError!, style: const TextStyle(fontSize: 12, color: Colors.orangeAccent)),
                ),
              if (_photoUrl != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(children: [
                      Image.network(_photoUrl!,
                          height: 120, width: double.infinity, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: IconButton.filledTonal(
                          tooltip: '사진 빼기',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() => _photoUrl = null),
                        ),
                      ),
                    ]),
                  ),
                ),
              for (final p in _places)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const Icon(Icons.place_outlined, size: 20),
                  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: p.address.isEmpty
                      ? null
                      : Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _pickPlace(p),
                ),
              const SizedBox(height: 12),
            ],
            const Text('카테고리', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final c in s.categories)
                ChoiceChip(
                  label: Text(c.name),
                  avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
                  selected: _cats.first == c.id,
                  onSelected: (_) => _selectCategory(c.id),
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
                onChanged: (v) async {
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
            if (_rule != null)
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
                subtitle: const Text('캘린더에는 다음 1개만 보이고, 완료하면 날짜가 자동으로 넘어가. 약 먹기, 정기 점검 같은 확인용.',
                    style: TextStyle(fontSize: 12)),
                value: _rolling,
                onChanged: (v) => setState(() => _rolling = v),
              ),
              if (_rolling && _rule != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.autorenew, size: 16, color: Colors.white54),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '"${_rule!.describe(_start)}" 규칙대로, 완료하면 다음 날짜로 이동해.',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ),
                  ]),
                ),
              if (_rolling && _rule == null) ...[
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('위에서 반복(예: 매주 목요일)을 고르면 그 규칙대로 이동하고, 고르지 않으면 아래 간격으로 이동해.',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                ),
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
                    ButtonSegment(value: false, label: Text('예정일 기준')),
                    ButtonSegment(value: true, label: Text('완료한 날 기준')),
                  ],
                  selected: {_rollFromCompletion},
                  onSelectionChanged: (v) => setState(() => _rollFromCompletion = v.first),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _rollFromCompletion
                        ? '늦게 완료하면 완료한 날부터 다시 세어. (약 먹기에 알맞아)'
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
            if (widget.item != null && widget.item!.visibility == m.Visibility.shared)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  const Icon(Icons.person_outline, size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  Text('만든 사람 · ${s.ownerLabel(widget.item!)}',
                      style: const TextStyle(fontSize: 12, color: Colors.white60)),
                ]),
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
            const SizedBox(height: 12),
            ChecklistEditor(initial: _checklist, onChanged: (l) => _checklist = l),
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
