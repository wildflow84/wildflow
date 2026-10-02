import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';

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
            const Icon(Icons.calendar_month, size: 72),
            const SizedBox(height: 12),
            Text('OurDay', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            const Text('우리 둘의 일정과 할 일'),
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
