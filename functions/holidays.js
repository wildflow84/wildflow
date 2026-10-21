'use strict';
// 공휴일/명절: lib/models/kr_calendar.dart + special_holidays.dart 의 JS 판.
// 공휴일(대체공휴일 포함), 선거일·임시공휴일, 사용자가 추가한 날, 음력 명절만 계산한다 (24절기/기념일은 요약에 필요 없어 뺐다).
const { dayNumber, ymd, lunarToSolar } = require('./lunar');

/** 규칙으로 계산할 수 없는 공휴일: [연, 월, 일, 이름]. lib/models/special_holidays.dart 와 같아야 한다. */
const knownSpecialHolidays = [
  [2012, 4, 11, '국회의원선거일'],
  [2012, 12, 19, '대통령선거일'],
  [2014, 6, 4, '지방선거일'],
  [2015, 8, 14, '임시공휴일'],
  [2016, 4, 13, '국회의원선거일'],
  [2017, 5, 9, '대통령선거일'],
  [2017, 10, 2, '임시공휴일'],
  [2018, 6, 13, '지방선거일'],
  [2020, 4, 15, '국회의원선거일'],
  [2020, 8, 17, '임시공휴일'],
  [2022, 3, 9, '대통령선거일'],
  [2022, 6, 1, '지방선거일'],
  [2024, 4, 10, '국회의원선거일'],
  [2024, 10, 1, '임시공휴일(국군의날)'],
  [2025, 1, 27, '임시공휴일'],
  [2025, 6, 3, '대통령선거일'],
  [2026, 6, 3, '지방선거일'],
];

const KIND_ORDER = { holiday: 0, custom: 1, observance: 2 };

/**
 * [y]년의 표시 목록: Map(일수 -> [{name, kind}]).
 * [custom]: [{dn, name, holiday}] 사용자가 추가한 날 (그 해 것만 쓴다)
 */
function buildYear(y, custom = []) {
  const marks = new Map();
  const add = (dn, name, kind) => {
    if (!marks.has(dn)) marks.set(dn, []);
    const list = marks.get(dn);
    if (!list.some((m) => m.name === name)) list.push({ name, kind });
  };
  const groups = [];
  const holiday = (name, dns, rule = 'none') => {
    for (const dn of dns) add(dn, name, 'holiday');
    groups.push({ name, dns, rule });
  };
  const D = (m, d) => dayNumber(y, m, d);

  // ---- 양력 고정 공휴일 ----
  if (y >= 1949) holiday('신정', [D(1, 1)]);
  if (y >= 1949) holiday('삼일절', [D(3, 1)], 'weekendFrom2022');
  if (y >= 1975) holiday('어린이날', [D(5, 5)], 'children');
  if (y >= 1956) holiday('현충일', [D(6, 6)]);
  if (y >= 1949) holiday('광복절', [D(8, 15)], 'weekendFrom2021');
  if (y >= 1949) holiday('개천절', [D(10, 3)], 'weekendFrom2021');
  if (y >= 1949) holiday('성탄절', [D(12, 25)], 'weekendFrom2023');

  // 시기에 따라 공휴일이었다가 빠진(또는 부활한) 날
  const hangeul = (y >= 1949 && y <= 1990) || y >= 2013;
  // (공휴일이 아닌 해의 한글날/식목일/제헌절/국군의날은 기념일일 뿐이라 요약에서는 뺀다)
  if (hangeul) holiday('한글날', [D(10, 9)], 'weekendFrom2021');
  if (y >= 1949 && y <= 2005) holiday('식목일', [D(4, 5)]);
  if (y >= 1950 && y <= 2007) holiday('제헌절', [D(7, 17)]);
  if (y >= 1976 && y <= 1990) holiday('국군의날', [D(10, 1)]);

  // ---- 음력 공휴일 ----
  const seol = lunarToSolar(y, 1, 1);
  if (seol !== null) {
    const days = [seol - 1, seol, seol + 1];
    add(days[0], '설날 연휴', 'holiday');
    add(days[1], '설날', 'holiday');
    add(days[2], '설날 연휴', 'holiday');
    groups.push({ name: '설날', dns: days, rule: 'seolChuseok' });
  }
  const chuseok = lunarToSolar(y, 8, 15);
  if (chuseok !== null) {
    const days = [chuseok - 1, chuseok, chuseok + 1];
    add(days[0], '추석 연휴', 'holiday');
    add(days[1], '추석', 'holiday');
    add(days[2], '추석 연휴', 'holiday');
    groups.push({ name: '추석', dns: days, rule: 'seolChuseok' });
  }
  const buddha = lunarToSolar(y, 4, 8);
  if (buddha !== null && y >= 1975) holiday('부처님오신날', [buddha], 'weekendFrom2023');

  // ---- 임시공휴일 / 선거일 / 사용자 추가 ----
  for (const [sy, sm, sd, name] of knownSpecialHolidays) {
    if (sy === y) holiday(name, [dayNumber(sy, sm, sd)]);
  }
  for (const c of custom) {
    if (ymd(c.dn).y !== y) continue;
    if (c.holiday) holiday(c.name, [c.dn]);
    else add(c.dn, c.name, 'custom');
  }

  addSubstitutes(y, groups, marks);
  addLunarObservances(y, add);

  for (const list of marks.values()) list.sort((a, b) => KIND_ORDER[a.kind] - KIND_ORDER[b.kind]);
  return marks;
}

