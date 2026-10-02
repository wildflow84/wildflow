import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/item.dart' as m;
import 'category_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    return Scaffold(
      appBar: AppBar(title: const Text('설정'), backgroundColor: Colors.transparent),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          const _Header('새 일정 / 할 일의 기본 공개 범위'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<m.Visibility>(
              segments: const [
                ButtonSegment(
                    value: m.Visibility.private, icon: Icon(Icons.lock), label: Text('나만 보기')),
                ButtonSegment(
                    value: m.Visibility.shared, icon: Icon(Icons.people), label: Text('같이 보기')),
              ],
              selected: {s.defaultVisibility},
              onSelectionChanged: (v) => s.setDefaultVisibility(v.first),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '등록할 때 항목마다 바꿀 수 있어. 카테고리에 기본 공개 범위를 따로 정해두면 그게 우선이야.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          const _Header('카테고리'),
          for (final c in s.categories)
            ListTile(
              leading: CircleAvatar(backgroundColor: c.color, radius: 12),
              title: Text(c.name),
              subtitle: Text(c.defaultVisibility == null
                  ? '기본 공개 범위: 내 설정 따름'
                  : c.defaultVisibility == m.Visibility.private
                      ? '항상 나만 보기'
                      : '항상 같이 보기'),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () => showCategoryDialog(context, edit: c),
            ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('카테고리 추가'),
            onTap: () => showCategoryDialog(context),
          ),
          const Divider(height: 32),
          const _Header('공유 공간'),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('초대 코드 복사'),
            subtitle: const Text('상대에게 보내서 같은 공간에 참여하게 해'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: s.spaceId!));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('초대 코드를 복사했어')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('로그아웃'),
            onTap: () {
              Navigator.pop(context);
              s.repo.signOut();
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}
