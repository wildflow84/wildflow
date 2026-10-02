import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ourday/models/lunar.dart';
import 'package:ourday/ui/lunar_picker.dart';

void main() {
  testWidgets('음력 선택창: 열고 확인하면 같은 날 양력을 돌려준다', (t) async {
    await initializeDateFormatting('ko');
    DateTime? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => result = await pickLunarDate(c, initial: DateTime(2026, 6, 29)),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('음력으로 날짜 고르기'), findsOneWidget);
    expect(find.textContaining('양력'), findsOneWidget);
    await t.tap(find.text('확인'));
    await t.pumpAndSettle();
    expect(result, DateTime(2026, 6, 29));
    expect(solarToLunar(result!), isNotNull);
  });
}
