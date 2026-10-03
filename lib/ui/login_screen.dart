import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import 'splash.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<Store>();
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HelloArt(width: 280),
            const SizedBox(height: 8),
            Text('순대희 캘린더', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            const Text('함께 쓰는 일정과 할 일'),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Google로 로그인'),
              onPressed: () async {
                try {
                  await s.repo.signInWithGoogle();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('로그인 실패: $e')));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
