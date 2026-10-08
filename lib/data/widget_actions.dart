import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart' hide Visibility;
import 'package:geolocator/geolocator.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../firebase_options.dart';
import '../models/item.dart';
import 'repository.dart';
import 'store.dart';
import 'widget_sync.dart';

/// 홈 화면 위젯에서 할 일 체크박스를 눌렀을 때 앱을 열지 않고 백그라운드에서 완료 처리한다.
/// 네이티브(WidgetActionActivity)가 `ourday://done?space=…&id=…&date=yyyy-MM-dd` 로 이 함수를 부른다.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri != null && uri.host == 'locate') return _backgroundLocate();
  if (uri != null && uri.host == 'refresh') return _backgroundRefresh();
  if (uri == null || uri.host != 'done') return;
  final space = uri.queryParameters['space'] ?? '';
  final id = uri.queryParameters['id'] ?? '';
  final date = uri.queryParameters['date'] ?? '';
  if (space.isEmpty || id.isEmpty || date.isEmpty) return;
  bool? marking;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? await auth.authStateChanges().firstWhere((u) => u != null).timeout(const Duration(seconds: 8));
    if (user == null) throw StateError('로그인 정보를 못 찾았어');
    final repo = Repository();
    final item = await repo.getItem(space, id);
    if (item == null) throw StateError('항목을 못 찾았어 (삭제됐거나 볼 수 없는 항목)');
    final day = DateTime.parse(date);
    // 이동형은 완료하면 다음 날짜로 넘어간다. 이미 넘어간 항목을 또 누르면 한 번 더 넘어가 버리니 막는다.
    if (item.isRolling && dateOnly(item.start) != dateOnly(day)) return;
    final r = toggledDone(item, dateOnly(day), user.uid, DateTime.now());
    marking = r.marking;
    // 서버 저장을 기다리기 전에 위젯부터 바꿔서 바로 보이게 한다
    await WidgetSync.patchDone(id, date, r.marking);
    // 저장: 네트워크가 잠깐 안 되어도 기기에 대기열로 남아 나중에 올라가므로, 오래 기다리지 않는다
    await repo.save(space, r.item).timeout(const Duration(seconds: 12));
    if (r.marking && item.visibility == Visibility.shared) {
      unawaited(repo.notifyComplete(space, id).catchError((_) {}));
    }
    await _recordWidgetDoneError(''); // 성공하면 지난 오류 표시를 지운다
  } on TimeoutException {
    // 저장 요청은 이미 기기에 대기 중이라 연결되면 올라간다. 위젯은 그대로 둔다.
    await _recordWidgetDoneError('저장 응답이 늦어서 대기 중이야 (연결되면 올라가)');
  } catch (e) {
    // 저장 못 한 걸 위젯이 완료로 보여 주면 헷갈리니 원래대로 되돌리고, 이유를 설정 화면에서 볼 수 있게 남긴다
    if (marking != null) await WidgetSync.patchDone(id, date, !marking);
    await _recordWidgetDoneError('$e');
  }
}

/// 위젯 체크박스 저장이 실패한 이유를 남긴다 (설정 → 위젯 완료 기록). 빈 문자열이면 지운다.
Future<void> _recordWidgetDoneError(String message) async {
  try {
    final stamp = message.isEmpty ? '' : '${DateTime.now().toIso8601String().substring(0, 16)} $message';
    await HomeWidget.saveWidgetData<String>('widgetDoneError', stamp);
  } catch (_) {}
}

/// 앱을 안 열어도 주기적으로(안드로이드 WorkManager) 불리는 위젯 데이터 갱신.
/// 상대가 추가한 일정, 다른 기기에서 바꾼 내용, 날짜가 바뀐 뒤의 목록을 위젯에 새로 반영한다.
/// 앱 화면과 같은 계산을 쓰려고 Store를 잠깐 만들어서 데이터가 올 때까지 기다린 뒤 한 번 밀어 넣고 닫는다.
Future<void> _backgroundRefresh() async {
  Store? store;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('ko');
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    store = Store(Repository());
    final s = store;
    final ready = Completer<void>();
    void check() {
      if (!ready.isCompleted && s.itemsLoaded && s.profileLoaded && s.categoriesLoaded) ready.complete();
    }

    s.addListener(check);
    check();
    await ready.future.timeout(const Duration(seconds: 25));
    await s.refreshWidgetNow();
  } catch (_) {
    // 로그인이 없거나 네트워크가 없으면 다음 주기에 다시 한다
  } finally {
    store?.dispose();
  }
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
