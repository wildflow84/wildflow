import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/item.dart';

/// Firestore 구조
///   users/{uid}                 { spaceId, name }
///   spaces/{spaceId}            { members: [uid], names: {uid: name} }
///   spaces/{spaceId}/items/{id} Item.toMap()
///
/// 프라이빗 보호는 firestore.rules가 서버에서 강제한다.
class Repository {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Stream<User?> get authChanges => _auth.authStateChanges();
  User? get user => _auth.currentUser;

  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      await _auth.signInWithPopup(provider);
    } else {
      await _auth.signInWithProvider(provider);
    }
  }

  Future<void> signOut() => _auth.signOut();

  /// 로그인한 사용자가 속한 space. 없으면 null.
  Future<String?> mySpaceId() async {
    final doc = await _db.collection('users').doc(user!.uid).get();
    return doc.data()?['spaceId'] as String?;
  }

  /// 새 space를 만든다. spaceId가 곧 초대 코드라서 추측 불가능한 랜덤 ID를 쓴다.
  Future<String> createSpace() async {
    final u = user!;
    final ref = _db.collection('spaces').doc();
    final batch = _db.batch();
    batch.set(ref, {
      'members': [u.uid],
      'names': {u.uid: u.displayName ?? '나'},
    });
    batch.set(_db.collection('users').doc(u.uid),
        {'spaceId': ref.id, 'name': u.displayName});
    await batch.commit();
    return ref.id;
  }

  /// 초대 코드(=spaceId)로 참여한다. 규칙상 최대 2명.
  Future<void> joinSpace(String spaceId) async {
    final u = user!;
    final ref = _db.collection('spaces').doc(spaceId.trim());
    await ref.update({
      'members': FieldValue.arrayUnion([u.uid]),
      'names.${u.uid}': u.displayName ?? '상대',
    });
    await _db.collection('users').doc(u.uid).set(
        {'spaceId': ref.id, 'name': u.displayName});
  }

  Stream<Map<String, String>> memberNames(String spaceId) => _db
      .collection('spaces')
      .doc(spaceId)
      .snapshots()
      .map((s) => Map<String, String>.from(s.data()?['names'] ?? const {}));

  /// 공유 항목 + 내 프라이빗 항목을 합쳐서 흘려준다.
  /// 보안 규칙이 쿼리 조건과 일치해야 해서 쿼리를 둘로 나눈다.
  Stream<List<Item>> watchItems(String spaceId) {
    final col = _db.collection('spaces').doc(spaceId).collection('items');
    final shared = col.where('visibility', isEqualTo: 'shared').snapshots();
    final mine = col.where('ownerUid', isEqualTo: user!.uid).snapshots();

    late StreamController<List<Item>> ctrl;
    List<Item> a = [], b = [];
    final subs = <StreamSubscription>[];
    void emit() {
      final map = {for (final i in [...a, ...b]) i.id: i};
      ctrl.add(map.values.toList());
    }

    ctrl = StreamController<List<Item>>(
      onListen: () {
        subs.add(shared.listen((s) {
          a = s.docs.map(Item.fromDoc).toList();
          emit();
        }, onError: ctrl.addError));
        subs.add(mine.listen((s) {
          b = s.docs.map(Item.fromDoc).toList();
          emit();
        }, onError: ctrl.addError));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return ctrl.stream;
  }

  Future<void> save(String spaceId, Item item) => _db
      .collection('spaces')
      .doc(spaceId)
      .collection('items')
      .doc(item.id.isEmpty ? null : item.id)
      .set(item.toMap());

  Future<void> delete(String spaceId, String id) =>
      _db.collection('spaces').doc(spaceId).collection('items').doc(id).delete();
}
