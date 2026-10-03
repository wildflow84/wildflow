import 'package:flutter/material.dart';
import 'palette.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';

/// 처음 로그인했을 때: 새 공유 공간을 만들거나, 상대가 준 코드로 참여.
class SpaceScreen extends StatefulWidget {
  const SpaceScreen({super.key});

  @override
  State<SpaceScreen> createState() => _SpaceScreenState();
}

class _SpaceScreenState extends State<SpaceScreen> {
  final _code = TextEditingController();
  String? _err;

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      final t = '$e';
      setState(() => _err = t.contains('permission-denied')
          ? '이 공간에는 들어갈 수 없어. 코드가 틀렸거나, 이미 2명이거나, 방장이 허용하지 않았어.'
          : t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    return Scaffold(
      appBar: AppBar(title: const Text('공유 공간 설정'), actions: [
        TextButton(onPressed: s.repo.signOut, child: const Text('로그아웃')),
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s.removedNotice) ...[
                  const Text('방장이 이 공유 공간에서 내보냈어. 새 공간을 만들거나 다른 코드로 참여할 수 있어.',
                      style: TextStyle(color: Colors.orangeAccent)),
                  const SizedBox(height: 16),
                ],
                const Text('둘 중 한 명이 먼저 공간을 만들고, 나온 코드를 상대에게 보내주면 돼.'),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: () => _run(s.createSpace),
                    child: const Text('새 공간 만들기')),
                const Divider(height: 40),
                TextField(
                  controller: _code,
                  decoration: const InputDecoration(
                      labelText: '초대 코드', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                    onPressed: () => _run(() => s.joinSpace(_code.text)),
                    child: const Text('코드로 참여')),
                if (_err != null) ...[
                  const SizedBox(height: 12),
                  Text(_err!, style: const TextStyle(color: kRed)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
