'use strict';
// 음력 변환: lib/models/lunar.dart 의 JS 판. 날짜는 모두 "일수(dn)"로 다룬다 (1900-01-01 = 0, 달력상의 날짜라 시간대 없음).
const { lunarTableFirstYear, lunarTable } = require('./lunar_table');

const EPOCH = Date.UTC(1900, 0, 1);
const DAY_MS = 86400000;

/** 양력 y-m-d(m은 1~12) -> 일수 */
function dayNumber(y, m, d) {
  return Math.round((Date.UTC(y, m - 1, d) - EPOCH) / DAY_MS);
}

/** 일수 -> {y, m, d, wd(1=월 ... 7=일)} */
function ymd(dn) {
  const t = new Date(EPOCH + dn * DAY_MS);
  return { y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate(), wd: t.getUTCDay() === 0 ? 7 : t.getUTCDay() };
}

function dateKeyOf(dn) {
  const { y, m, d } = ymd(dn);
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

/** 'yyyy-MM-dd' -> 일수. 형식이 틀리면 null */
function parseKey(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || ''));
  if (!m) return null;
  const y = +m[1], mo = +m[2], d = +m[3];
  const dn = dayNumber(y, mo, d);
  const back = ymd(dn);
  return back.y === y && back.m === mo && back.d === d ? dn : null;
}

const years = (() => {
  const out = [];
  for (const r of lunarTable) {
    const [year, start, leapMonth, mask, n] = r;
    const starts = [], numbers = [], leaps = [];
    let cur = start, no = 1, isLeap = false;
    for (let i = 0; i < n; i++) {
      starts.push(cur);
      numbers.push(no);
      leaps.push(isLeap);
      cur += ((mask >> i) & 1) === 1 ? 30 : 29;
      if (leapMonth !== 0 && no === leapMonth && !isLeap) {
        isLeap = true; // 다음 달이 윤달
      } else {
        isLeap = false;
        no++;
      }
    }
    out.push({ year, starts, numbers, leaps, end: cur });
  }
  return out;
})();

/** 일수 -> {year, month, day, leap}. 표 범위 밖이면 null */
function solarToLunar(dn) {
  if (dn < years[0].starts[0] || dn >= years[years.length - 1].end) return null;
  let lo = 0, hi = years.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (years[mid].starts[0] <= dn) lo = mid;
    else hi = mid - 1;
  }
  const y = years[lo];
  let i = y.starts.length - 1;
  while (y.starts[i] > dn) i--;
  return { year: y.year, month: y.numbers[i], day: dn - y.starts[i] + 1, leap: y.leaps[i] };
}

/** 음력 -> 양력 일수. 없는 날짜면 null */
function lunarToSolar(year, month, day, leap = false) {
  const idx = year - lunarTableFirstYear;
  if (idx < 0 || idx >= years.length) return null;
  const y = years[idx];
  for (let i = 0; i < y.starts.length; i++) {
    if (y.numbers[i] === month && y.leaps[i] === leap) {
      const next = i + 1 < y.starts.length ? y.starts[i + 1] : y.end;
      if (day < 1 || day > next - y.starts[i]) return null;
      return y.starts[i] + day - 1;
    }
  }
  return null;
}

module.exports = { dayNumber, ymd, dateKeyOf, parseKey, solarToLunar, lunarToSolar };
