import 'package:flutter/material.dart';

import 'coupons/coupon_screen.dart';

/// 달력과 따로 붙이는 기능들의 목록. 새 기능은 여기에 한 줄만 추가하면 "기능" 메뉴에 나타난다.
class AppFeature {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
  const AppFeature({required this.id, required this.title, required this.subtitle, required this.icon, required this.builder});
}

final List<AppFeature> appFeatures = [
  AppFeature(
    id: 'coupons',
    title: '쿠폰 판매',
    subtitle: '쿠폰 스크린샷을 올리면 번호를 저장하고, 판매 할 일로 만들어 줘',
    icon: Icons.local_activity_outlined,
    builder: (_) => const CouponScreen(),
  ),
];
