// Firebase 설정은 코드에 넣지 않고 빌드할 때 --dart-define-from-file=firebase_config.json 으로 주입한다.
// (CI에서는 GitHub Secret FIREBASE_CONFIG_JSON 으로 생성. README 참고)
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static const _projectId = String.fromEnvironment('PROJECT_ID');
  static const _senderId = String.fromEnvironment('MESSAGING_SENDER_ID');
  static const _authDomain = String.fromEnvironment('AUTH_DOMAIN');
  static const _bucket = String.fromEnvironment('STORAGE_BUCKET');
  static const _webKey = String.fromEnvironment('WEB_API_KEY');
  static const _webAppId = String.fromEnvironment('WEB_APP_ID');
  static const _androidKey = String.fromEnvironment('ANDROID_API_KEY');
  static const _androidAppId = String.fromEnvironment('ANDROID_APP_ID');

  static FirebaseOptions get currentPlatform {
    if (_projectId.isEmpty) {
      throw StateError('Firebase 설정이 없어. firebase_config.json을 --dart-define-from-file로 넘겨줘. (README 참고)');
    }
    if (kIsWeb) {
      return const FirebaseOptions(
        apiKey: _webKey,
        appId: _webAppId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        authDomain: _authDomain,
        storageBucket: _bucket,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const FirebaseOptions(
        apiKey: _androidKey,
        appId: _androidAppId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        storageBucket: _bucket,
      );
    }
    throw UnsupportedError('지원하지 않는 플랫폼');
  }
}
