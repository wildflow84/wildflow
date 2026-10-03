import 'package:flutter/material.dart';

/// 앱 전체 색 (따뜻한 크림 테마). 화면 코드에서 색을 직접 쓰지 말고 여기 이름을 쓴다.
const kBg = Color(0xFFFBF5EA); // 바탕
const kCard = Colors.white; // 카드/칸
const kInk = Color(0xFF3A2E26); // 본문 글자
const kSubtle = Color(0xFF7A6B5D); // 보조 글자
const kMuted = Color(0xFF9A8B7D); // 흐린 글자
const kFaint = Color(0xFFC4B8AA); // 아주 흐린 글자/테두리
const kLine = Color(0xFFF0E6D6); // 구분선, 옅은 테두리
const kFill = Color(0xFFF4EBDC); // 옅은 채움
const kAccent = Color(0xFFD9772F); // 포인트 (순대 색)
const kRed = Color(0xFFD9534F); // 일요일/공휴일/삭제
const kBlue = Color(0xFF3D7DCA); // 토요일
const kGreen = Color(0xFF5FA05A); // 완료/놓기

/// 배경색 위에 올릴 글자색: 밝은 배경이면 짙은 색, 아니면 흰색
Color onColor(Color c) => c.computeLuminance() > 0.6 ? kInk : Colors.white;

/// 카드 그림자
const kCardShadow = Color(0x1F8A5A22);
