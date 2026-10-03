import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/ics.dart';
import '../models/item.dart' as m;
import '../models/item.dart' show Item;

/// 구글 캘린더 내보내기 파일(.zip 또는 .ics)을 골라 일정으로 가져온다.
Future<void> importFromGoogleCalendar(BuildContext context) async {
  final store = context.read<Store>();
  final messenger = ScaffoldMessenger.of(context);
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['ics', 'zip']);
  if (files.isEmpty) return;
  final cals = <IcsCalendar>[];
  try {
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final base = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      if ((f.extension ?? '').toLowerCase() == 'zip') {
        for (final e in ZipDecoder().decodeBytes(bytes)) {
          if (e.isFile && e.name.toLowerCase().endsWith('.ics')) {
            final name = e.name.split('/').last.replaceAll(RegExp(r'\.ics$', caseSensitive: false), '');
            cals.add(parseIcs(utf8.decode(e.content, allowMalformed: true), fallbackName: name));
          }
        }
      } else {
        cals.add(parseIcs(utf8.decode(bytes, allowMalformed: true), fallbackName: base));
      }
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('파일을 읽지 못했어: $e')));
    return;
  }
  final nonEmpty = cals.where((c) => c.events.isNotEmpty).toList();
  if (nonEmpty.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('가져올 일정이 없어')));
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => _ImportDialog(calendars: nonEmpty, store: store));
}

class _ImportDialog extends StatefulWidget {
  final List<IcsCalendar> calendars;
  final Store store;
  const _ImportDialog({required this.calendars, required this.store});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final Set<int> _picked = {
    // 공휴일 달력은 우리 달력에 이미 있으니 기본으로 뺀다
    for (var i = 0; i < widget.calendars.length; i++)
      if (!RegExp('휴일|holiday|공휴일', caseSensitive: false).hasMatch(widget.calendars[i].name)) i,
  };
  late m.Visibility _vis = widget.store.defaultVisibility;
  bool _busy = false;

  String _dedupKey(String title, DateTime start, bool allDay) => '$title|${start.millisecondsSinceEpoch}|$allDay';

  Future<void> _run() async {
    final s = widget.store;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final events = [for (final i in _picked) ...widget.calendars[i].events];
    final r = icsToItems(events, ownerUid: s.uid, visibility: _vis, categoryId: s.categories.first.id);
    // 이미 있는 일정(제목+시작 같음)은 건너뛴다: 같은 파일을 다시 가져와도 중복되지 않게
    final have = {for (final i in s.items) _dedupKey(i.title, i.start, i.allDay)};
    final fresh = <Item>[];
    for (final it in r.items) {
      if (have.add(_dedupKey(it.title, it.start, it.allDay))) fresh.add(it);
    }
    try {
      await s.importItems(fresh);
      if (!mounted) return;
      Navigator.pop(context);
      final skipped = r.items.length - fresh.length;
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text('${fresh.length}개 가져왔어'
            '${skipped > 0 ? ' · 이미 있어서 $skipped개 건너뜀' : ''}'
            '${r.simplified > 0 ? ' · 복잡한 반복 ${r.simplified}개는 단순하게 바뀌었어' : ''}'),
      ));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('가져오기에 실패했어: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = [for (final i in _picked) widget.calendars[i].events.length].fold<int>(0, (a, b) => a + b);
    return AlertDialog(
      title: const Text('구글 캘린더 가져오기'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('가져올 캘린더', style: TextStyle(color: Colors.white70)),
            for (var i = 0; i < widget.calendars.length; i++)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _picked.contains(i),
                title: Text(widget.calendars[i].name),
                subtitle: Text('${widget.calendars[i].events.length}개'),
                onChanged: _busy ? null : (v) => setState(() => v == true ? _picked.add(i) : _picked.remove(i)),
              ),
            const SizedBox(height: 8),
            const Text('공개 범위', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            SegmentedButton<m.Visibility>(
              segments: const [
                ButtonSegment(value: m.Visibility.private, icon: Icon(Icons.lock), label: Text('나만')),
                ButtonSegment(value: m.Visibility.shared, icon: Icon(Icons.people), label: Text('같이')),
              ],
              selected: {_vis},
              onSelectionChanged: _busy ? null : (v) => setState(() => _vis = v.first),
            ),
            const SizedBox(height: 8),
            const Text('가져온 일정은 첫 번째 카테고리로 들어가. 같은 제목·시작 시각이 이미 있으면 건너뛰어.',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: _busy || _picked.isEmpty ? null : _run,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('$total개 가져오기'),
        ),
      ],
    );
  }
}
