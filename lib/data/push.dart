import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'repository.dart';

enum PushState { unsupported, off, blocked, on }

/// 이 기기의 푸시 알림(FCM) 켜기/끄기. 토큰은 내 프로필에 저장되어 서버 함수가 상대 기기로 보낼 때 쓴다.
class Push {
  /// 웹 푸시 인증서 키(선택). 없으면 Firebase 기본 키를 쓴다.
  static const _vapid = String.fromEnvironment('VAPID_KEY');

  static FirebaseMessaging get _m => FirebaseMessaging.instance;

  static Future<bool> get supported async {
    try {
      return await FirebaseMessaging.instance.isSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<PushState> state() async {
    if (!await supported) return PushState.unsupported;
    final s = await _m.getNotificationSettings();
    switch (s.authorizationStatus) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return PushState.on;
      case AuthorizationStatus.denied:
      case AuthorizationStatus.deniedPermanently:
        return PushState.blocked;
      case AuthorizationStatus.notDetermined:
        return PushState.off;
    }
  }

  /// 권한을 요청하고 토큰을 저장한다. 결과 상태를 돌려준다.
  static Future<PushState> enable(Repository repo) async {
    if (!await supported) return PushState.unsupported;
    final s = await _m.requestPermission();
    if (s.authorizationStatus == AuthorizationStatus.denied ||
        s.authorizationStatus == AuthorizationStatus.deniedPermanently) {
      return PushState.blocked;
    }
    final token = await _m.getToken(vapidKey: _vapid.isEmpty ? null : _vapid);
    if (token == null) return PushState.off;
    await repo.addFcmToken(token);
    // 토큰이 바뀌면 다시 저장
    _m.onTokenRefresh.listen((t) => repo.addFcmToken(t));
    return PushState.on;
  }

  /// 이 기기에서 알림 끄기: 토큰을 서버 목록에서 빼고 삭제한다.
  static Future<void> disable(Repository repo) async {
    final token = await _m.getToken(vapidKey: _vapid.isEmpty ? null : _vapid);
    if (token != null) await repo.removeFcmToken(token);
    await _m.deleteToken();
  }

  /// 앱이 열려 있는 동안 온 알림은 스낵바로 보여준다 (브라우저/OS는 앱이 켜진 동안 알림을 띄우지 않는다).
  static void listenForeground(GlobalKey<ScaffoldMessengerState> key) {
    supported.then((ok) {
      if (!ok) return;
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        key.currentState?.showSnackBar(SnackBar(
          content: Text([if (n.title != null) n.title!, if (n.body != null) n.body!].join('\n')),
          duration: const Duration(seconds: 5),
        ));
      });
    });
  }
}
