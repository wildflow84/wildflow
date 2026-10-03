import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctionsException;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/category.dart' show subscriptionCategoryId;
import '../models/item.dart' as m;
import '../models/subscription.dart';

/// 일정 구독 목록과 추가/새로고침/삭제
class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    return Scaffold(
      appBar: AppBar(title: const Text('일정 구독')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('구독 추가'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: StreamBuilder<List<Subscription>>(
            stream: s.repo.watchSubscriptions(s.spaceId!),
            builder: (context, snap) {
              final subs = snap.data ?? const [];
              return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    '캘린더 주소(.ics)를 등록하면 서버가 12시간마다 새로 받아와서 일정에 넣어줘. 킥오프 시간이 바뀌면 자동으로 반영돼.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                if (subs.isEmpty && snap.connectionState != ConnectionState.waiting)
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('아직 구독이 없어'))),
                for (final sub in subs) _SubTile(sub: sub),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final s = context.read<Store>();
    final messenger = ScaffoldMessenger.of(context);
    final sub = await showDialog<Subscription>(context: context, builder: (_) => _AddDialog(store: s));
    if (sub == null) return;
    try {
      final id = await s.repo.addSubscription(s.spaceId!, sub);
      messenger.showSnackBar(const SnackBar(content: Text('일정을 받아오는 중이야…')));
      final r = await s.repo.syncSubscription(s.spaceId!, id);
      messenger.showSnackBar(SnackBar(content: Text('${r['count']}개 일정을 가져왔어')));
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message ?? '가져오지 못했어')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('가져오지 못했어: $e')));
    }
  }
}

class _SubTile extends StatelessWidget {
  final Subscription sub;
  const _SubTile({required this.sub});

  @override
  Widget build(BuildContext context) {
    final s = context.read<Store>();
    final f = DateFormat('M월 d일 HH:mm', 'ko');
    final status = sub.error != null
        ? '오류 · ${sub.error}'
        : sub.lastSyncAt == null
            ? '아직 받아오지 않았어'
            : '${sub.lastCount ?? 0}개 · ${f.format(sub.lastSyncAt!)} 동기화';
    return ListTile(
      leading: Icon(Icons.rss_feed, color: sub.error != null ? Colors.orangeAccent : null),
      title: Text(sub.name),
      subtitle: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: sub.error != null ? Colors.orangeAccent : null)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          final messenger = ScaffoldMessenger.of(context);
          if (v == 'sync') {
            try {
              final r = await s.repo.syncSubscription(s.spaceId!, sub.id);
              messenger.showSnackBar(SnackBar(content: Text('${r['count']}개 일정으로 새로 고쳤어')));
            } on FirebaseFunctionsException catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(e.message ?? '새로 고치지 못했어')));
            }
          } else if (v == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('"${sub.name}" 구독 삭제'),
                content: const Text('이 구독으로 들어온 일정도 같이 지워져.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
                ],
              ),
            );
            if (ok == true) {
              await s.repo.removeSubscription(s.spaceId!, sub.id);
              messenger.showSnackBar(const SnackBar(content: Text('구독을 지웠어')));
            }
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'sync', child: Text('지금 새로 고침')),
          PopupMenuItem(value: 'delete', child: Text('구독 삭제')),
        ],
      ),
    );
  }
}

class _AddDialog extends StatefulWidget {
  final Store store;
  const _AddDialog({required this.store});

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  late m.Visibility _vis = widget.store.defaultVisibility;

  bool get _valid {
    final u = _url.text.trim();
    return _name.text.trim().isNotEmpty && (u.startsWith('https://') || u.startsWith('webcal://'));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return AlertDialog(
      title: const Text('일정 구독 추가'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('자주 쓰는 구독', style: TextStyle(color: Colors.white70)),
            Wrap(spacing: 8, children: [
              for (final p in subscriptionPresets)
                ActionChip(
                  label: Text(p.$1),
                  onPressed: () => setState(() {
                    _name.text = p.$1.replaceAll(RegExp(r' \(.*\)'), '');
                    _url.text = p.$2;
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: '이름'), onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: const InputDecoration(labelText: '캘린더 주소 (https://… .ics)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SegmentedButton<m.Visibility>(
              segments: const [
                ButtonSegment(value: m.Visibility.private, icon: Icon(Icons.lock), label: Text('나만')),
                ButtonSegment(value: m.Visibility.shared, icon: Icon(Icons.people), label: Text('같이')),
              ],
              selected: {_vis},
              onSelectionChanged: (v) => setState(() => _vis = v.first),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(
                  context,
                  Subscription(
                      id: '',
                      name: _name.text.trim(),
                      url: _url.text.trim(),
                      categoryId: subscriptionCategoryId,
                      visibility: _vis,
                      ownerUid: s.uid))
              : null,
          child: const Text('추가'),
        ),
      ],
    );
  }
}
