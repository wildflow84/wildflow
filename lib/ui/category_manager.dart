import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/item.dart' as m;
import 'category_dialog.dart';

/// 카테고리 관리: 추가 / 수정 / 삭제 / 드래그로 순서 변경.
class CategoryManagerScreen extends StatelessWidget {
  const CategoryManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('카테고리 관리'),
        actions: [
          TextButton.icon(
            onPressed: () => showCategoryDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('추가'),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            '항목에는 카테고리를 하나 붙이고, 그 색으로 표시돼. 끌어서 순서를 바꾸고, 눌러서 수정해.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: s.categories.length,
            onReorderItem: (from, to) {
              final list = [...s.categories];
              list.insert(to, list.removeAt(from));
              s.reorderCategories(list);
            },
            itemBuilder: (context, i) {
              final c = s.categories[i];
              return ListTile(
                key: ValueKey(c.id),
                leading: CircleAvatar(backgroundColor: c.color, radius: 12),
                title: Text(c.name),
                subtitle: Text(c.defaultVisibility == null
                    ? '기본 공개 범위: 내 설정 따름'
                    : c.defaultVisibility == m.Visibility.private
                        ? '항상 나만 보기'
                        : '항상 같이 보기'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: '수정',
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => showCategoryDialog(context, edit: c),
                  ),
                  IconButton(
                    tooltip: '삭제',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => confirmDeleteCategory(context, c),
                  ),
                  const SizedBox(width: 24), // 드래그 핸들 자리
                ]),
                onTap: () => showCategoryDialog(context, edit: c),
              );
            },
          ),
        ),
      ]),
        ),
      ),
    );
  }
}
