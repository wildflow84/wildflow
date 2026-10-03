import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/push.dart';
import '../data/store.dart';
import '../models/item.dart' as m;
import 'category_manager.dart';
import 'ics_import.dart';

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
          const _Header('내 정보'),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('닉네임'),
            subtitle: Text(s.myNickname.isEmpty ? '정하지 않음 (구글 이름으로 보여)' : '${s.myNickname} · 상대와 내가 만든 항목에 이 이름으로 보여'),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: () => _editNickname(context, s),
          ),
          const Divider(height: 32),
          const _Header('알림'),
          const _PushTile(),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('상대의 재촉 받기'),
            subtitle: const Text('끄면 상대가 재촉 버튼을 눌러도 알림이 안 가 (상대에게 꺼놨다고 알려줘)'),
            value: s.allowNudge,
            onChanged: (v) => s.setPref('allowNudge', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.share_outlined),
            title: const Text('새로 공유된 일정/할 일 알림'),
            subtitle: const Text('상대가 같이 보기로 새 항목을 만들거나 공유하면 알려줘'),
            value: s.notifyShared,
            onChanged: (v) => s.setPref('notifyShared', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.task_alt),
            title: const Text('같이 하는 할 일 완료 알림'),
            subtitle: const Text('상대가 같이 보기 할 일을 완료하면 알려줘'),
            value: s.notifyComplete,
            onChanged: (v) => s.setPref('notifyComplete', v),
          ),
          if (s.notifyComplete)
            SwitchListTile(
              secondary: const Icon(Icons.autorenew),
              title: const Text('반복 할 일 완료 알림도 받기'),
              subtitle: const Text('약 먹기처럼 자주 반복되는 건 기본으로 꺼져 있어'),
              value: s.notifyCompleteRepeating,
              onChanged: (v) => s.setPref('notifyCompleteRepeating', v),
            ),
          const Divider(height: 32),
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
          const _Header('가져오기'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('구글 캘린더에서 가져오기'),
            subtitle: const Text('구글 캘린더 설정 → 가져오기/내보내기 → 내보내기로 받은 .zip 또는 .ics 파일'),
            onTap: () => importFromGoogleCalendar(context),
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
            leading: const Icon(Icons.info_outline),
            title: const Text('앱 버전'),
            // CI가 빌드할 때 커밋 번호를 넣는다. 새로 배포됐는지 확인할 때 쓴다.
            subtitle: Text(const String.fromEnvironment('APP_VERSION', defaultValue: '개발 빌드')),
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

Future<void> _editNickname(BuildContext context, Store s) async {
  final ctl = TextEditingController(text: s.myNickname);
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('닉네임'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLength: Store.maxNicknameLength,
        decoration: const InputDecoration(hintText: '상대에게 보일 이름'),
        onSubmitted: (t) => Navigator.pop(ctx, t),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('저장')),
      ],
    ),
  );
  if (v != null && v.trim().isNotEmpty) await s.setNickname(v);
}

/// 이 기기에서 푸시 알림 받기 켜기/끄기
class _PushTile extends StatefulWidget {
  const _PushTile();

  @override
  State<_PushTile> createState() => _PushTileState();
}

class _PushTileState extends State<_PushTile> {
  PushState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await Push.state();
    if (mounted) setState(() => _state = s);
  }

  Future<void> _toggle() async {
    final repo = context.read<Store>().repo;
    setState(() => _busy = true);
    try {
      if (_state == PushState.on) {
        await Push.disable(repo);
      } else {
        final r = await Push.enable(repo);
        if (r == PushState.blocked && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('브라우저/기기에서 알림이 차단돼 있어. 사이트 설정에서 허용해줘')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('알림 설정 실패: $e')));
    }
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    final (sub, can) = switch (st) {
      null => ('확인 중…', false),
      PushState.unsupported => ('이 브라우저/기기는 푸시를 지원하지 않아', false),
      PushState.blocked => ('차단됨 · 브라우저 사이트 설정에서 알림을 허용해줘', false),
      PushState.on => ('켜짐 · 이 기기로 알림이 와', true),
      PushState.off => ('꺼짐 · 눌러서 켜기', true),
    };
    return ListTile(
      leading: const Icon(Icons.notifications_outlined),
      title: const Text('이 기기에서 알림 받기'),
      subtitle: Text(sub),
      trailing: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Switch(value: st == PushState.on, onChanged: can ? (_) => _toggle() : null),
      onTap: can && !_busy ? _toggle : null,
    );
  }
}
