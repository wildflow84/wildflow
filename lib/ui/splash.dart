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
                HelloArt(width: 300),
                SizedBox(height: 8),
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

/// 아기와 시츄 그림
class HelloArt extends StatelessWidget {
  final double width;
  const HelloArt({super.key, required this.width});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/hello.png',
        width: width,
        errorBuilder: (_, _, _) => Icon(Icons.calendar_month, size: width / 4, color: kAccent),
      );
}
