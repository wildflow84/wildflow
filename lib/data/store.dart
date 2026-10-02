import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/item.dart';
import 'repository.dart';
import 'widget_sync.dart';

/// 화면이 구독하는 단일 상태 객체.
class Store extends ChangeNotifier {
  final Repository repo;
  Store(this.repo) {
    _authSub = repo.authChanges.listen(_onAuth);
  }

  late final StreamSubscription _authSub;
  StreamSubscription? _itemsSub, _namesSub;

  User? user;
  String? spaceId;
  bool loading = true;
  String? error;
  List<Item> items = [];
  Map<String, String> names = {};

  /// 보기 필터: mine=내 항목, partner=상대 공유 항목
  final Set<String> filters = {'mine', 'partner'};

  Future<void> _onAuth(User? u) async {
    user = u;
    await _stop();
    if (u == null) {
      spaceId = null;
      items = [];
      loading = false;
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    try {
      spaceId = await repo.mySpaceId();
      if (spaceId != null) _start();
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  void _start() {
    final id = spaceId!;
    _itemsSub = repo.watchItems(id).listen((list) {
      items = list;
      notifyListeners();
      WidgetSync.push(visibleItems, user!.uid);
    }, onError: (e) {
      error = '$e';
      notifyListeners();
    });
    _namesSub = repo.memberNames(id).listen((n) {
      names = n;
      notifyListeners();
    });
  }

  Future<void> _stop() async {
    await _itemsSub?.cancel();
    await _namesSub?.cancel();
  }

  Future<void> createSpace() async {
    spaceId = await repo.createSpace();
    _start();
    notifyListeners();
  }

  Future<void> joinSpace(String code) async {
    await repo.joinSpace(code);
    spaceId = code.trim();
    _start();
    notifyListeners();
  }

  /// 현재 필터에 맞는 항목. 'mine'=내가 소유한 것(공유+프라이빗), 'partner'=상대가 올린 공유 항목.
  List<Item> get visibleItems {
    final me = user?.uid;
    return items.where((i) {
      final isMine = i.ownerUid == me;
      if (isMine) return filters.contains('mine');
      return filters.contains('partner');
    }).toList();
  }

  void toggleFilter(String f) {
    filters.contains(f) ? filters.remove(f) : filters.add(f);
    notifyListeners();
    WidgetSync.push(visibleItems, user!.uid);
  }

  List<Item> itemsOn(DateTime day) {
    final list = visibleItems.where((i) => occursOn(i, day)).toList();
    list.sort((a, b) {
      if (a.type != b.type) return a.type == ItemType.event ? -1 : 1;
      return a.start.compareTo(b.start);
    });
    return list;
  }

  String ownerName(Item i) => names[i.ownerUid] ?? '';

  Future<void> save(Item i) => repo.save(spaceId!, i);
  Future<void> delete(Item i) => repo.delete(spaceId!, i.id);

  Future<void> toggleDone(Item i, DateTime day) {
    if (i.repeat == Repeat.none) return save(i.copyWith(done: !i.done));
    final k = dateKey(day);
    final dd = [...i.doneDates];
    dd.contains(k) ? dd.remove(k) : dd.add(k);
    return save(i.copyWith(doneDates: dd));
  }

  @override
  void dispose() {
    _authSub.cancel();
    _stop();
    super.dispose();
  }
}
