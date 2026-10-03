import 'palette.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker, FixedExtentScrollController;
import 'package:flutter/material.dart';

/// 디지털 시간 선택: 시/분 휠(마우스 휠, 드래그 모두 가능) + 자주 쓰는 시각 버튼. 24시간제.
Future<TimeOfDay?> pickTimeDigital(BuildContext context, {required TimeOfDay initial}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (_) => _DigitalTimeDialog(initial: initial),
  );
}

class _DigitalTimeDialog extends StatefulWidget {
  final TimeOfDay initial;
  const _DigitalTimeDialog({required this.initial});

  @override
  State<_DigitalTimeDialog> createState() => _DigitalTimeDialogState();
}

class _DigitalTimeDialogState extends State<_DigitalTimeDialog> {
  late int _h = widget.initial.hour;
  late int _m = widget.initial.minute;
  late final _hc = FixedExtentScrollController(initialItem: _h);
  late final _mc = FixedExtentScrollController(initialItem: _m);

  static const _quick = [(7, 0), (8, 0), (9, 0), (12, 0), (18, 0), (21, 0)];

  static String _two(int v) => v.toString().padLeft(2, '0');

  void _set(int h, int m) {
    setState(() {
      _h = h;
      _m = m;
    });
    _hc.animateToItem(h, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    _mc.animateToItem(m, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  Widget _wheel(FixedExtentScrollController c, int count, ValueChanged<int> onChanged) {
    return SizedBox(
      width: 84,
      height: 150,
      child: CupertinoPicker(
        scrollController: c,
        itemExtent: 44,
        looping: true,
        magnification: 1.1,
        squeeze: 1.1,
        useMagnifier: true,
        backgroundColor: Colors.transparent,
        onSelectedItemChanged: onChanged,
        children: [
          for (var i = 0; i < count; i++)
            Center(child: Text(_two(i), style: const TextStyle(fontSize: 28, color: kInk))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hc.dispose();
    _mc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('시간 선택'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${_two(_h)}:${_two(_m)}',
            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 8),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _wheel(_hc, 24, (v) => setState(() => _h = v)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(':', style: TextStyle(fontSize: 28)),
          ),
          _wheel(_mc, 60, (v) => setState(() => _m = v)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final q in _quick)
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text('${_two(q.$1)}:${_two(q.$2)}'),
              onPressed: () => _set(q.$1, q.$2),
            ),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: () => Navigator.pop(context, TimeOfDay(hour: _h, minute: _m)),
          child: const Text('확인'),
        ),
      ],
    );
  }
}
