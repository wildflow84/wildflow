import 'package:flutter/material.dart';
import 'palette.dart';
import 'package:intl/intl.dart';

import '../models/lunar.dart';

/// 음력 날짜로 고르기: 음력 연/월(윤달 포함)/일을 고르면 같은 날의 양력 날짜를 돌려준다.
Future<DateTime?> pickLunarDate(BuildContext context, {required DateTime initial}) =>
    showDialog<DateTime>(context: context, builder: (_) => _LunarDialog(initial: initial));

class _LunarDialog extends StatefulWidget {
  final DateTime initial;
  const _LunarDialog({required this.initial});

  @override
  State<_LunarDialog> createState() => _LunarDialogState();
}

class _LunarDialogState extends State<_LunarDialog> {
  late int _year, _month, _day;
  late bool _leap;

  @override
  void initState() {
    super.initState();
    final l = solarToLunar(widget.initial) ?? solarToLunar(DateTime.now())!;
    _year = l.year;
    _month = l.month;
    _day = l.day;
    _leap = l.leap;
  }

  bool _exists(int y, int m, bool leap, int d) => lunarToSolar(y, m, d, leap: leap) != null;

  /// 해/월을 바꾼 뒤에도 없는 조합(윤달 없는 해, 29일까지인 달의 30일)이 되지 않게 맞춘다.
  void _fix() {
    if (_leap && !_exists(_year, _month, true, 1)) _leap = false;
    while (_day > 29 && !_exists(_year, _month, _leap, _day)) {
      _day--;
    }
  }

  @override
  Widget build(BuildContext context) {
    final solar = lunarToSolar(_year, _month, _day, leap: _leap);
    final hasLeap = _exists(_year, _month, true, 1);
    final maxDay = _exists(_year, _month, _leap, 30) ? 30 : 29;
    final startYear = solarToLunar(lunarRangeStart)!.year + 1;
    final endYear = solarToLunar(lunarRangeEnd)!.year - 1;
    return AlertDialog(
      title: const Text('음력으로 날짜 고르기'),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              flex: 5,
              child: DropdownButtonFormField<int>(
                initialValue: _year.clamp(startYear, endYear),
                decoration: const InputDecoration(labelText: '음력 연'),
                menuMaxHeight: 320,
                items: [
                  for (var y = endYear; y >= startYear; y--) DropdownMenuItem(value: y, child: Text('$y년')),
                ],
                onChanged: (v) => setState(() {
                  _year = v!;
                  _fix();
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<int>(
                initialValue: _month,
                decoration: const InputDecoration(labelText: '월'),
                menuMaxHeight: 320,
                items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text('$m월'))],
                onChanged: (v) => setState(() {
                  _month = v!;
                  _fix();
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<int>(
                key: ValueKey('d$maxDay'),
                initialValue: _day.clamp(1, maxDay),
                decoration: const InputDecoration(labelText: '일'),
                menuMaxHeight: 320,
                items: [for (var d = 1; d <= maxDay; d++) DropdownMenuItem(value: d, child: Text('$d일'))],
                onChanged: (v) => setState(() => _day = v!),
              ),
            ),
          ]),
          if (hasLeap)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('윤$_month월 (윤달)'),
              value: _leap,
              onChanged: (v) => setState(() {
                _leap = v;
                _fix();
              }),
            ),
          const SizedBox(height: 12),
          Text(
            solar == null ? '없는 날짜야' : '양력 ${DateFormat('y년 M월 d일 (E)', 'ko').format(solar)}',
            style: TextStyle(color: kSubtle),
          ),
          const SizedBox(height: 4),
          Text('반복은 등록 화면에서 "매년 음력 …"을 고르면 돼', style: TextStyle(fontSize: 12, color: kMuted)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: solar == null ? null : () => Navigator.pop(context, solar), child: const Text('확인')),
      ],
    );
  }
}
