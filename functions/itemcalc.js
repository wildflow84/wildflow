'use strict';
// 항목 계산: lib/models/item.dart 의 occursOn / isDoneOn / isOverdue / isMineTo / timeLabel / ddayLabel 의 JS 판.
// 서버는 한국시간(KST, UTC+9)으로 날짜를 본다. 앱의 시각은 폰(한국) 기준이라 같은 결과가 나온다.
const { dayNumber, ymd, dateKeyOf, parseKey } = require('./lunar');
const { ruleFromMap, ruleOccursOn, legacyRule } = require('./recurrence');

const KST_MS = 9 * 3600 * 1000;

function millis(ts) {
  if (ts == null) return 0;
  if (typeof ts.toMillis === 'function') return ts.toMillis();
  if (typeof ts._seconds === 'number') return ts._seconds * 1000;
  return Number(ts) || 0;
}

/** 시각(ms) -> 한국시간 날짜/시각 {dn, h, mi, ms} */
function kstParts(ms) {
  const t = new Date(ms + KST_MS);
  return {
    dn: dayNumber(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate()),
    h: t.getUTCHours(),
    mi: t.getUTCMinutes(),
    ms,
  };
}

/** 한국시간 dn일 0시의 시각(ms) */
function kstMidnightMs(dn) {
  const { y, m, d } = ymd(dn);
  return Date.UTC(y, m - 1, d) - KST_MS;
}

const hhmm = (p) => `${String(p.h).padStart(2, '0')}:${String(p.mi).padStart(2, '0')}`;

/** Firestore 문서 데이터 -> 계산용 항목 (Item.fromDoc 의 필요한 부분) */
function toItem(id, data) {
  const m = data || {};
  const startMs = millis(m.start);
  const start = kstParts(startMs);
  const endMs = m.end ? millis(m.end) : 0;
  const end = endMs ? kstParts(endMs) : null;
  const rule = m.rule && typeof m.rule === 'object' ? ruleFromMap(m.rule) : null;
  const repeatUntilMs = m.repeatUntil ? millis(m.repeatUntil) : 0;
  const list = (v) => (Array.isArray(v) ? v.map(String) : []);
  const item = {
    id,
    type: m.type === 'event' ? 'event' : 'todo',
    title: typeof m.title === 'string' ? m.title : '',
    location: typeof m.location === 'string' ? m.location : '',
    startMs,
    start,
    end,
    allDay: m.allDay !== false,
    done: m.done === true,
    doneDates: list(m.doneDates),
    categories: Array.isArray(m.categories) && m.categories.length > 0 ? list(m.categories) : [typeof m.category === 'string' ? m.category : 'default'],
    visibility: m.visibility,
    ownerUid: typeof m.ownerUid === 'string' ? m.ownerUid : '',
    repeat: typeof m.repeat === 'string' ? m.repeat : 'none',
    rule,
    repeatUntil: repeatUntilMs ? kstParts(repeatUntilMs).dn : null,
    exceptions: list(m.exceptions),
    rollEvery: typeof m.rollEvery === 'number' ? m.rollEvery : 0,
    rollRule: m.rollRule && typeof m.rollRule === 'object' ? ruleFromMap(m.rollRule) : null,
    checklist: Array.isArray(m.checklist) ? m.checklist.filter((c) => c && typeof c === 'object').map((c) => ({ text: String(c.t ?? ''), done: c.d === true })) : [],
    checksByDate: m.checksByDate && typeof m.checksByDate === 'object' ? m.checksByDate : {},
    assignee: typeof m.assignee === 'string' ? m.assignee : '',
    dday: m.dday === true,
    subscriptionId: typeof m.subscriptionId === 'string' && m.subscriptionId ? m.subscriptionId : null,
  };
  item.effectiveRule = rule || legacyRule(item.repeat, start.dn);
  item.isRecurring = item.effectiveRule != null;
  item.isRolling = item.rollRule != null || item.rollEvery > 0;
  return item;
}

/** [dn]일에 항목이 나타나는지 (반복 규칙 + 멀티데이) */
function occursOn(item, dn) {
  const s = item.start.dn;
  if (dn < s) return false;
  const rule = item.effectiveRule;
  if (rule) {
    if (item.repeatUntil != null && dn > item.repeatUntil) return false;
    if (item.exceptions.includes(dateKeyOf(dn))) return false;
    return ruleOccursOn(rule, s, dn);
  }
  const e = item.end ? item.end.dn : s;
  return dn <= e;
}

const isDoneOn = (item, dn) => (item.isRecurring ? item.doneDates.includes(dateKeyOf(dn)) : item.done);

/** 할 일이 마감을 넘겼는지. 시각이 있으면 그 시각 기준, 없으면 날짜가 오늘 이전일 때 */
function isOverdue(item, nowMs) {
  if (item.type !== 'todo' || item.isRecurring) return false;
  return item.allDay ? item.start.dn < kstParts(nowMs).dn : item.startMs < nowMs;
}

/** 할 일 담당: 담당자가 정해져 있으면 그 사람, 아니면 만든 사람 */
const isMineTo = (item, uid) => (item.assignee ? item.assignee === uid : item.ownerUid === uid);

/** 회차(날짜)별 남은 체크리스트 수 */
function checksLeftOn(item, dn) {
  if (!item.isRecurring) return item.checklist.filter((c) => !c.done).length;
  const done = Array.isArray(item.checksByDate[dateKeyOf(dn)]) ? item.checksByDate[dateKeyOf(dn)] : [];
  return item.checklist.filter((c) => !done.includes(c.text)).length;
}

const hasEndTime = (item) => !item.allDay && item.end != null && (item.end.h !== 0 || item.end.mi !== 0);

/** 일정 시간 표기: 종일이면 null. 예: "15:00", "15:00–16:30", "15:00 → 10/17 12:00" */
function eventTimeLabel(item) {
  if (item.allDay) return null;
  const s = hhmm(item.start);
  if (!hasEndTime(item)) return s;
  const e = item.end;
  const sameDay = item.isRecurring || e.dn === item.start.dn;
  if (sameDay) return `${s}–${hhmm(e)}`;
  const { m, d } = ymd(e.dn);
  return `${s} → ${m}/${d} ${hhmm(e)}`;
}

/** 할 일 시간 표기(마감): "~15:00". 종일이면 null */
const todoTimeLabel = (item) => (item.allDay ? null : `~${hhmm(item.start)}`);

/** D-day 문구: 오늘이면 "D-day", 앞이면 "D-3", 지났으면 "D+2" */
function ddayLabel(dn, todayDn) {
  const n = dn - todayDn;
  return n === 0 ? 'D-day' : n > 0 ? `D-${n}` : `D+${-n}`;
}

module.exports = {
  KST_MS, millis, kstParts, kstMidnightMs, toItem, occursOn, isDoneOn, isOverdue, isMineTo,
  checksLeftOn, eventTimeLabel, todoTimeLabel, ddayLabel, parseKey, dateKeyOf,
};
