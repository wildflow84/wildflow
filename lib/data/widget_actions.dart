import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart' hide Visibility;
import 'package:geolocator/geolocator.dart';
import 'package:home_widget/home_widget.dart';

import '../firebase_options.dart';
import '../models/item.dart';
import 'repository.dart';

/// 홈 화면 위젯에서 할 일 체크박스를 눌렀을 때 앱을 열지 않고 백그라운드에서 완료 처리한다.
/// 네이티브(WidgetActionActivity)가 `ourday://done?space=…&id=…&date=yyyy-MM-dd` 로 이 함수를 부른다.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri != null && uri.host == 'locate') return _backgroundLocate();
  if (uri == null || uri.host != 'done') return;
  final space = uri.queryParameters['space'] ?? '';
  final id = uri.queryParameters['id'] ?? '';
  final date = uri.queryParameters['date'] ?? '';
  if (space.isEmpty || id.isEmpty || date.isEmpty) return;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? await auth.authStateChanges().firstWhere((u) => u != null).timeout(const Duration(seconds: 8));
    if (user == null) return;
    final repo = Repository();
    final item = await repo.getItem(space, id);
    if (item == null) return;
    final day = DateTime.parse(date);
    final r = toggledDone(item, dateOnly(day), user.uid, DateTime.now());
    // 서버 저장을 기다리기 전에 위젯부터 바꿔서 바로 보이게 한다
    await _patchWidgetJson(id, date, r.item, dateOnly(day));
    await repo.save(space, r.item);
    if (r.marking && item.visibility == Visibility.shared) {
      unawaited(repo.notifyComplete(space, id).catchError((_) {}));
    }
  } catch (_) {
    // 실패해도 조용히: 위젯은 다음에 앱을 열 때 맞춰진다
  }
}

/// 위젯 목록 데이터에서 방금 바꾼 항목의 완료 표시만 고쳐서 바로 반영한다.
Future<void> _patchWidgetJson(String id, String date, Item updated, DateTime day) async {
  try {
    final raw = await HomeWidget.getWidgetData<String>('agendaJson');
    if (raw == null) return;
    final days = jsonDecode(raw) as List;
    final done = isDoneOn(updated, day);
    for (final d in days) {
      for (final it in (d['items'] as List)) {
        if (it['id'] == id && it['dk'] == date) it['done'] = done;
      }
    }
    await HomeWidget.saveWidgetData<String>('agendaJson', jsonEncode(days));
    await HomeWidget.updateWidget(androidName: 'OurDayWidget');
  } catch (_) {}
}

/// 앱을 안 열어도 15분마다(안드로이드 WorkManager) 불리는 위치 갱신.
/// 곧 시작하는 "출발 알림" 일정이 있을 때만 내 위치를 서버에 남긴다 (서버가 출발 시각을 계산).
Future<void> _backgroundLocate() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? await auth.authStateChanges().firstWhere((u) => u != null).timeout(const Duration(seconds: 8));
    if (user == null) return;
    final repo = Repository();
    final space = await repo.mySpaceId();
    if (space == null) return;
    final now = DateTime.now();
    final soon = await FirebaseFirestore.instance
        .collection('spaces')
        .doc(space)
        .collection('items')
        .where('departFrom', isGreaterThan: Timestamp.fromDate(now))
        .where('departFrom', isLessThanOrEqualTo: Timestamp.fromDate(now.add(const Duration(hours: 8))))
        .get();
    final mine = soon.docs.any((d) => d.data()['ownerUid'] == user.uid && d.data()['departAlert'] == true);
    if (!mine) return;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
    );
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'lastLoc': {'lat': pos.latitude, 'lng': pos.longitude, 'at': FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
  } catch (_) {
    // 백그라운드 위치 권한이 없거나 위치를 못 가져오면 조용히 넘어간다
  }
}
