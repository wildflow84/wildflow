import 'package:flutter/material.dart';
import 'palette.dart';
import 'package:intl/intl.dart';

/// 날짜 선택. 기본 showDatePicker는 가로로 넓은 화면(PC)에서 제목이 줄바꿈되어 어색해서 직접 구성했다.
/// 제목은 한 줄, 달력은 CalendarDatePicker(월/연도 이동 포함), 하단에 "오늘" 바로가기.
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initial,
  DateTime? first,
  DateTime? last,
  String? title,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _DatePickerDialog(
      initial: initial,
      first: first ?? DateTime(1901, 1, 1),
      last: last ?? DateTime(2200, 12, 31),
      title: title,
    ),
  );
}

class _DatePickerDialog extends StatefulWidget {
  final DateTime initial, first, last;
  final String? title;
  const _DatePickerDialog({required this.initial, required this.first, required this.last, this.title});

  @override
  State<_DatePickerDialog> createState() => _DatePickerDialogState();
}

class _DatePickerDialogState extends State<_DatePickerDialog> {
  late DateTime _picked = DateTime(widget.initial.year, widget.initial.month, widget.initial.day);
  int _rev = 0; // "오늘"을 눌렀을 때 달력을 새로 그리기 위한 키

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('y년 M월 d일 (E)', 'ko');
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final canToday = !todayOnly.isBefore(widget.first) && !todayOnly.isAfter(widget.last);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (widget.title != null)
                      Text(widget.title!, style: TextStyle(fontSize: 12, color: kMuted)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(df.format(_picked),
                          maxLines: 1, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              CalendarDatePicker(
                key: ValueKey(_rev),
                initialDate: _picked,
                firstDate: widget.first,
                lastDate: widget.last,
                onDateChanged: (d) => setState(() => _picked = d),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  if (canToday)
                    TextButton(
                      onPressed: () => setState(() {
                        _picked = todayOnly;
                        _rev++;
                      }),
                      child: const Text('오늘'),
                    ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
                  FilledButton(onPressed: () => Navigator.pop(context, _picked), child: const Text('확인')),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
