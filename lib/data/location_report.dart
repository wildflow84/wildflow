import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../models/item.dart';
import 'store.dart';

/// 출발 시간 알림용: 곧 시작하는 "출발 알림" 일정이 있을 때만, 앱을 열거나 돌아올 때 내 위치를 서버에 남긴다.
/// 서버(sendDepartAlerts)가 이 위치에서 장소까지 걸리는 시간을 계산해 출발할 때 푸시를 보낸다.
class LocationReporter with WidgetsBindingObserver {
  final Store store;
  DateTime? _last;
  LocationReporter(this.store);

  static const _minGap = Duration(minutes: 3);
  static const _horizon = Duration(hours: 8);

  void start() {
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_onStore);
  }

  void _onStore() => unawaited(maybeReport());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(maybeReport(force: true));
  }

  /// 앞으로 [_horizon] 안에 시작하는 출발 알림 일정이 있나
  static bool hasUpcomingDepart(List<Item> items, DateTime now) =>
      items.any((i) {
        final f = i.departFrom;
        return f != null && f.isAfter(now) && f.difference(now) <= _horizon;
      });

  Future<void> maybeReport({bool force = false}) async {
    try {
      final uid = store.user?.uid;
      if (uid == null || store.spaceId == null) return;
      final now = DateTime.now();
      if (!hasUpcomingDepart(store.items, now)) return;
      if (!force && _last != null && now.difference(_last!) < _minGap) return;
      _last = now;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
      );
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'lastLoc': {'lat': pos.latitude, 'lng': pos.longitude, 'at': FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (_) {
      // 위치를 못 가져와도 앱 동작에는 영향 없음 (권한 거부, 위치 꺼짐, 시간 초과)
    }
  }
}
