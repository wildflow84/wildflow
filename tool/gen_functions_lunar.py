#!/usr/bin/env python3
"""lib/models/lunar_table.g.dart 의 음력 표를 서버 함수용 functions/lunar_table.js 로 옮긴다.
표는 앱과 서버가 같은 값을 써야 하므로, 앱 표가 바뀌면 이 스크립트를 다시 돌린다."""
import re

src = open('lib/models/lunar_table.g.dart', encoding='utf-8').read()
rows = re.findall(r'\[(\d+), (\d+), (\d+), (\d+), (\d+)\],', src)
out = ("// 자동 생성: tool/gen_functions_lunar.py (lib/models/lunar_table.g.dart 를 그대로 옮김)\n"
       "// 각 행: [음력해, 설날(1900-01-01부터의 일수), 윤달 월(없으면 0), 월길이 비트(30일=1), 월 개수]\n"
       "'use strict';\nconst lunarTableFirstYear = 1900;\nconst lunarTable = [\n")
for r in rows:
    out += "  [%s],\n" % ", ".join(r)
out += "];\nmodule.exports = { lunarTableFirstYear, lunarTable };\n"
open('functions/lunar_table.js', 'w', encoding='utf-8').write(out)
print(len(rows), 'rows')
