import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/painting.dart' show Color;

import 'item.dart' as m;

/// 사용자가 만들고 고치는 카테고리. 공간(space) 전체가 공유한다.
/// [defaultVisibility]가 null이면 개인 설정의 기본 공개 범위를 따른다.
class Category {
  final String id, name;
  final int colorValue; // ARGB
  final m.Visibility? defaultVisibility;
  final int order;

  const Category({
    required this.id,
    required this.name,
    required this.colorValue,
    this.defaultVisibility,
    this.order = 0,
  });

  Color get color => Color(colorValue);

  Category copyWith({String? name, int? colorValue, m.Visibility? defaultVisibility, bool clearVisibility = false, int? order}) =>
      Category(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        defaultVisibility: clearVisibility ? null : (defaultVisibility ?? this.defaultVisibility),
        order: order ?? this.order,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'color': colorValue,
        'defaultVisibility': defaultVisibility?.name,
        'order': order,
      };

  factory Category.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final v = d['defaultVisibility'] as String?;
    return Category(
      id: doc.id,
      name: d['name'] ?? '',
      colorValue: (d['color'] as num?)?.toInt() ?? 0xFF6C74D8,
      defaultVisibility:
          v == null ? null : m.Visibility.values.firstWhere((e) => e.name == v, orElse: () => m.Visibility.shared),
      order: (d['order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 공간을 처음 열 때 한 번 채워 넣는 기본 카테고리. id는 기존 항목과 호환되도록 고정.
const defaultCategories = <Category>[
  Category(id: 'default', name: '일반', colorValue: 0xFF4A7BD9, order: 0), // 파랑
  Category(id: 'work', name: '업무', colorValue: 0xFFE8643C, order: 1), // 주황빨강
  Category(id: 'family', name: '가족', colorValue: 0xFF3FA45B, order: 2), // 초록
  Category(id: 'money', name: '재테크', colorValue: 0xFFE3A21A, order: 3), // 노랑
  Category(id: 'travel', name: '여행', colorValue: 0xFF8E5BD9, order: 4), // 보라
  Category(id: 'kid', name: '아이', colorValue: 0xFFE5588C, order: 5), // 분홍
];

/// 예전 기본 색 (아직 안 바꾼 기본 카테고리는 새 기본 색으로 한 번 바꿔 준다)
const oldDefaultCategoryColors = <String, int>{
  'default': 0xFF6C74D8,
  'work': 0xFFE8794B,
  'family': 0xFF8DB04A,
  'money': 0xFFE3B341,
  'travel': 0xFF3FA796,
  'kid': 0xFFD06A9E,
};

/// 구독(.ics)으로 들어온 일정이 항상 속하는 고정 카테고리. 저장소에는 없고 앱이 내장한다.
const subscriptionCategoryId = 'subscription';
const subscriptionCategory = Category(id: subscriptionCategoryId, name: '구독 캘린더', colorValue: 0xFF6B7A8F, order: 999);

/// 색 선택에 쓰는 기본 팔레트 (어두운 배경에서 잘 보이는 색)
const colorPalette = <int>[
  0xFF6C74D8, 0xFF4C6EF5, 0xFF3FA796, 0xFF2FB5C9, 0xFF8DB04A, 0xFFB5C94A,
  0xFFE3B341, 0xFFE8A95B, 0xFFE8794B, 0xFFE5603E, 0xFFD06A9E, 0xFFC04BC0,
  0xFF9B6BE8, 0xFF7E8AA8, 0xFFB08968, 0xFF5E9B8F, 0xFFCC5555, 0xFF8A8FA3,
];
