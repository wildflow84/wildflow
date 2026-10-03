import 'package:flutter/material.dart';

/// 앱 전체 색. 화면 코드에서 색을 직접 쓰지 말고 여기 이름(kBg 등)을 쓴다.
/// 밝은 테마(따뜻한 크림)와 어두운 테마를 [applyPalette]로 바꾼다.
class AppPalette {
  final Color bg; // 바탕
  final Color card; // 카드/칸
  final Color ink; // 본문 글자
  final Color subtle; // 보조 글자
  final Color muted; // 흐린 글자
  final Color faint; // 아주 흐린 글자/테두리
  final Color line; // 구분선, 옅은 테두리
  final Color fill; // 옅은 채움
  final Color accent; // 포인트 색
  final Color accentSoft; // 포인트 옅은 배경 (선택된 칩 등)
  final Color accentDeep; // 포인트 옅은 배경 위 글자
  final Color red; // 일요일/공휴일/삭제
  final Color blue; // 토요일
  final Color green; // 완료/놓기
  final Color shadow; // 카드 그림자
  final bool dark;
  const AppPalette({
    required this.bg,
    required this.card,
    required this.ink,
    required this.subtle,
    required this.muted,
    required this.faint,
    required this.line,
    required this.fill,
    required this.accent,
    required this.accentSoft,
    required this.accentDeep,
    required this.red,
    required this.blue,
    required this.green,
    required this.shadow,
    required this.dark,
  });
}

const lightPalette = AppPalette(
  bg: Color(0xFFFBF5EA),
  card: Colors.white,
  ink: Color(0xFF3A2E26),
  subtle: Color(0xFF7A6B5D),
  muted: Color(0xFF9A8B7D),
  faint: Color(0xFFC4B8AA),
  line: Color(0xFFF0E6D6),
  fill: Color(0xFFF4EBDC),
  accent: Color(0xFFD9772F),
  accentSoft: Color(0xFFFBE3CC),
  accentDeep: Color(0xFF8A4A14),
  red: Color(0xFFD9534F),
  blue: Color(0xFF3D7DCA),
  green: Color(0xFF5FA05A),
  shadow: Color(0x1F8A5A22),
  dark: false,
);

const darkPalette = AppPalette(
  bg: Color(0xFF15171D),
  card: Color(0xFF20242D),
  ink: Color(0xFFF3ECE4),
  subtle: Color(0xFFC2B8AD),
  muted: Color(0xFF948A80),
  faint: Color(0xFF5E5850),
  line: Color(0xFF2C313B),
  fill: Color(0xFF282C36),
  accent: Color(0xFFE88F4C),
  accentSoft: Color(0xFF4A3322),
  accentDeep: Color(0xFFFFD2AB),
  red: Color(0xFFFF8A84),
  blue: Color(0xFF79B6F5),
  green: Color(0xFF83CC7E),
  shadow: Color(0x66000000),
  dark: true,
);

AppPalette _p = lightPalette;

/// 지금 쓰는 팔레트를 바꾼다 (앱 맨 위에서 테마가 바뀔 때 부른다).
void applyPalette(bool dark) => _p = dark ? darkPalette : lightPalette;

bool get isDarkTheme => _p.dark;

Color get kBg => _p.bg;
Color get kCard => _p.card;
Color get kInk => _p.ink;
Color get kSubtle => _p.subtle;
Color get kMuted => _p.muted;
Color get kFaint => _p.faint;
Color get kLine => _p.line;
Color get kFill => _p.fill;
Color get kAccent => _p.accent;
Color get kAccentSoft => _p.accentSoft;
Color get kAccentDeep => _p.accentDeep;
Color get kRed => _p.red;
Color get kBlue => _p.blue;
Color get kGreen => _p.green;
Color get kCardShadow => _p.shadow;

/// 배경색 위에 올릴 글자색: 밝은 배경이면 짙은 갈색, 아니면 흰색 (테마와 상관없이 칩 색 기준)
Color onColor(Color c) => c.computeLuminance() > 0.6 ? const Color(0xFF3A2E26) : Colors.white;
