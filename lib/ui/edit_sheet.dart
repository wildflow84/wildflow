import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/item.dart' as m;
import '../models/item.dart' show Item, ItemType, Repeat, dateOnly;
import 'categories.dart';

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
  late String _category = widget.item?.category ?? 'default';
  late m.Visibility _vis = widget.item?.visibility ?? m.Visibility.shared;
  late Repeat _repeat = widget.item?.repeat ?? Repeat.none;

  static const _repeatLabels = {
    Repeat.none: '반복 안 함',
    Repeat.daily: '매일',
    Repeat.weekly: '매주',
    Repeat.monthly: '매월',
    Repeat.yearly: '매년',
  };

  Future<void> _pick(bool isEnd) async {
    final init = isEnd ? (_end ?? _start) : _start;
    final d = await showDatePicker(
        context: context,
        initialDate: init,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
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
      visibility: _vis,
      repeat: _repeat,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('y.M.d (E)', 'ko');
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
            Wrap(spacing: 8, children: [
              for (final c in categories)
                ChoiceChip(
                  label: Text(c.label),
                  avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
                  selected: _category == c.id,
                  onSelected: (_) => setState(() => _category = c.id),
                ),
            ]),
            const SizedBox(height: 12),
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('프라이빗 (나만 보기)'),
              secondary: Icon(_vis == m.Visibility.private ? Icons.lock : Icons.people),
              value: _vis == m.Visibility.private,
              onChanged: (v) => setState(
                  () => _vis = v ? m.Visibility.private : m.Visibility.shared),
            ),
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
