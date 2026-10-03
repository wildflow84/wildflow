import 'package:flutter/material.dart';
import 'palette.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';

/// 공유 공간 구성원: 방장은 초대한 사람을 내보내거나, 내보낸 사람을 다시 받아줄 수 있다.
class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    return Scaffold(
      appBar: AppBar(title: const Text('구성원')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(children: [
            for (final uid in s.members)
              ListTile(
                leading: CircleAvatar(child: Text(_initial(s.names[uid] ?? '?'))),
                title: Text(uid == s.uid ? '${s.names[uid] ?? '나'} (나)' : (s.names[uid] ?? '상대')),
                subtitle: Text(uid == s.members.first ? '방장' : '초대받은 사람'),
                trailing: s.isHost && uid != s.uid
                    ? TextButton(
                        style: TextButton.styleFrom(foregroundColor: kRed),
                        onPressed: () => _confirmRemove(context, s, uid),
                        child: const Text('내보내기'),
                      )
                    : null,
              ),
            if (!s.isHost)
              Padding(
                padding: EdgeInsets.all(16),
                child: Text('초대받은 사람은 구성원을 내보낼 수 없어. 방장(공간을 만든 사람)만 할 수 있어.',
                    style: TextStyle(color: kMuted, fontSize: 12)),
              ),
            if (s.isHost && s.bannedNames.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 4),
                child: Text('내보낸 사람', style: TextStyle(color: kSubtle)),
              ),
              for (final e in s.bannedNames.entries)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_off_outlined)),
                  title: Text(e.value),
                  subtitle: const Text('초대 코드로 다시 들어올 수 없어'),
                  trailing: TextButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await s.allowMember(e.key);
                        messenger.showSnackBar(SnackBar(content: Text('${e.value}이(가) 다시 들어올 수 있어')));
                      } catch (err) {
                        messenger.showSnackBar(SnackBar(content: Text('처리하지 못했어: $err')));
                      }
                    },
                    child: const Text('다시 받기'),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }

  static String _initial(String n) => n.isEmpty ? '?' : String.fromCharCode(n.runes.first);

  Future<void> _confirmRemove(BuildContext context, Store s, String uid) async {
    final name = s.names[uid] ?? '상대';
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$name을(를) 내보낼까?'),
        content: Text('$name은(는) 더 이상 이 공간의 일정과 할 일을 볼 수 없고, 초대 코드로도 다시 들어올 수 없어.\n\n'
            '• $name이(가) 만든 같이 보기 항목은 남아\n'
            '• $name의 나만 보기 항목은 $name 것으로 남아 있어서 아무도 못 봐 (다시 받아주면 돌아와)\n'
            '• 맡겨둔 할 일의 담당은 비워져'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('내보내기'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await s.removeMember(uid);
      messenger.showSnackBar(SnackBar(content: Text('$name을(를) 내보냈어')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('내보내지 못했어: $e')));
    }
  }
}
