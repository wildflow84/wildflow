
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'palette.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/push.dart';
import '../data/store.dart';
import '../models/item.dart' as m;
import 'category_manager.dart';
import 'members_screen.dart';
import 'subscriptions.dart';

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
            title: Text(s.myNickname.isEmpty ? '닉네임' : '닉네임 · ${s.myNickname}'),
            subtitle: Text(s.myNickname.isEmpty ? '정하지 않음 (구글 이름으로 보여)' : '상대 화면과 내가 만든 항목에 이 이름으로 보여'),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: () => _editNickname(context, s),
          ),
          const Divider(height: 32),
          const _Header('화면'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto), label: Text('기기 설정')),
                ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_outlined), label: Text('밝게')),
                ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_outlined), label: Text('어둡게')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => s.setPref('themeMode', v.first),
            ),
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
            secondary: const Icon(Icons.alarm),
            title: const Text('일정/할 일 알림'),
            subtitle: const Text('등록할 때 정해둔 시각(정각, 30분 전 등)에 알려줘. 같이 보기 항목은 상대에게도 가'),
            value: s.notifyReminder,
            onChanged: (v) => s.setPref('notifyReminder', v),
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
          if (!kIsWeb) ...[
            ListTile(
              leading: const Icon(Icons.my_location_outlined),
              title: const Text('위치 허용 (출발 시간 알림)'),
              subtitle: const Text('앱을 안 열어도 위치를 갱신하려면 "항상 허용"으로 바꿔줘'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _askLocation(context),
            ),
            const Divider(height: 32),
          ],
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
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '등록할 때 항목마다 바꿀 수 있어. 카테고리에 기본 공개 범위를 따로 정해두면 그게 우선이야.',
              style: TextStyle(color: kMuted, fontSize: 12),
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
          const _Header('구독'),
          ListTile(
            leading: const Icon(Icons.rss_feed),
            title: const Text('일정 구독'),
            subtitle: const Text('아스날 경기, 드라마 방영 일정 등 캘린더 주소(.ics)를 자동으로 받아와'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionsScreen())),
          ),
          const Divider(height: 32),
          const _Header('공유 공간'),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('구성원'),
            subtitle: Text(s.isHost ? '초대한 사람을 내보내거나 다시 받을 수 있어' : '공간 구성원 보기'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MembersScreen())),
          ),
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

/// 위치 권한을 요청하고, "항상 허용"이 아니면 설정 화면으로 안내한다.
/// 안드로이드는 "항상 허용"을 앱 안에서 바로 줄 수 없어서 설정에서 직접 골라야 한다.
Future<void> _askLocation(BuildContext context) async {
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (!context.mounted) return;
  if (p == LocationPermission.always) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 항상 허용돼 있어')));
    return;
  }
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('위치를 "항상 허용"으로'),
      content: Text(p == LocationPermission.whileInUse || p == LocationPermission.deniedForever
          ? '지금은 앱을 쓰는 동안만 위치를 쓸 수 있어. 앱을 안 열어도 출발 시간을 맞추려면 설정 → 위치(권한)에서 "항상 허용"을 골라줘.'
          : '위치 권한이 필요해. 설정 → 위치(권한)에서 허용해줘.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('나중에')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('설정 열기')),
      ],
    ),
  );
  if (go == true) await Geolocator.openAppSettings();
}
