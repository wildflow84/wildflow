'use strict';
// 반복 규칙 계산: lib/models/recurrence.dart 의 JS 판 (matches / occursOn / lastOccurrence / nextAfter).
// 날짜는 모두 일수(dn, lunar.js 참고)다.
const { dayNumber, ymd, parseKey, solarToLunar, lunarToSolar } = require('./lunar');

const FREQS = ['daily', 'weekly', 'monthly', 'yearly'];

/** Firestore 에 저장된 규칙 맵 -> 규칙 객체 (Recurrence.fromMap) */
function ruleFromMap(m) {
  if (!m || typeof m !== 'object') return null;
  const num = (v) => (typeof v === 'number' ? Math.trunc(v) : null);
  const interval = Math.min(999, Math.max(1, num(m.interval) ?? 1));
  return {
    freq: FREQS.includes(m.freq) ? m.freq : 'daily',
    interval,
    weekdays: Array.isArray(m.weekdays) ? m.weekdays.map(Number) : [],
    monthDays: Array.isArray(m.monthDays) ? m.monthDays.map(Number) : [],
    nth: num(m.nth),
    nthWeekday: num(m.nthWeekday),
    clampMonthEnd: m.clamp === true,
    until: m.until == null ? null : parseKey(m.until),
    count: num(m.count),
    lunar: m.lunar === true,
  };
}

function daysIn(y, m) {
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}
const isLeapYear = (y) => (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
// 일요일 기준 주 시작 (Dart: dayNumber(d) - d.weekday % 7)
const weekStart = (dn) => dn - (ymd(dn).wd % 7);
const mod = (a, n) => ((a % n) + n) % n;

function isNthWeekday(r) {
  return r.freq === 'monthly' && r.nth != null;
}

/** [start]에서 시작하는 규칙이 [day]에 해당하는지 (종료 조건, 예외 날짜는 보지 않음) */
function matches(r, start, day) {
  const s = ymd(start), d = ymd(day);
  if (day < start) return false;
  if (r.lunar && (r.freq === 'yearly' || r.freq === 'monthly')) return lunarMatch(r, start, day);
  switch (r.freq) {
    case 'daily':
      return mod(day - start, r.interval) === 0;
    case 'weekly': {
      const days = r.weekdays.length === 0 ? [s.wd] : r.weekdays;
      if (!days.includes(d.wd)) return false;
      return mod(Math.trunc((weekStart(day) - weekStart(start)) / 7), r.interval) === 0;
    }
    case 'monthly': {
      const months = (d.y - s.y) * 12 + d.m - s.m;
      if (mod(months, r.interval) !== 0) return false;
      return isNthWeekday(r) ? nthMatch(r, s, d) : dateMatch(r, s, d);
    }
    case 'yearly':
      if (mod(d.y - s.y, r.interval) !== 0) return false;
      if (d.m === s.m && d.d === s.d) return true;
      return r.clampMonthEnd && s.m === 2 && s.d === 29 && d.m === 2 && d.d === 28 && !isLeapYear(d.y);
  }
  return false;
}

function lunarMatch(r, start, day) {
  const ls = solarToLunar(start), ld = solarToLunar(day);
  if (!ls || !ld) return false;
  if (r.freq === 'yearly') {
    if (mod(ld.year - ls.year, r.interval) !== 0) return false;
    if (ld.leap || ld.month !== ls.month) return false; // 윤달은 평달에 챙긴다
  }
  if (ld.day === ls.day) return true;
  // 30일이 없는 달(29일까지)은 29일에
  return ls.day === 30 && ld.day === 29 && lunarToSolar(ld.year, ld.month, 30, ld.leap) === null;
}

function dateMatch(r, s, d) {
  const days = r.monthDays.length === 0 ? [s.d] : r.monthDays;
  const last = daysIn(d.y, d.m);
  for (const md of days) {
    if (md === -1 && d.d === last) return true;
    if (md > 0) {
      if (md === d.d) return true;
      if (r.clampMonthEnd && md > last && d.d === last) return true;
    }
  }
  return false;
}

function nthMatch(r, s, d) {
  if (d.wd !== (r.nthWeekday ?? s.wd)) return false;
  const last = daysIn(d.y, d.m);
  if (r.nth === -1) return d.d + 7 > last;
  return Math.trunc((d.d - 1) / 7) + 1 === r.nth;
}

const lastCache = new Map();

/** 횟수 종료일 때 마지막 발생일(일수). 횟수 종료가 아니거나 못 찾으면 null */
function lastOccurrence(r, start) {
  if (r.count == null) return null;
  const key = JSON.stringify(r) + '#' + start;
  if (lastCache.has(key)) return lastCache.get(key);
  let left = r.count;
  let d = start;
  let result = null;
  for (let i = 0; i < 366 * 120; i++) {
    if (r.until != null && d > r.until) break;
    if (matches(r, start, d) && --left === 0) {
      result = d;
      break;
    }
    d++;
  }
  lastCache.set(key, result);
  return result;
}

/** 종료 조건까지 포함한 발생 여부 (예외 날짜는 보지 않음) */
function ruleOccursOn(r, start, day) {
  if (day < start) return false;
  if (r.until != null && day > r.until) return false;
  if (!matches(r, start, day)) return false;
  if (r.count != null) {
    const last = lastOccurrence(r, start);
    if (last == null || day > last) return false;
  }
  return true;
}

/** [anchor] 기준으로 [after] 다음 날부터 처음 맞는 날짜. 없으면 null */
function nextAfter(r, anchor, after) {
  let d = after + 1;
  for (let i = 0; i < 366 * 9; i++) {
    if (r.until != null && d > r.until) return null;
    if (matches(r, anchor, d)) return d;
    d++;
  }
  return null;
}

/** 이전 버전의 단순 반복을 같은 의미의 규칙으로 (legacyRule) */
function legacyRule(repeat, startDn) {
  const base = { interval: 1, weekdays: [], monthDays: [], nth: null, nthWeekday: null, clampMonthEnd: false, until: null, count: null, lunar: false };
  switch (repeat) {
    case 'daily':
      return { ...base, freq: 'daily' };
    case 'weekly':
      return { ...base, freq: 'weekly', weekdays: [ymd(startDn).wd] };
    case 'monthly':
      return { ...base, freq: 'monthly', monthDays: [ymd(startDn).d], clampMonthEnd: true };
    case 'yearly':
      return { ...base, freq: 'yearly', clampMonthEnd: true };
    default:
      return null;
  }
}

module.exports = { ruleFromMap, matches, ruleOccursOn, lastOccurrence, nextAfter, legacyRule, dayNumber };
