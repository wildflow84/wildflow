import 'package:flutter/material.dart';

import '../models/category.dart';

/// 팔레트 + 직접 입력(#RRGGBB)으로 색을 고르는 위젯.
class ColorChooser extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const ColorChooser({super.key, required this.value, required this.onChanged});

  @override
  State<ColorChooser> createState() => _ColorChooserState();
}

class _ColorChooserState extends State<ColorChooser> {
  late final _hex = TextEditingController(text: _toHex(widget.value));

  static String _toHex(int v) => (v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  static int? _parse(String s) {
    final t = s.replaceAll('#', '').trim();
    if (t.length != 6) return null;
    final v = int.tryParse(t, radix: 16);
    return v == null ? null : 0xFF000000 | v;
  }

  @override
  void didUpdateWidget(ColorChooser old) {
    super.didUpdateWidget(old);
    final parsed = _parse(_hex.text);
    if (parsed != widget.value) _hex.text = _toHex(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in colorPalette)
          GestureDetector(
            onTap: () => widget.onChanged(c),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                    color: widget.value == c ? Colors.white : Colors.transparent, width: 2.5),
              ),
              child: widget.value == c ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: Color(widget.value), shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 130,
          child: TextField(
            controller: _hex,
            maxLength: 7,
            decoration: const InputDecoration(
                prefixText: '#', labelText: '직접 입력', counterText: '', isDense: true),
            onChanged: (t) {
              final v = _parse(t);
              if (v != null) widget.onChanged(v);
            },
          ),
        ),
      ]),
    ]);
  }
}

/// 색을 하나 고르는 대화상자. 취소하면 null.
Future<int?> pickColor(BuildContext context, {required int initial}) {
  var current = initial;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('색상 선택'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: ColorChooser(value: current, onChanged: (v) => setS(() => current = v)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, current), child: const Text('선택')),
        ],
      ),
    ),
  );
}
