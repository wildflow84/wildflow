import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recurrence.dart';
import 'date_picker.dart';

/// 구글 캘린더의 "맞춤 반복"과 같은 구성: 간격 / 요일 / 매월 날짜·요일 기준 / 종료.
Future<Recurrence?> showRecurrenceEditor(BuildContext context,
    {required DateTime start, Recurrence? initial}) {
  return showDialog<Recurrence>(
    context: context,
    builder: (_) => _RecurrenceDialog(start: start, initial: initial),
  );
}

enum _EndKind { never, until, count }

enum _MonthMode { date, weekday }

class _RecurrenceDialog extends StatefulWidget {
  final DateTime start;
  final Recurrence? initial;
  const _RecurrenceDialog({required this.start, this.initial});

  @override
  State<_RecurrenceDialog> createState() => _RecurrenceDialogState();
}

class _RecurrenceDialogState extends State<_RecurrenceDialog> {
  late DateTime s = DateTime(widget.start.year, widget.start.month, widget.start.day);

  late Freq _freq = widget.initial?.freq ?? Freq.weekly;
  late int _interval = widget.initial?.interval ?? 1;
  late final Set<int> _weekdays = {
    ...(widget.initial?.weekdays.isNotEmpty == true ? widget.initial!.weekdays : [s.weekday])
  };
  late _MonthMode _monthMode = widget.initial?.isNthWeekday == true ? _MonthMode.weekday : _MonthMode.date;
  late final Set<int> _monthDays = {
    ...(widget.initial?.monthDays.isNotEmpty == true ? widget.initial!.monthDays : [s.day])
  };
  late int _nth = widget.initial?.nth ?? (nthOfMonth(s) > 4 ? -1 : nthOfMonth(s));
  late int _nthWeekday = widget.initial?.nthWeekday ?? s.weekday;
  late bool _clamp = widget.initial?.clampMonthEnd ?? false;
  late _EndKind _end = widget.initial?.until != null
      ? _EndKind.until
      : widget.initial?.count != null
          ? _EndKind.count
          : _EndKind.never;
  late DateTime _until = widget.initial?.until ?? DateTime(s.year, s.month + 3, s.day);
  late final _countCtl = TextEditingController(text: '${widget.initial?.count ?? 10}');

  int get _count => (int.tryParse(_countCtl.text) ?? 10).clamp(1, 999);

  Recurrence _build() {
    return Recurrence(
      freq: _freq,
      interval: _interval,
      weekdays: _freq == Freq.weekly ? (_weekdays.toList()..sort()) : const [],
      monthDays: _freq == Freq.monthly && _monthMode == _MonthMode.date ? (_monthDays.toList()..sort()) : const [],
      nth: _freq == Freq.monthly && _monthMode == _MonthMode.weekday ? _nth : null,
      nthWeekday: _freq == Freq.monthly && _monthMode == _MonthMode.weekday ? _nthWeekday : null,
      clampMonthEnd: _freq == Freq.monthly && _monthMode == _MonthMode.date && _clamp,
      lunar: widget.initial?.lunar == true && _freq == widget.initial!.freq,
      until: _end == _EndKind.until ? _until : null,
      count: _end == _EndKind.count ? _count : null,
    );
  }

  @override
  void dispose() {
    _countCtl.dispose();
    super.dispose();
  }

  static const _unit = {Freq.daily: '일', Freq.weekly: '주', Freq.monthly: '개월', Freq.yearly: '년'};

  Widget _section(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
          const SizedBox(height: 8),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final rule = _build();
    return AlertDialog(
      title: const Text('반복 설정'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 간격
            Row(children: [
              const Text('반복 간격'),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _interval,
                items: [for (var n = 1; n <= 30; n++) DropdownMenuItem(value: n, child: Text('$n'))],
                onChanged: (v) => setState(() => _interval = v!),
              ),
              const SizedBox(width: 8),
              DropdownButton<Freq>(
                value: _freq,
                items: [for (final f in Freq.values) DropdownMenuItem(value: f, child: Text(_unit[f]!))],
                onChanged: (v) => setState(() => _freq = v!),
              ),
              const SizedBox(width: 8),
              const Text('마다'),
            ]),

            // 주: 요일
            if (_freq == Freq.weekly)
              _section(
                '반복 요일',
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  for (final wd in const [7, 1, 2, 3, 4, 5, 6]) // 일요일부터
                    _DayDot(
                      label: Recurrence.wdShort(wd),
                      selected: _weekdays.contains(wd),
                      size: 34,
                      color: wd == 7 ? Colors.redAccent : wd == 6 ? Colors.lightBlueAccent : null,
                      onTap: () => setState(() {
                        if (_weekdays.contains(wd)) {
                          if (_weekdays.length > 1) _weekdays.remove(wd); // 최소 하나
                        } else {
                          _weekdays.add(wd);
                        }
                      }),
                    ),
                ]),
              ),

