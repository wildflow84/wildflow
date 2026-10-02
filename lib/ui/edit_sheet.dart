import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/item.dart' as m;
import '../models/item.dart' show Item, ItemType, Repeat, dateOnly;
import 'category_dialog.dart';
import 'color_picker.dart';

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
  late DateTime _start = widget.item?.start ?? dateOnly(widget.day);
  late DateTime? _end = widget.item?.end;
  late String _category;
  late m.Visibility _vis;
  late bool _visTouched = widget.item != null; // 직접 바꾸면 카테고리 기본값으로 덮어쓰지 않는다
  late int? _color = widget.item?.color; // null이면 카테고리 색
  late Repeat _repeat = widget.item?.repeat ?? Repeat.none;

  static const _repeatLabels = {
    Repeat.none: '반복 안 함',
    Repeat.daily: '매일',
    Repeat.weekly: '매주',
    Repeat.monthly: '매월',
    Repeat.yearly: '매년',
  };

  @override
  void initState() {
    super.initState();
    final s = context.read<Store>();
    _category = widget.item?.category ?? s.categories.first.id;
    _vis = widget.item?.visibility ?? s.visibilityFor(_category);
  }

  void _selectCategory(String id) {
    final s = context.read<Store>();
    setState(() {
      _category = id;
      if (!_visTouched) _vis = s.visibilityFor(id);
    });
  }

  Future<void> _pick(bool isEnd) async {
    final init = isEnd ? (_end ?? _start) : _start;
    final d = await showDatePicker(
        context: context,
        initialDate: init,
        firstDate: DateTime(1901),
        lastDate: DateTime(2200, 12, 31));
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

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    final s = context.read<Store>();
    final base = widget.item ??
        Item(id: '', type: _type, title: '', start: _start, ownerUid: s.uid);
    await s.save(base.copyWith(
      type: _type,
      title: _title.text.trim(),
      note: _note.text.trim(),
      start: _start,
      end: _end,
      clearEnd: _end == null,
      category: _category,
      color: _color,
      clearColor: _color == null,
      visibility: _vis,
      repeat: _repeat,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final df = DateFormat('y.M.d (E)', 'ko');
    final catColor = s.categoryOf(_category).color;
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
              Expanded(child: OutlinedButton(onPressed: () => _pick(false), child: Text(df.format(_start)))),
              if (_type == ItemType.event && _repeat == Repeat.none) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('~')),
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => _pick(true),
                        child: Text(_end == null ? '종료일(선택)' : df.format(_end!)))),
              ],
            ]),
            const SizedBox(height: 12),
            const Text('카테고리', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final c in s.categories)
                ChoiceChip(
                  label: Text(c.name),
                  avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
                  selected: _category == c.id,
                  onSelected: (_) => _selectCategory(c.id),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('새 카테고리'),
                onPressed: () async {
                  final id = await showCategoryDialog(context);
                  if (id != null && mounted) _selectCategory(id);
                },
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
            DropdownButtonFormField<Repeat>(
              initialValue: _repeat,
              decoration: const InputDecoration(labelText: '반복', border: OutlineInputBorder()),
              items: [
                for (final e in _repeatLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() {
                _repeat = v!;
                if (v != Repeat.none) _end = null;
              }),
            ),
            const SizedBox(height: 12),
            SegmentedButton<m.Visibility>(
              segments: const [
                ButtonSegment(
                    value: m.Visibility.private, icon: Icon(Icons.lock), label: Text('나만 보기')),
                ButtonSegment(
                    value: m.Visibility.shared, icon: Icon(Icons.people), label: Text('같이 보기')),
              ],
              selected: {_vis},
              onSelectionChanged: (v) => setState(() {
                _vis = v.first;
                _visTouched = true;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: '메모', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(children: [
              if (widget.item != null)
                TextButton(
                  onPressed: () async {
                    await context.read<Store>().delete(widget.item!);
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
