import 'package:flutter/material.dart';

import 'palette.dart';

/// 앱을 처음 열 때(로그인 확인, 데이터 불러오는 동안) 보여 주는 화면.
class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LogoMark(size: 120),
                SizedBox(height: 20),
                Text('순대희 캘린더', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kInk)),
                SizedBox(height: 6),
                Text('함께 쓰는 일정과 할 일', style: TextStyle(fontSize: 13, color: kMuted)),
                SizedBox(height: 28),
                SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: kAccent)),
              ],
            ),
          ),
        ),
      );
}

/// 앱 로고 (둥근 네모 아이콘)
class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.23),
          boxShadow: const [BoxShadow(color: kCardShadow, blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: Image.asset(
          'assets/brand/logo.png',
          width: size,
          height: size,
          errorBuilder: (_, _, _) => Icon(Icons.calendar_month, size: size * 0.7, color: kAccent),
        ),
      );
}
