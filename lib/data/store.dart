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
  final Set<String> filters = {'partner'};

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
      if (i.ownerUid == me) return true; // 내 항목은 항상 보인다
      return showShared; // 상대가 올린 같이 보기 항목은 토글
    }).toList();
  }

  /// "공유 캘린더 보기" 토글 (상대가 올린 같이 보기 항목)
  bool get showShared => filters.contains('partner');

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

  /// 항목의 카테고리들 (삭제된 카테고리는 빼고, 하나도 없으면 첫 카테고리)
  List<Category> categoriesOf(Item i) {
    final list = [
      for (final id in i.categories)
        for (final c in categories)
          if (c.id == id) c
    ];
    return list.isEmpty ? [categoryOf(i.category)] : list;
  }

  /// 항목 색: 항목별 색 > 대표(첫 번째) 카테고리 색
  Color colorOf(Item i) => i.color != null ? Color(i.color!) : categoriesOf(i).first.color;

  /// 새 항목의 공개 범위: 선택한 카테고리 중 하나라도 "나만"이면 나만 > 카테고리 기본값 > 내 기본 설정
  m.Visibility visibilityFor(List<String> categoryIds) {
    final defaults = [for (final id in categoryIds) categoryOf(id).defaultVisibility];
    if (defaults.contains(m.Visibility.private)) return m.Visibility.private;
    if (defaults.contains(m.Visibility.shared)) return m.Visibility.shared;
    return defaultVisibility;
  }

  Future<void> setDefaultVisibility(m.Visibility v) async {
    defaultVisibility = v;
    notifyListeners();
    await repo.setDefaultVisibility(v);
  }

  Future<String> saveCategory(Category c) => repo.saveCategory(spaceId!, c);

  /// 드래그로 바꾼 순서를 저장
  Future<void> reorderCategories(List<Category> ordered) {
    final updated = [for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(order: i)];
    categories = updated;
    notifyListeners();
    return repo.saveCategories(spaceId!, updated);
  }

  Future<void> deleteCategory(Category c) => repo.deleteCategory(spaceId!, c.id);

  String ownerName(Item i) => names[i.ownerUid] ?? '';

  /// 만든 사람 표시용 이름 (이름을 아직 모르면 나/상대)
  String ownerLabel(Item i) {
    final n = names[i.ownerUid];
    if (n != null && n.isNotEmpty) return n;
    return i.ownerUid == uid ? '나' : '상대';
  }

  Future<void> save(Item i) async {
    if (_previewUid != null) {
      // 미리보기(Firebase 없음): 로컬 목록만 갱신
      items = [...items.where((x) => x.id != i.id), i];
      notifyListeners();
      return;
    }
    await repo.save(spaceId!, i);
  }
  Future<void> delete(Item i) => repo.delete(spaceId!, i.id);

  /// 반복 항목 삭제: 이 날짜만 / 이 날짜 이후 / 전부
  Future<void> deleteRepeating(Item i, DateTime day, RepeatDelete scope) async {
    final result = applyRepeatDelete(i, day, scope);
    if (result == null) {
      await delete(i);
    } else {
      await save(result);
    }
  }

  /// 완료 토글. 이동형 반복은 완료 대신 날짜가 다음 일정으로 넘어간다.
  /// 되돌리기용으로 변경 전 항목을 돌려준다 (이동형일 때만).
  Future<Item?> toggleDone(Item i, DateTime day) async {
    final now = DateTime.now();
    if (i.isRolling) {
      await save(rollNextItem(i, now, uid));
      return i;
    }
    if (!i.isRecurring) {
      await save(i.copyWith(done: !i.done, lastDoneBy: uid, lastDoneAt: now));
      return null;
    }
    final k = dateKey(day);
    final dd = [...i.doneDates];
    dd.contains(k) ? dd.remove(k) : dd.add(k);
    await save(i.copyWith(doneDates: dd, lastDoneBy: uid, lastDoneAt: now));
    return null;
  }

  /// 이동형 완료 되돌리기
  Future<void> undoRoll(Item previous) => save(previous);

  @override
  void dispose() {
    _authSub?.cancel();
    _stop();
    super.dispose();
  }
}
