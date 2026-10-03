import 'package:flutter/material.dart';
import 'palette.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/item.dart';

enum CompleteChoice { cancel, anyway, checkAll }

/// 체크리스트가 남은 할 일을 완료하려 할 때 확인한다. 남은 게 없으면 바로 anyway.
Future<CompleteChoice> confirmIncompleteChecklist(BuildContext context, Item item, DateTime day) async {
  final left = item.checksLeftOn(day);
  if (left == 0) return CompleteChoice.anyway;
  final r = await showDialog<CompleteChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('체크리스트가 남았어'),
      content: Text('"${item.title}"에 아직 체크 안 한 항목이 $left개 있어.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, CompleteChoice.cancel), child: const Text('돌아가기')),
        TextButton(onPressed: () => Navigator.pop(ctx, CompleteChoice.anyway), child: const Text('그냥 완료')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, CompleteChoice.checkAll), child: const Text('모두 체크하고 완료')),
      ],
    ),
  );
  return r ?? CompleteChoice.cancel;
}

/// 목록에서 바로 체크할 수 있는 체크리스트 (제목을 누르면 편집 없이 체크만 바뀐다).
class ChecklistInline extends StatelessWidget {
  final Item item;
  final DateTime day;
  final bool canEdit;
  const ChecklistInline({super.key, required this.item, required this.day, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    final s = context.read<Store>();
    final list = item.checklistOn(day); // 반복 항목은 이 날짜(회차)의 체크
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 0, 16, 6),
      child: Column(children: [
        for (var i = 0; i < list.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: canEdit ? () => s.setCheck(item, day, i, !list[i].done) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Icon(list[i].done ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 18, color: list[i].done ? kGreen : kMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(list[i].text,
                      style: TextStyle(
                          fontSize: 13,
                          color: list[i].done ? kFaint : null,
                          decoration: list[i].done ? TextDecoration.lineThrough : null)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// 등록 화면의 체크리스트 편집: 한 줄씩 추가, 여러 줄 붙여넣기(장보기 목록) 지원.
class ChecklistEditor extends StatefulWidget {
  final List<CheckEntry> initial;
  final ValueChanged<List<CheckEntry>> onChanged;
  /// 반복 항목은 목록만 정하고(체크는 회차마다 따로) 체크 상자는 숨긴다.
  final bool showChecks;
  const ChecklistEditor({super.key, required this.initial, required this.onChanged, this.showChecks = true});

  @override
  State<ChecklistEditor> createState() => _ChecklistEditorState();
}

class _ChecklistEditorState extends State<ChecklistEditor> {
  late List<CheckEntry> _items = [...widget.initial];
  final _add = TextEditingController();
  final _addFocus = FocusNode();

  void _emit() => widget.onChanged([..._items]);

  void _addFromField() {
    // 줄바꿈으로 붙여넣은 여러 줄은 각각 한 항목으로
    final lines = _add.text.split('\n').map((e) => e.replaceFirst(RegExp(r'^\s*[-•*·]\s*'), '').trim()).where((e) => e.isNotEmpty);
    if (lines.isEmpty) return;
    setState(() => _items = [..._items, for (final l in lines) CheckEntry(l)]);
    _add.clear();
    _emit();
    _addFocus.requestFocus(); // 이어서 바로 다음 항목을 입력
  }

  @override
  void dispose() {
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _items.where((c) => !c.done).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.checklist, size: 18, color: kSubtle),
        const SizedBox(width: 6),
        Text('체크리스트', style: TextStyle(color: kSubtle)),
        if (_items.isNotEmpty && widget.showChecks) Text('  ${_items.length - left}/${_items.length}', style: TextStyle(color: kMuted, fontSize: 12)),
        const Spacer(),
        if (widget.showChecks && _items.any((c) => c.done))
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () {
              setState(() => _items = [for (final c in _items) if (!c.done) c]);
              _emit();
            },
            child: const Text('체크한 것 지우기'),
          ),
      ]),
      if (!widget.showChecks)
        Padding(
          padding: EdgeInsets.only(top: 2, bottom: 4),
          child: Text('반복 일정은 날짜(회차)마다 따로 체크해', style: TextStyle(fontSize: 12, color: kMuted)),
        ),
      for (var i = 0; i < _items.length; i++)
        Row(children: [
          if (!widget.showChecks) Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.circle, size: 6, color: kMuted)),
          if (widget.showChecks)
          Checkbox(
            visualDensity: VisualDensity.compact,
            value: _items[i].done,
            onChanged: (v) {
              setState(() => _items[i] = _items[i].copyWith(done: v ?? false));
              _emit();
            },
          ),
          Expanded(
            child: TextFormField(
              key: ValueKey('c$i${_items[i].text}'),
              initialValue: _items[i].text,
              style: TextStyle(
                  decoration: _items[i].done ? TextDecoration.lineThrough : null,
                  color: _items[i].done ? kFaint : null),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none),
              onChanged: (t) {
                _items[i] = _items[i].copyWith(text: t);
                _emit();
              },
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '삭제',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              setState(() => _items.removeAt(i));
              _emit();
            },
          ),
        ]),
      TextField(
        controller: _add,
        focusNode: _addFocus,
        minLines: 1,
        maxLines: 6,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _addFromField(),
        onChanged: (t) {
          if (t.contains('\n') && t.trim().isNotEmpty) _addFromField();
        },
        decoration: InputDecoration(
          hintText: '항목 추가 (여러 줄 붙여넣기 가능)',
          prefixIcon: const Icon(Icons.add, size: 20),
          suffixIcon: IconButton(icon: const Icon(Icons.keyboard_return, size: 18), onPressed: _addFromField),
        ),
      ),
    ]);
  }
}
