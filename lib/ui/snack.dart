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
