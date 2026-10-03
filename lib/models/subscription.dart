import 'package:cloud_firestore/cloud_firestore.dart';

import 'item.dart' show Visibility;

/// 일정 구독: .ics 주소를 서버가 12시간마다 받아 와서 일정으로 넣어준다 (아스날 경기, 드라마 방영 일정 등).
class Subscription {
  final String id;
  final String name;
  final String url;
  final String categoryId;
  final Visibility visibility;
  final String ownerUid;
  final DateTime? lastSyncAt;
  final int? lastCount;
  final String? error;
  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    required this.ownerUid,
    this.categoryId = 'default',
    this.visibility = Visibility.shared,
    this.lastSyncAt,
    this.lastCount,
    this.error,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'url': url,
        'categoryId': categoryId,
        'visibility': visibility.name,
        'ownerUid': ownerUid,
      };

  factory Subscription.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Subscription(
      id: d.id,
      name: m['name'] ?? '',
      url: m['url'] ?? '',
      categoryId: m['categoryId'] ?? 'default',
      visibility: Visibility.values.firstWhere((v) => v.name == m['visibility'], orElse: () => Visibility.shared),
      ownerUid: m['ownerUid'] ?? '',
      lastSyncAt: (m['lastSyncAt'] as Timestamp?)?.toDate(),
      lastCount: (m['lastCount'] as num?)?.toInt(),
      error: m['error'] as String?,
    );
  }
}

/// 자주 쓰는 구독 주소 (주소를 직접 붙여넣어도 된다)
const subscriptionPresets = <(String, String)>[
  ('아스날 경기 일정', 'https://ics.fixtur.es/v2/arsenal.ics'),
  ('아틀레티코 마드리드 경기 일정', 'https://ics.fixtur.es/v2/atletico-madrid.ics'),
  ('아스날 경기 일정 (다른 서비스)', 'https://twentyclubs.com/calendars/arsenal.ics'),
];
