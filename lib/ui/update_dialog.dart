import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_update.dart';

bool _askedThisLaunch = false;

/// 앱을 켠 뒤 한 번만 새 버전이 있는지 확인하고, 있으면 안내한다.
Future<void> askUpdateOnce(BuildContext context) async {
  if (_askedThisLaunch || !UpdateChecker.supported) return;
  _askedThisLaunch = true;
  final u = await UpdateChecker.check();
  if (u != null && context.mounted) await showUpdateDialog(context, u);
}

Future<void> showUpdateDialog(BuildContext context, AppUpdate u) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('새 버전이 나왔어'),
      content: Text(
        '${u.version.isEmpty ? '' : '버전 ${u.version}\n\n'}'
        '업데이트를 누르면 앱 파일을 내려받아. 받은 파일(알림)을 눌러서 설치하면 기존 앱 위에 그대로 덮어써져.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('나중에')),
        FilledButton(
          onPressed: () {
            launchUrl(u.apkUrl, mode: LaunchMode.externalApplication);
            Navigator.pop(ctx);
          },
          child: const Text('업데이트'),
        ),
      ],
    ),
  );
}

/// 설정에서 직접 확인
Future<void> checkUpdateNow(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final u = await UpdateChecker.check();
  if (!context.mounted) return;
  if (u == null) {
    messenger.showSnackBar(const SnackBar(content: Text('지금이 최신 버전이야')));
  } else {
    await showUpdateDialog(context, u);
  }
}
