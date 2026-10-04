import 'package:flutter/material.dart';

/// 알림 메시지. 버튼(되돌리기 등)이 있어도 [seconds]초 뒤에 사라진다.
/// (Flutter 기본값은 버튼이 있는 알림을 닫을 때까지 유지하기 때문에 persist를 끈다.)
void showTimedSnack(
  ScaffoldMessengerState messenger,
  String text, {
  String? actionLabel,
  VoidCallback? onAction,
  int seconds = 3,
}) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    duration: Duration(seconds: seconds),
    persist: false,
    action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
  ));
}

/// 바텀시트 위에서도 보이는 안내 문구. 스낵바는 시트 뒤에 가려질 수 있어서 맨 위 오버레이에 띄운다.
void showOverlayToast(BuildContext context, String text, {int seconds = 3}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final bottom = MediaQuery.viewPaddingOf(context).bottom + 24;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 24,
      right: 24,
      bottom: bottom,
      child: IgnorePointer(
        child: Material(
          color: const Color(0xE6303030),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(Duration(seconds: seconds), () {
    if (entry.mounted) entry.remove();
  });
}
