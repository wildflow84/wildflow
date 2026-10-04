import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctionsException;
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
  List<String> members = []; // 맨 앞이 방장(공간을 만든 사람)
  Map<String, String> bannedNames = {}; // 내보낸 사람들 (uid → 이름)
  /// 방장이 나를 내보냈을 때 한 번 안내하기 위한 표시
  bool removedNotice = false;

  bool get isHost => members.isNotEmpty && members.first == uid;

  /// 내 프로필 문서 (알림 설정 등)
  Map<String, dynamic> profile = {};

  /// 알림 설정: 기본값은 재촉 받기/완료 알림 켜짐, 반복 할 일 완료 알림 꺼짐
  bool get allowNudge => profile['allowNudge'] != false;
  bool get notifyReminder => profile['notifyReminder'] != false;
  bool get notifyShared => profile['notifyShared'] != false;
  bool get notifyComplete => profile['notifyComplete'] != false;
  bool get notifyCompleteRepeating => profile['notifyCompleteRepeating'] == true;

  /// 화면 테마: system(기기 따라감, 기본) / light / dark
  String get themeMode {
    final v = profile['themeMode'];
    return v == 'light' || v == 'dark' ? v as String : 'system';
  }

  /// 내 설정을 한 번이라도 받아왔는지 (시작 화면을 고르는 데 쓴다)
  bool profileLoaded = false;

  /// 앱을 켰을 때 먼저 보여줄 탭: last(마지막으로 본 화면, 기본) / calendar / list / todo
  String get startTab {
    final v = profile['startTab'];
    return v == 'calendar' || v == 'list' || v == 'todo' ? v as String : 'last';
  }

  /// 0=캘린더 1=목록 2=할 일
  int get initialTab {
    switch (startTab) {
      case 'calendar':
        return 0;
      case 'list':
        return 1;
      case 'todo':
        return 2;
    }
    final last = profile['lastTab'];
    return last is int && last >= 0 && last <= 2 ? last : 0;
  }

  /// 탭을 바꿀 때마다 기억해 둔다 (시작 화면이 "마지막으로 본 화면"일 때만)
  void rememberTab(int i) {
    if (startTab == 'last' && profile['lastTab'] != i) unawaited(setPref('lastTab', i));
  }

  Future<void> setPref(String key, Object value) async {
    profile = {...profile, key: value};
    notifyListeners();
    if (_previewUid == null) await repo.setPref(key, value);
  }
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
      _pushWidget();
      _refillRepeatReminders();
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
        // 안 건드린 예전 기본 색은 새 기본 색으로 바꿔 둔다
        for (final c in list) {
          final old = oldDefaultCategoryColors[c.id];
          if (old != null && c.colorValue == old) {
            final nc = defaultCategories.firstWhere((d) => d.id == c.id);
            repo.saveCategory(id, c.copyWith(colorValue: nc.colorValue)).catchError((_) => '');
          }
        }
        categories = [...list]..sort((a, b) {
            final o = a.order.compareTo(b.order);
            return o != 0 ? o : a.name.compareTo(b.name);
          });
      }
      notifyListeners();
      _pushWidget(); // 카테고리 이름/색이 바뀌면 위젯도
    });
    _profileSub = repo.watchProfile().listen((p) {
      profile = p;
      profileLoaded = true;
      final v = p['defaultVisibility'] as String?;
      defaultVisibility = v == null
          ? m.Visibility.shared
          : m.Visibility.values.firstWhere((e) => e.name == v, orElse: () => m.Visibility.shared);
      notifyListeners();
      _pushWidget(); // 다른 기기에서 바꾼 카테고리 보기 설정도 반영
    });
    _customSub = repo.watchCustomDays(id).listen((list) {
      customDays = list;
      cal = KrCalendar(custom: list);
      notifyListeners();
    });
    _namesSub = repo.watchSpace(id).listen((sp) {
      names = sp.names;
      members = sp.members;
      bannedNames = sp.bannedNames;
      notifyListeners();
      // 방장이 나를 내보냈다: 연결을 끊고 공간 선택 화면으로
      if (sp.members.isNotEmpty && !sp.members.contains(uid)) _wasRemoved();
    });
  }

  final Set<String> _remindRefilled = {};

  /// 반복 일정의 알림 시각 목록은 서버가 하나씩 보내며 줄어든다. 내 일정 중 목록이 어긋났거나 곧 바닥나는 것만 새로 채워 저장한다.
  void _refillRepeatReminders() {
    if (_previewUid != null || spaceId == null) return;
    final now = DateTime.now();
    for (final i in items) {
      if (i.ownerUid != uid || i.id.isEmpty || !i.needsRemindRefill(now)) continue;
      // 같은 항목을 한 번 채운 뒤에는 이 접속에서 다시 채우지 않는다 (저장이 다시 이 검사를 부르는 걸 막는다)
      if (!_remindRefilled.add('${i.id}|${i.remindStoredAt?.millisecondsSinceEpoch}')) continue;
      repo.save(spaceId!, i).catchError((_) => '');
    }
  }

  Future<void> _wasRemoved() async {
    await _stop();
    spaceId = null;
    items = [];
    names = {};
    members = [];
    removedNotice = true;
    notifyListeners();
    repo.clearMySpace().catchError((_) {});
  }

  /// 방장만: 상대를 내보낸다 (그 사람이 만든 같이 보기 항목은 남고, 나만 보기 항목은 그 사람 것으로 남는다)
  Future<void> removeMember(String targetUid) => repo.removeMember(spaceId!, targetUid);

  Future<void> allowMember(String targetUid) => repo.allowMember(spaceId!, targetUid);

  Future<void> _stop() async {
    await _itemsSub?.cancel();
    await _namesSub?.cancel();
    await _customSub?.cancel();
    await _catSub?.cancel();
    await _profileSub?.cancel();
    profileLoaded = false;
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
    removedNotice = false;
    await repo.joinSpace(code);
    spaceId = code.trim();
    _start();
    notifyListeners();
  }

  /// 현재 필터에 맞는 항목. 'mine'=내가 소유한 것(공유+프라이빗), 'partner'=상대가 올린 공유 항목.
  List<Item> get visibleItems => _visibleCache ??= _computeVisible();

  // 같은 상태에서 화면이 여러 번 다시 그려질 때마다 전체 항목을 다시 거르지 않게 결과를 기억해 둔다.
  // 상태가 바뀌어 notifyListeners()가 불리면 비운다.
  List<Item>? _visibleCache;
  List<Item>? _photoSpansCache;
  final Map<int, List<Item>> _dayCache = {};

  @override
  void notifyListeners() {
    _visibleCache = null;
    _photoSpansCache = null;
    _dayCache.clear();
    super.notifyListeners();
  }

  /// 사진이 있는 여러 날 일정 (달력 칸 배경용)
  List<Item> get photoSpans => _photoSpansCache ??= [
        for (final i in visibleItems)
          if (i.type == ItemType.event && i.photoUrl != null && i.end != null && !i.isRecurring &&
              dateOnly(i.end!).isAfter(dateOnly(i.start)))
            i
      ];

  List<Item> _computeVisible() {
    final me = _previewUid ?? user?.uid;
    final hidden = hiddenCategories;
    return items.where((i) {
      if (hidden.isNotEmpty && hidden.contains(i.categories.isEmpty ? 'default' : i.categories.first)) {
        return false; // 숨긴 카테고리
      }
      if (i.ownerUid == me) return true; // 내 항목은 항상 보인다
      return showShared; // 상대가 올린 같이 보기 항목은 토글
    }).toList();
  }

  /// 달력에서 숨긴 카테고리 (기기 간 같이 쓰도록 내 프로필에 저장)
  Set<String> get hiddenCategories => {...?(profile['hiddenCategories'] as List?)?.map((e) => '$e')};

  Future<void> setCategoryHidden(String id, bool hidden) async {
    final next = hiddenCategories..remove(id);
    if (hidden) next.add(id);
    profile = {...profile, 'hiddenCategories': next.toList()};
    notifyListeners();
    _pushWidget(); // 위젯도 같은 보기 설정으로
    if (_previewUid == null) await repo.setPref('hiddenCategories', next.toList());
  }

  /// 모든 카테고리를 한꺼번에 숨기거나(전체 해제) 보이게(전체 선택) 한다
  Future<void> setAllCategoriesHidden(Iterable<String> ids, bool hidden) async {
    final next = hidden ? ids.toList() : <String>[];
    profile = {...profile, 'hiddenCategories': next};
    notifyListeners();
    _pushWidget();
    if (_previewUid == null) await repo.setPref('hiddenCategories', next);
  }

  Future<void> showAllCategories() async {
    profile = {...profile, 'hiddenCategories': <String>[]};
    notifyListeners();
    _pushWidget();
    if (_previewUid == null) await repo.setPref('hiddenCategories', <String>[]);
  }

  /// "공유 캘린더 보기" 토글 (상대가 올린 같이 보기 항목)
  bool get showShared => filters.contains('partner');

  /// 안드로이드 홈 화면 위젯에 지금 보이는 일정/할 일을 밀어 넣는다
  Timer? _pushTimer;

  void _pushWidget() {
    if (kIsWeb) return; // 위젯은 안드로이드 전용
    // 항목이 바뀔 때마다(내가 저장하면 두 번씩 오기도 해) 바로 계산하면 화면이 버벅이므로, 잠잠해진 뒤 한 번만 보낸다
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 2), _doPushWidget);
  }

  void _doPushWidget() {
    WidgetSync.push(
      visibleItems,
      uid,
      colorOf: (i) => colorOf(i).toARGB32(),
      categoryName: (i) => categoriesOf(i).first.name,
      holidaysOn: (d) => [for (final m in cal.marksOn(d)) if (m.isHoliday) m.name],
      spaceId: spaceId ?? '',
    );
  }

  void toggleFilter(String f) {
    filters.contains(f) ? filters.remove(f) : filters.add(f);
    notifyListeners();
    _pushWidget();
  }

  List<Item> itemsOn(DateTime day) {
    final key = day.year * 10000 + day.month * 100 + day.day;
    return _dayCache.putIfAbsent(key, () {
      final list = visibleItems.where((i) => occursOn(i, day)).toList();
      list.sort((a, b) {
        if (a.type != b.type) return a.type == ItemType.event ? -1 : 1;
        return a.start.compareTo(b.start);
      });
      return list;
    });
  }

  List<CustomDay> customDaysOn(DateTime d) =>
      customDays.where((c) => dateOnly(c.date) == dateOnly(d)).toList();

  Future<void> addCustomDay(DateTime d, String name, bool holiday) => repo.saveCustomDay(
      spaceId!, CustomDay(id: '', date: d, name: name, holiday: holiday));

  Future<void> deleteCustomDay(CustomDay c) => repo.deleteCustomDay(spaceId!, c.id);

  Category categoryOf(String id) => id == subscriptionCategoryId
      ? subscriptionCategory
      : categories.firstWhere((c) => c.id == id,
      orElse: () => categories.isNotEmpty ? categories.first : defaultCategories.first);

  /// 항목의 카테고리들 (삭제된 카테고리는 빼고, 하나도 없으면 첫 카테고리)
  List<Category> categoriesOf(Item i) {
    final list = [
      for (final id in i.categories)
        for (final c in [...categories, subscriptionCategory])
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

  /// 내 닉네임 (상대와 항목의 '만든 사람'에 이 이름으로 보인다). 아직 안 정했으면 구글 이름.
  String get myNickname => names[uid] ?? '';

  static const maxNicknameLength = 12;

  Future<void> setNickname(String value) async {
    final n = value.trim();
    if (n.isEmpty || n.length > maxNicknameLength) return;
    names = {...names, uid: n};
    notifyListeners();
    if (_previewUid != null) return;
    await repo.setNickname(spaceId!, n);
  }

  String ownerName(Item i) => names[i.ownerUid] ?? '';

  /// 만든 사람 표시용 이름 (이름을 아직 모르면 나/상대)
  String ownerLabel(Item i) {
    final n = names[i.ownerUid];
    if (n != null && n.isNotEmpty) return n;
    return i.ownerUid == uid ? '나' : '상대';
  }

  /// [notifyShare]: 새로 공유되는 항목이면 상대에게 알림. 반복 일정 수정으로 갈라져 생기는 항목처럼 사용자가 새로 공유한 게 아닐 땐 끈다.
  Future<void> save(Item i, {bool notifyShare = true}) async {
    if (_previewUid != null) {
      // 미리보기(Firebase 없음): 로컬 목록만 갱신
      items = [...items.where((x) => x.id != i.id), i];
      notifyListeners();
      return;
    }
    // 상대에게 새로 공유되는 경우(새 같이 보기 항목, 나만 보기 → 같이 보기)에는 알려준다
    final before = i.id.isEmpty ? null : items.where((x) => x.id == i.id).firstOrNull;
    final newlyShared = notifyShare &&
        i.visibility == m.Visibility.shared &&
        i.ownerUid == uid &&
        (before == null || before.visibility != m.Visibility.shared);
    final id = await repo.save(spaceId!, i);
    if (newlyShared) repo.notifyShared(spaceId!, id).catchError((_) {});
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
  /// [checkAll]: 남은 체크리스트를 모두 체크하면서 완료한다.
  Future<Item?> toggleDone(Item item, DateTime day, {bool checkAll = false}) async {
    final i = checkAll ? item.withAllChecks(day, true) : item;
    final r = toggledDone(i, day, uid, DateTime.now());
    await save(r.item);
    if (r.marking) _tellPartnerDone(i);
    return i.isRolling ? item : null;
  }

  /// 같이 보기 항목을 완료했다고 상대에게 알린다 (상대 설정에 따라 서버가 보낼지 정함). 실패해도 무시.
  void _tellPartnerDone(Item i) {
    if (_previewUid != null || i.visibility != m.Visibility.shared || spaceId == null || i.id.isEmpty) return;
    repo.notifyComplete(spaceId!, i.id).catchError((_) {});
  }

  /// 같이 보기 항목 재촉. 사용자에게 보여줄 결과 문구를 돌려준다.
  Future<String> nudge(Item i) async {
    final partner = names.entries.where((e) => e.key != uid).map((e) => e.value).firstOrNull ?? '상대';
    try {
      final r = await repo.nudge(spaceId!, i.id);
      return '$partner에게 재촉했어 (${r['count']}/${r['max']})';
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') return '이 항목은 3번 다 재촉했어';
      if (e.message == 'muted') return '$partner이(가) 재촉 알림을 꺼놨어';
      if (e.message == 'no-device') return '$partner이(가) 아직 알림을 안 켰어 (설정 → 알림)';
      return e.message ?? '재촉을 못 보냈어';
    } catch (_) {
      return '재촉을 못 보냈어. 잠시 뒤에 다시 해봐';
    }
  }

  /// 체크리스트 한 줄 체크/해제
  Future<void> setCheck(Item i, DateTime day, int index, bool done) => save(i.withCheck(day, index, done));

  /// 이동형 완료 되돌리기
  Future<void> undoRoll(Item previous) => save(previous);

  @override
  void dispose() {
    _pushTimer?.cancel();
    _authSub?.cancel();
    _stop();
    super.dispose();
  }
}
