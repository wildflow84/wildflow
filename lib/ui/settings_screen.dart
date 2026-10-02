import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/item.dart' as m;
import 'category_manager.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
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
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('카테고리 관리'),
            subtitle: Text('${s.categories.length}개 · 추가, 수정, 삭제, 순서 변경'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CategoryManagerScreen())),
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
        ),
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
