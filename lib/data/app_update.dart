import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// 새 안드로이드 앱이 나왔을 때 알려주기 위한 정보.
/// CI가 앱을 빌드할 때마다 APK와 `app/latest.json`을 웹 호스팅에 같이 올린다.
class AppUpdate {
  final int build;
  final String version;
  final Uri apkUrl;
  const AppUpdate({required this.build, required this.version, required this.apkUrl});
}

/// `latest.json` 내용에서 지금 앱([current] 빌드 번호)보다 새 버전이 있으면 그 정보를, 아니면 null.
AppUpdate? parseLatest(String body, int current, Uri base) {
  try {
    final m = jsonDecode(body);
    if (m is! Map) return null;
    final build = (m['build'] as num?)?.toInt();
    final apk = m['apk'] as String?;
    if (build == null || apk == null || apk.isEmpty || build <= current) return null;
    return AppUpdate(
      build: build,
      version: (m['version'] as String?) ?? '',
      apkUrl: base.resolve(apk),
    );
  } catch (_) {
    return null;
  }
}

class UpdateChecker {
  /// CI가 넣는 빌드 번호. 개발 빌드나 웹은 0이라 업데이트 확인을 하지 않는다.
  static const currentBuild = int.fromEnvironment('APP_BUILD', defaultValue: 0);

  static bool get supported => !kIsWeb && currentBuild > 0;

  static Uri get _base => Uri.parse('https://${Firebase.app().options.projectId}.web.app/');

  /// 새 버전이 있으면 정보를, 없거나 확인에 실패하면 null.
  static Future<AppUpdate?> check() async {
    if (!supported) return null;
    try {
      final res = await http.get(_base.resolve('app/latest.json')).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return parseLatest(utf8.decode(res.bodyBytes), currentBuild, _base);
    } catch (_) {
      return null;
    }
  }
}
