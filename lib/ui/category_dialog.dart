import 'package:flutter/material.dart';
import 'palette.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/category.dart';
import '../models/item.dart' as m;
import 'color_picker.dart';

/// 카테고리 만들기/수정 대화상자. 저장하면 카테고리 id를 돌려준다. (삭제하거나 취소하면 null)
Future<String?> showCategoryDialog(BuildContext context, {Category? edit}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CategoryDialog(edit: edit),
  );
}

class _CategoryDialog extends StatefulWidget {
  final Category? edit;
  const _CategoryDialog({this.edit});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.edit?.name);
  late int _color = widget.edit?.colorValue ?? colorPalette[DateTime.now().millisecond % colorPalette.length];
  late m.Visibility? _vis = widget.edit?.defaultVisibility;

  @override
  Widget build(BuildContext context) {
    final s = context.read<Store>();
    return AlertDialog(
      title: Text(widget.edit == null ? '새 카테고리' : '카테고리 수정'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '이름', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Text('색상'),
            const SizedBox(height: 8),
            ColorChooser(value: _color, onChanged: (v) => setState(() => _color = v)),
            const SizedBox(height: 16),
            DropdownButtonFormField<m.Visibility?>(
              initialValue: _vis,
              decoration: const InputDecoration(
                  labelText: '이 카테고리의 기본 공개 범위', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: null, child: Text('내 기본 설정을 따름')),
                DropdownMenuItem(value: m.Visibility.private, child: Text('항상 나만 보기')),
                DropdownMenuItem(value: m.Visibility.shared, child: Text('항상 같이 보기')),
              ],
              onChanged: (v) => setState(() => _vis = v),
            ),
          ]),
        ),
      ),
      actions: [
        if (widget.edit != null)
          TextButton(
            onPressed: () async {
              if (await confirmDeleteCategory(context, widget.edit!) && context.mounted) {
                Navigator.pop(context);
              }
            },
            child: Text('삭제', style: TextStyle(color: kRed)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: () async {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final base = widget.edit ??
                Category(id: '', name: name, colorValue: _color, order: s.categories.length);
            final id = await s.saveCategory(base.copyWith(
              name: name,
              colorValue: _color,
              defaultVisibility: _vis,
              clearVisibility: _vis == null,
            ));
            if (context.mounted) Navigator.pop(context, id);
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// 삭제 확인 후 삭제. 삭제했으면 true.
Future<bool> confirmDeleteCategory(BuildContext context, Category c) async {
  final s = context.read<Store>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('"${c.name}" 삭제'),
      content: const Text('이 카테고리가 붙은 항목은 지워지지 않아. 다른 카테고리가 있으면 그걸로, 없으면 기본 색으로 보여.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
      ],
    ),
  );
  if (ok != true) return false;
  await s.deleteCategory(c);
  return true;
}