/** 대체공휴일: 규정의 시행 시점을 따른다 (kr_calendar.dart 의 _addSubstitutes) */
function addSubstitutes(y, groups, marks) {
  const coverage = new Map();
  for (const g of groups) for (const dn of g.dns) coverage.set(dn, (coverage.get(dn) || 0) + 1);
  const holidayDns = new Set(coverage.keys());
  groups.sort((a, b) => a.dns[0] - b.dns[0]);
  const SUN = 7, SAT = 6;
  const may4of2023 = dayNumber(2023, 5, 4);

  for (const g of groups) {
    if (g.rule === 'none') continue;
    const wds = g.dns.map((dn) => ymd(dn).wd);
    const hasSunday = wds.includes(SUN);
    const hasSaturday = wds.includes(SAT);
    const overlap = g.dns.some((dn) => coverage.get(dn) > 1);
    const first = g.dns[0];
    let ok = false;
    switch (g.rule) {
      case 'seolChuseok':
        ok = y >= 2014 && (hasSunday || overlap);
        break;
      case 'children':
        ok = (y >= 2014 && hasSunday) || (y >= 2018 && (hasSaturday || overlap));
        break;
      case 'weekendFrom2021':
        ok = y >= 2021 && (hasSunday || hasSaturday);
        break;
      case 'weekendFrom2022':
        ok = y >= 2022 && (hasSunday || hasSaturday);
        break;
      case 'weekendFrom2023':
        ok = first >= may4of2023 && (hasSunday || hasSaturday);
        break;
    }
    if (!ok) continue;
    let dn = g.dns[g.dns.length - 1] + 1;
    while (ymd(dn).wd >= SAT || holidayDns.has(dn)) dn++;
    holidayDns.add(dn);
    if (!marks.has(dn)) marks.set(dn, []);
    marks.get(dn).push({ name: `${g.name} 대체공휴일`, kind: 'holiday' });
  }
}

function addLunarObservances(y, add) {
  const lunar = (m, d, name) => {
    const s = lunarToSolar(y, m, d);
    if (s !== null) add(s, name, 'observance');
  };
  lunar(1, 15, '정월대보름');
  lunar(5, 5, '단오');
  lunar(7, 7, '칠석');
  lunar(7, 15, '백중');
  lunar(9, 9, '중양절');
}

/**
 * [dn]일의 공휴일/명절/사용자 지정일 이름들 (공휴일 -> 사용자 지정 -> 명절 순).
 * 앱처럼 그 날짜가 속한 해의 표에서 찾는다.
 */
function holidayNamesOn(dn, custom = []) {
  const y = ymd(dn).y;
  const marks = buildYear(y, custom).get(dn) || [];
  return marks.map((m) => m.name);
}

module.exports = { buildYear, holidayNamesOn, knownSpecialHolidays };
