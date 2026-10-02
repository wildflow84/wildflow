import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/painting.dart' show Color;

import '../models/category.dart';
import '../models/item.dart';
import '../models/item.dart' as m;
import '../models/kr_calendar.dart';
import 'repository.dart';
import 'widget_sync.dart';

/// 화면이 구독하는 단일 상태 객체.
class Store extends ChangeNotifier {
  final Repository repo;
  Store(this.repo) {
    _authSub = repo.authChanges.listen(_onAuth);
  }

  /// Firebase 없이 화면만 확인하는 미리보기용 (lib/preview_main.dart, 위젯 테스트)
  Store.preview(this.repo, {required String uid, required this.names, required this.items})
      : _previewUid = uid,
        spaceId = 'preview',
        loading = false;

  String? _previewUid;
  StreamSubscription? _authSub;

  String get uid => _previewUid ?? user!.uid;
  StreamSubscription? _itemsSub, _namesSub, _customSub, _catSub, _profileSub;

  User? user;
  String? spaceId;
  bool loading = true;
  String? error;
  List<Item> items = [];
  Map<String, String> names = {};
  List<CustomDay> customDays = [];
  List<Category> categories = defaultCategories;

  /// 새 항목의 기본 공개 범위 (설정에서 변경). 카테고리별 기본값이 있으면 그쪽이 우선.
  m.Visibility defaultVisibility = m.Visibility.shared;
  bool _seeded = false;

  /// 공휴일/절기/기념일 달력. 사용자가 추가한 임시공휴일이 바뀌면 새로 만든다.
  KrCalendar cal = KrCalendar();

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
      WidgetSync.push(visibleItems, uid);
    }, onError: (e) {
      error = '$e';
      notifyListeners();
    });
    _catSub = repo.watchCategories(id).listen((list) {
      if (list.isEmpty) {
        if (!_seeded) {
          _seeded = true;
          repo.seedCategoriesIfEmpty(id).catchError((_) {});
        }
        categories = defaultCategories;
      } else {
        categories = [...list]..sort((a, b) {
            final o = a.order.compareTo(b.order);
            return o != 0 ? o : a.name.compareTo(b.name);
          });
      }
      notifyListeners();
    });
    _profileSub = repo.watchDefaultVisibility().listen((v) {
      defaultVisibility = v ?? m.Visibility.shared;
      notifyListeners();
    });
    _customSub = repo.watchCustomDays(id).listen((list) {
      customDays = list;
      cal = KrCalendar(custom: list);
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
    await _customSub?.cancel();
    await _catSub?.cancel();
    await _profileSub?.cancel();
    _seeded = false;
    categories = defaultCategories;
    defaultVisibility = m.Visibility.shared;
    customDays = [];
    cal = KrCalendar();
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
    final me = _previewUid ?? user?.uid;
    return items.where((i) {
      final isMine = i.ownerUid == me;
      if (isMine) return filters.contains('mine');
      return filters.contains('partner');
    }).toList();
  }

  void toggleFilter(String f) {
    filters.contains(f) ? filters.remove(f) : filters.add(f);
    notifyListeners();
    WidgetSync.push(visibleItems, uid);
  }

  List<Item> itemsOn(DateTime day) {
    final list = visibleItems.where((i) => occursOn(i, day)).toList();
    list.sort((a, b) {
      if (a.type != b.type) return a.type == ItemType.event ? -1 : 1;
      return a.start.compareTo(b.start);
    });
    return list;
  }

  List<CustomDay> customDaysOn(DateTime d) =>
      customDays.where((c) => dateOnly(c.date) == dateOnly(d)).toList();

  Future<void> addCustomDay(DateTime d, String name, bool holiday) => repo.saveCustomDay(
      spaceId!, CustomDay(id: '', date: d, name: name, holiday: holiday));

  Future<void> deleteCustomDay(CustomDay c) => repo.deleteCustomDay(spaceId!, c.id);

  Category categoryOf(String id) => categories.firstWhere((c) => c.id == id,
      orElse: () => categories.isNotEmpty ? categories.first : defaultCategories.first);

  /// 항목 색: 항목별 색 > 카테고리 색
  Color colorOf(Item i) => i.color != null ? Color(i.color!) : categoryOf(i.category).color;

  /// 새 항목의 공개 범위: 카테고리 기본값 > 내 기본 설정
  m.Visibility visibilityFor(String categoryId) =>
      categoryOf(categoryId).defaultVisibility ?? defaultVisibility;

  Future<void> setDefaultVisibility(m.Visibility v) async {
    defaultVisibility = v;
    notifyListeners();
    await repo.setDefaultVisibility(v);
  }

  Future<String> saveCategory(Category c) => repo.saveCategory(spaceId!, c);

  Future<void> deleteCategory(Category c) => repo.deleteCategory(spaceId!, c.id);

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
    _authSub?.cancel();
    _stop();
    super.dispose();
  }
}
