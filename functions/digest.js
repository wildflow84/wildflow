'use strict';
// 오늘의 요약(dailyDigest): 순수 로직과 HTTP 처리. Firebase 없이 테스트할 수 있게 데이터 읽기는 주입받는다.
const crypto = require('node:crypto');
const { dayNumber, parseKey, dateKeyOf } = require('./lunar');
const calc = require('./itemcalc');
const { holidayNamesOn } = require('./holidays');

// 앱의 기본 카테고리(lib/models/category.dart)와 구독 카테고리 이름
const DEFAULT_CATEGORY_NAMES = { default: '일반', work: '업무', family: '가족', money: '재테크', travel: '여행', kid: '아이' };
const SUBSCRIPTION_CATEGORY_NAME = '구독 캘린더';

/** 한국시간 기준 오늘 'yyyy-MM-dd' */
function todayKeyKst(nowMs) {
  return dateKeyOf(calc.kstParts(nowMs).dn);
}

function categoryNames(item, categories) {
  if (item.subscriptionId) return [SUBSCRIPTION_CATEGORY_NAME];
  const byId = { ...DEFAULT_CATEGORY_NAMES };
  for (const c of categories) if (c && c.id && c.name) byId[c.id] = c.name;
  const names = item.categories.filter((id) => byId[id]).map((id) => byId[id]);
  if (names.length > 0) return names;
  // 지워진 카테고리뿐이면 앱처럼 첫 카테고리로 보여 준다
  const ordered = [...categories].filter((c) => c && c.name).sort((a, b) => (a.order || 0) - (b.order || 0));
  return [ordered.length > 0 ? ordered[0].name : DEFAULT_CATEGORY_NAMES.default];
}

/** 종일 먼저, 그다음 시각순 */
function bySchedule(a, b) {
  const ka = a._allDay ? -1 : a._minutes;
  const kb = b._allDay ? -1 : b._minutes;
  return ka - kb || a._startMs - b._startMs || a.title.localeCompare(b.title, 'ko');
}

/**
 * 요약을 만든다.
 * @param {object} p
 * @param {string} p.dateKey 'yyyy-MM-dd'
 * @param {number} p.nowMs 지금 시각(ms)
 * @param {string} p.memberUid 대상 구성원 uid
 * @param {string} p.memberName 응답에 쓸 이름
 * @param {Object<string,string>} p.names uid -> 이름표
 * @param {Array<{id:string,data:object}>} p.docs 항목 문서들 (이 함수가 한 번 더 shared 만 남긴다)
 * @param {Array<{id:string,name:string,order?:number}>} p.categories
 * @param {Array<{date:any,name:string,holiday?:boolean}>} p.customDays
 */
function buildDigest({ dateKey, nowMs, memberUid, memberName, names, docs, categories = [], customDays = [] }) {
  const dn = parseKey(dateKey);
  if (dn == null) throw new Error('bad date');
  const today = calc.kstParts(nowMs).dn;
  // 오늘 요약이면 지금 시각 기준으로 마감 지남을 가리고, 다른 날짜면 그날 0시 기준
  const refMs = dn === today ? nowMs : calc.kstMidnightMs(dn);
  const nameOf = (uid) => (uid && names && names[uid]) || null;

  const events = [];
  const todos = [];
  for (const doc of docs) {
    const data = doc.data || {};
    // 프라이버시: 같이 보기(shared) 항목만. 소유자가 대상 구성원이어도 private 은 절대 내보내지 않는다.
    if (data.visibility !== 'shared') continue;
    if (!data.start) continue;
    const item = calc.toItem(doc.id, data);
    if (item.type === 'event') {
      if (!calc.occursOn(item, dn)) continue;
      events.push({
        id: item.id,
        title: item.title,
        allDay: item.allDay,
        time: calc.eventTimeLabel(item),
        location: item.location,
        categories: categoryNames(item, categories),
        ownerName: nameOf(item.ownerUid),
        subscription: item.subscriptionId != null,
        _allDay: item.allDay,
        _minutes: item.start.h * 60 + item.start.mi,
        _startMs: item.startMs,
      });
    } else {
      if (!calc.isMineTo(item, memberUid)) continue;
      const done = calc.isDoneOn(item, dn);
      const overdue = !done && calc.isOverdue(item, refMs);
      if (!calc.occursOn(item, dn) && !overdue) continue;
      // 이동형 반복은 문서에 다음 1회만 들어 있다 (완료하면 날짜가 다음으로 넘어간다)
      const shownDn = item.isRecurring ? dn : item.start.dn;
      todos.push({
        id: item.id,
        title: item.title,
        time: calc.todoTimeLabel(item),
        done,
        overdue,
        assigneeName: nameOf(item.assignee),
        ownerName: nameOf(item.ownerUid),
        checklistLeft: calc.checksLeftOn(item, dn),
        dday: item.dday ? calc.ddayLabel(shownDn, dn) : null,
        categories: categoryNames(item, categories),
        _allDay: item.allDay,
        _minutes: item.start.h * 60 + item.start.mi,
        _startMs: item.startMs,
      });
    }
  }
  events.sort(bySchedule);
  todos.sort(bySchedule);
  const strip = (o) => {
    const out = { ...o };
    delete out._allDay;
    delete out._minutes;
    delete out._startMs;
    return out;
  };

  const custom = customDays
    .map((c) => ({ dn: calc.kstParts(calc.millis(c.date)).dn, name: String(c.name || ''), holiday: c.holiday !== false }))
    .filter((c) => c.name);
  const holidays = [...new Set(holidayNamesOn(dn, custom))];

  return { date: dateKey, member: memberName, holidays, events: events.map(strip), todos: todos.map(strip) };
}