            // 월: 날짜 / 요일 기준
            if (_freq == Freq.monthly) ...[
              _section(
                '매월 반복 기준',
                SegmentedButton<_MonthMode>(
                  segments: const [
                    ButtonSegment(value: _MonthMode.date, label: Text('날짜')),
                    ButtonSegment(value: _MonthMode.weekday, label: Text('요일')),
                  ],
                  selected: {_monthMode},
                  onSelectionChanged: (v) => setState(() => _monthMode = v.first),
                ),
              ),
              if (_monthMode == _MonthMode.date) ...[
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 7,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (var d = 1; d <= 31; d++)
                      _DayDot(
                        label: '$d',
                        selected: _monthDays.contains(d),
                        onTap: () => setState(() {
                          if (_monthDays.contains(d)) {
                            if (_monthDays.length > 1) _monthDays.remove(d);
                          } else {
                            _monthDays.add(d);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                FilterChip(
                  label: const Text('마지막 날 (말일)'),
                  selected: _monthDays.contains(-1),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _monthDays.add(-1);
                    } else if (_monthDays.length > 1) {
                      _monthDays.remove(-1);
                    }
                  }),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('없는 날짜는 말일로 (예: 31일 → 2월 28일)'),
                  value: _clamp,
                  onChanged: (v) => setState(() => _clamp = v ?? false),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Row(children: [
                  DropdownButton<int>(
                    value: _nth,
                    items: [
                      for (final n in const [1, 2, 3, 4, -1])
                        DropdownMenuItem(value: n, child: Text(Recurrence.nthLabel(n))),
                    ],
                    onChanged: (v) => setState(() => _nth = v!),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _nthWeekday,
                    items: [
                      for (var wd = 1; wd <= 7; wd++)
                        DropdownMenuItem(value: wd, child: Text(Recurrence.wdFull(wd))),
                    ],
                    onChanged: (v) => setState(() => _nthWeekday = v!),
                  ),
                ]),
              ],
            ],

            if (_freq == Freq.yearly)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('매년 ${s.month}월 ${s.day}일에 반복해.',
                    style: const TextStyle(color: Colors.white70)),
              ),

            // 종료
            _section(
              '종료',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<_EndKind>(
                  segments: const [
                    ButtonSegment(value: _EndKind.never, label: Text('안 함')),
                    ButtonSegment(value: _EndKind.until, label: Text('날짜')),
                    ButtonSegment(value: _EndKind.count, label: Text('횟수')),
                  ],
                  selected: {_end},
                  onSelectionChanged: (v) => setState(() => _end = v.first),
                ),
                if (_end == _EndKind.until) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('${_until.year}.${_until.month}.${_until.day}까지'),
                    onPressed: () async {
                      final d = await pickDate(context, initial: _until, first: s, title: '반복 종료일');
                      if (d != null) setState(() => _until = d);
                    },
                  ),
                ],
                if (_end == _EndKind.count) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _countCtl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('회 반복'),
                  ]),
                ],
              ]),
            ),

            // 요약
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.repeat, size: 18, color: Colors.white60),
                const SizedBox(width: 8),
                Expanded(child: Text(rule.describe(s), style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(context, _build()), child: const Text('확인')),
      ],
    );
  }
}

/// 요일/날짜를 고르는 동그란 토글
class _DayDot extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final double size;
  final VoidCallback onTap;
  const _DayDot(
      {required this.label, required this.selected, required this.onTap, this.color, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? accent : Colors.transparent,
          border: Border.all(color: selected ? accent : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Theme.of(context).colorScheme.onPrimary : color)),
      ),
    );
  }
}