/** 상수 시간 토큰 비교 (길이가 달라도 같은 시간이 걸리게 해시로 비교) */
function tokenMatches(provided, expected) {
  if (typeof provided !== 'string' || typeof expected !== 'string' || !provided || !expected) return false;
  const a = crypto.createHash('sha256').update(provided).digest();
  const b = crypto.createHash('sha256').update(expected).digest();
  return crypto.timingSafeEqual(a, b);
}

function bearerOf(req) {
  const h = typeof req.get === 'function' ? req.get('authorization') : req.headers && req.headers.authorization;
  const m = /^Bearer[ \t]+(\S+)[ \t]*$/i.exec(typeof h === 'string' ? h : '');
  return m ? m[1] : '';
}

/**
 * HTTP 핸들러를 만든다.
 * @param {object} deps
 * @param {() => string} deps.getToken 서버에 저장된 토큰 (비어 있으면 모든 요청을 거절)
 * @param {(member: string) => Promise<{spaceId:string, uid:string, name:string, names:object}|{error:'not_found'|'ambiguous'}>} deps.findMember
 * @param {(spaceId: string) => Promise<{docs:Array, categories:Array, customDays:Array}>} deps.loadSpace
 * @param {() => number} [deps.now]
 * @param {(msg: string) => void} [deps.log] 토큰/헤더는 절대 넘기지 않는다
 */
function createDigestHandler({ getToken, findMember, loadSpace, now = Date.now, log = () => {} }) {
  const send = (res, status, body) => {
    res.set('Cache-Control', 'no-store');
    res.status(status).json(body);
  };
  return async function dailyDigestHandler(req, res) {
    if (req.method !== 'GET') {
      res.set('Allow', 'GET');
      return send(res, 405, { error: 'GET만 쓸 수 있어' });
    }
    if (!tokenMatches(bearerOf(req), getToken())) {
      res.set('WWW-Authenticate', 'Bearer');
      return send(res, 401, { error: '인증이 필요해' });
    }
    const q = req.query || {};
    const member = typeof q.member === 'string' ? q.member.trim() : '';
    if (!member || member.length > 128) return send(res, 400, { error: 'member 가 필요해' });
    const nowMs = now();
    let dateKey = todayKeyKst(nowMs);
    if (q.date !== undefined) {
      if (typeof q.date !== 'string' || parseKey(q.date) == null) return send(res, 400, { error: 'date 는 yyyy-MM-dd 형식이야' });
      dateKey = q.date;
    }
    try {
      const found = await findMember(member);
      if (found.error === 'not_found') return send(res, 404, { error: '구성원을 찾을 수 없어' });
      if (found.error) return send(res, 400, { error: '구성원이 여러 공간/이름에 걸쳐 있어서 uid 로 지정해 줘' });
      const data = await loadSpace(found.spaceId);
      const body = buildDigest({
        dateKey, nowMs, memberUid: found.uid, memberName: found.name, names: found.names,
        docs: data.docs, categories: data.categories, customDays: data.customDays,
      });
      log(`dailyDigest ok date=${dateKey} events=${body.events.length} todos=${body.todos.length}`);
      return send(res, 200, body);
    } catch (e) {
      log(`dailyDigest error ${e && e.message ? e.message : 'unknown'}`);
      return send(res, 500, { error: '요약을 만들지 못했어' });
    }
  };
}

/** Firestore 에서 구성원이 속한 공간 찾기: uid 로 먼저, 없으면 이름표로. */
async function findMemberInFirestore(db, member) {
  const hits = new Map(); // `${spaceId}/${uid}` -> info
  const consider = (snap) => {
    const sp = snap.data() || {};
    const members = Array.isArray(sp.members) ? sp.members : [];
    const names = sp.names && typeof sp.names === 'object' ? sp.names : {};
    for (const uid of members) {
      if (uid === member || names[uid] === member) {
        hits.set(`${snap.id}/${uid}`, { spaceId: snap.id, uid, name: names[uid] || member, names });
      }
    }
  };
  const byUid = await db.collection('spaces').where('members', 'array-contains', member).get();
  byUid.forEach(consider);
  if (hits.size === 0) {
    const all = await db.collection('spaces').get();
    all.forEach(consider);
  }
  if (hits.size === 0) return { error: 'not_found' };
  if (hits.size > 1) return { error: 'ambiguous' };
  return [...hits.values()][0];
}

/** 공간 데이터 읽기. 항목은 쿼리에서도 shared 만 가져온다 (buildDigest 가 한 번 더 거른다). */
async function loadSpaceFromFirestore(db, spaceId) {
  const base = db.collection('spaces').doc(spaceId);
  const [items, cats, hols] = await Promise.all([
    base.collection('items').where('visibility', '==', 'shared').get(),
    base.collection('categories').get(),
    base.collection('holidays').get(),
  ]);
  return {
    docs: items.docs.map((d) => ({ id: d.id, data: d.data() })),
    categories: cats.docs.map((d) => ({ id: d.id, name: d.data().name, order: d.data().order })),
    customDays: hols.docs.map((d) => d.data()),
  };
}

module.exports = {
  buildDigest, createDigestHandler, tokenMatches, todayKeyKst,
  findMemberInFirestore, loadSpaceFromFirestore, DEFAULT_CATEGORY_NAMES, SUBSCRIPTION_CATEGORY_NAME,
};
