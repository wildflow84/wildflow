'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { dayNumber, ymd, dateKeyOf, parseKey, solarToLunar } = require('./lunar');
const { holidayNamesOn } = require('./holidays');
const calc = require('./itemcalc');
const digest = require('./digest');

// ---------- 도우미 ----------
const KST = 9 * 3600 * 1000;
/** 한국시간 'yyyy-MM-dd'(+시:분) 의 시각 -> Firestore Timestamp 흉내 */
function ts(key, h = 0, mi = 0) {
  const [y, m, d] = key.split('-').map(Number);
  const ms = Date.UTC(y, m - 1, d, h, mi) - KST;
  return { toMillis: () => ms };
}
const nowAt = (key, h = 9, mi = 0) => ts(key, h, mi).toMillis();

// ---------- 앱(Dart)과 같은 결과인지: golden.json 은 Dart 코드(occursOn/KrCalendar/solarToLunar)가 만든 기준값 ----------
const golden = JSON.parse(fs.readFileSync(path.join(__dirname, 'golden', 'golden.json'), 'utf8'));

test('음력 변환이 앱과 같다 (표본)', () => {
  for (const [key, ly, lm, ld, leap] of golden.lunar) {
    const l = solarToLunar(parseKey(key));
    if (ly == null) assert.equal(l, null, key);
    else assert.deepEqual([l.year, l.month, l.day, l.leap], [ly, lm, ld, leap], key);
  }
});

test('반복 규칙/멀티데이/예외/종료일이 앱의 occursOn 과 같다', () => {
  const from = parseKey('2023-12-01'), to = parseKey('2028-12-31');
  for (const c of golden.cases) {
    const item = calc.toItem('x', {
      type: 'event',
      title: c.name,
      start: ts(c.start, 9),
      end: c.end ? ts(c.end, 0) : null,
      rule: c.rule,
      repeat: c.repeat,
      repeatUntil: c.until ? ts(c.until) : null,
      exceptions: c.exceptions,
      visibility: 'shared',
    });
    const got = [];
    for (let dn = from; dn <= to; dn++) if (calc.occursOn(item, dn)) got.push(dateKeyOf(dn));
    assert.deepEqual(got, c.days, c.name);
  }
});

test('공휴일/대체공휴일/명절/사용자 지정일이 앱의 달력과 같다 (2012~2034)', () => {
  const custom = golden.customDays.map((c) => ({ dn: parseKey(c.date), name: c.name, holiday: c.holiday }));
  const from = parseKey('2012-01-01'), to = parseKey('2034-12-31');
  for (let dn = from; dn <= to; dn++) {
    const key = dateKeyOf(dn);
    assert.deepEqual(holidayNamesOn(dn, custom), golden.holidays[key] || [], key);
  }
});

test('공휴일 표본: 2026 추석 연휴와 개천절 대체공휴일', () => {
  assert.deepEqual(holidayNamesOn(parseKey('2026-09-24')), ['추석 연휴']);
  assert.deepEqual(holidayNamesOn(parseKey('2026-09-25')), ['추석']);
  assert.deepEqual(holidayNamesOn(parseKey('2026-10-03')), ['개천절']);
  assert.deepEqual(holidayNamesOn(parseKey('2026-10-05')), ['개천절 대체공휴일']);
  assert.deepEqual(holidayNamesOn(parseKey('2026-10-21')), []);
});

// ---------- 요약 만들기 ----------
const NAMES = { me: '대희 아빠', mina: '민아' };
const CATS = [{ id: 'family', name: '가족', order: 2 }, { id: 'c1', name: '병원', order: 7 }];
function ev(id, over = {}) {
  return { id, data: { type: 'event', title: id, start: ts('2026-10-21', 15), allDay: false, visibility: 'shared', ownerUid: 'me', categories: ['default'], ...over } };
}
function td(id, over = {}) {
  return { id, data: { type: 'todo', title: id, start: ts('2026-10-21'), allDay: true, visibility: 'shared', ownerUid: 'me', assignee: '', categories: ['default'], ...over } };
}
function run(docs, extra = {}) {
  return digest.buildDigest({
    dateKey: '2026-10-21', nowMs: nowAt('2026-10-21', 7), memberUid: 'mina', memberName: '민아',
    names: NAMES, docs, categories: CATS, customDays: [], ...extra,
  });
}

test('private 항목은 어떤 경우에도 나오지 않는다 (소유자가 대상 구성원이어도)', () => {
  const docs = [
    ev('공개일정'),
    ev('나만일정', { visibility: 'private', ownerUid: 'mina' }),
    ev('남의나만일정', { visibility: 'private', ownerUid: 'me' }),
    ev('visibility없음', { visibility: undefined }),
    ev('이상한값', { visibility: 'PRIVATE' }),
    td('공개할일', { assignee: 'mina' }),
    td('나만할일', { visibility: 'private', ownerUid: 'mina' }),
    td('나만배정', { visibility: 'private', assignee: 'mina' }),
    td('나만반복', { visibility: 'private', ownerUid: 'mina', rule: { freq: 'daily', interval: 1 } }),
  ];
  const r = run(docs);
  const text = JSON.stringify(r);
  assert.deepEqual(r.events.map((e) => e.title), ['공개일정']);
  assert.deepEqual(r.todos.map((t) => t.title), ['공개할일']);
  for (const bad of ['나만', '남의나만', 'visibility없음', '이상한값']) assert.ok(!text.includes(bad), bad);
});

test('일정: 그날 발생하는 것만, 종일 먼저 그다음 시각순, 메모/좌표 같은 건 없음', () => {
  const docs = [
    ev('늦은일정', { start: ts('2026-10-21', 18, 30), end: ts('2026-10-21', 19, 0) }),
    ev('종일일정', { allDay: true, start: ts('2026-10-21') }),
    ev('이른일정', { start: ts('2026-10-21', 9), end: ts('2026-10-21', 10, 30), location: '병원', categories: ['family', 'c1'], note: '비밀메모', photoUrl: 'http://x', lat: 1, lng: 2 }),
    ev('내일일정', { start: ts('2026-10-22', 9) }),
    ev('어제끝난', { start: ts('2026-10-19', 9), end: ts('2026-10-20', 12), allDay: false }),
    ev('멀티데이', { allDay: true, start: ts('2026-10-20'), end: ts('2026-10-22') }),
  ];
  const r = run(docs);
  assert.deepEqual(r.events.map((e) => e.title), ['멀티데이', '종일일정', '이른일정', '늦은일정']);
  const early = r.events.find((e) => e.title === '이른일정');
  assert.equal(early.time, '09:00–10:30');
  assert.equal(early.location, '병원');
  assert.deepEqual(early.categories, ['가족', '병원']);
  assert.equal(early.ownerName, '대희 아빠');
  assert.equal(early.subscription, false);
  assert.equal(r.events.find((e) => e.title === '종일일정').time, null);
  assert.deepEqual(Object.keys(early).sort(), ['allDay', 'categories', 'id', 'location', 'ownerName', 'subscription', 'time', 'title']);
  assert.ok(!JSON.stringify(r).includes('비밀메모'));
});

test('구독(.ics) 항목은 subscription: true 와 구독 카테고리', () => {
  const r = run([ev('공휴일캘린더', { subscriptionId: 'sub1', categories: ['family'] })]);
  assert.equal(r.events[0].subscription, true);
  assert.deepEqual(r.events[0].categories, ['구독 캘린더']);
});

test('반복 일정: 매주/2주마다/음력/예외/종료일', () => {
  const weekly = ev('매주수', { start: ts('2026-10-07', 8), rule: { freq: 'weekly', interval: 1, weekdays: [3] } }); // 2026-10-21 은 수요일
  const biweekly = ev('격주', { start: ts('2026-10-14', 8), rule: { freq: 'weekly', interval: 2, weekdays: [3] } }); // 10/14, 10/28 -> 오늘 아님
  const skipped = ev('예외', { start: ts('2026-10-07', 8), rule: { freq: 'weekly', interval: 1, weekdays: [3] }, exceptions: ['2026-10-21'] });
  const ended = ev('종료', { start: ts('2026-10-07', 8), rule: { freq: 'weekly', interval: 1, weekdays: [3] }, repeatUntil: ts('2026-10-20') });
  const lunar = ev('음력', { allDay: true, start: ts('2026-02-17'), rule: { freq: 'yearly', interval: 1, lunar: true } }); // 음력 1/1
  const r = run([weekly, biweekly, skipped, ended, lunar]);
  assert.deepEqual(r.events.map((e) => e.title), ['매주수']);
  const lunarDay = digest.buildDigest({
    dateKey: '2027-02-07', nowMs: nowAt('2027-02-07'), memberUid: 'mina', memberName: '민아', names: NAMES, docs: [lunar], categories: [], customDays: [],
  });
  assert.deepEqual(lunarDay.events.map((e) => e.title), ['음력']);
  assert.ok(lunarDay.holidays.includes('설날'));
});

test('할 일: 담당자가 있으면 담당자, 없으면 만든 사람 (민아 몫만)', () => {
  const docs = [
    td('민아가만듦', { ownerUid: 'mina' }),
    td('아빠가만듦', { ownerUid: 'me' }),
    td('아빠가민아에게', { ownerUid: 'me', assignee: 'mina' }),
    td('민아가아빠에게', { ownerUid: 'mina', assignee: 'me' }),
  ];
  const r = run(docs);
  assert.deepEqual(r.todos.map((t) => t.title).sort(), ['민아가만듦', '아빠가민아에게']);
  const assigned = r.todos.find((t) => t.title === '아빠가민아에게');
  assert.equal(assigned.assigneeName, '민아');
  assert.equal(assigned.ownerName, '대희 아빠');
});

test('할 일: 오늘 마감 + 지난 미완료(overdue), 완료한 지난 건 빠짐, 미래 건 빠짐', () => {
  const docs = [
    td('오늘마감', { ownerUid: 'mina' }),
    td('지난미완료', { ownerUid: 'mina', start: ts('2026-10-18') }),
    td('지난완료', { ownerUid: 'mina', start: ts('2026-10-18'), done: true }),
    td('오늘완료', { ownerUid: 'mina', done: true }),
    td('내일마감', { ownerUid: 'mina', start: ts('2026-10-22') }),
    td('오늘3시', { ownerUid: 'mina', allDay: false, start: ts('2026-10-21', 15) }),
    td('아침지남', { ownerUid: 'mina', allDay: false, start: ts('2026-10-21', 6) }),
  ];
  const r = run(docs); // 지금 07:00
  const by = Object.fromEntries(r.todos.map((t) => [t.title, t]));
  assert.deepEqual(Object.keys(by).sort(), ['아침지남', '오늘3시', '오늘마감', '오늘완료', '지난미완료'].sort());
  assert.equal(by['오늘마감'].overdue, false);
  assert.equal(by['지난미완료'].overdue, true);
  assert.equal(by['아침지남'].overdue, true);
  assert.equal(by['오늘3시'].overdue, false);
  assert.equal(by['오늘3시'].time, '~15:00');
  assert.equal(by['오늘마감'].time, null);
  assert.equal(by['오늘완료'].done, true);
  assert.equal(by['오늘완료'].overdue, false);
  // 정렬: 종일 먼저, 그다음 시각순
  assert.deepEqual(r.todos.map((t) => t.title).slice(-2), ['아침지남', '오늘3시']);
});

test('완료 판정: 반복 할 일은 doneDates 에 그날이 있어야 완료, 이동형 반복은 다음 1회만', () => {
  const rec = td('매일약', { ownerUid: 'mina', start: ts('2026-10-01'), rule: { freq: 'daily', interval: 1 }, doneDates: ['2026-10-20'] });
  const recDone = td('매일약2', { ownerUid: 'mina', start: ts('2026-10-01'), rule: { freq: 'daily', interval: 1 }, doneDates: ['2026-10-21'] });
  const roll = td('이동형', { ownerUid: 'mina', start: ts('2026-10-21'), rollEvery: 2, rollUnit: 'day', doneDates: ['2026-10-19'] });
  const rollLater = td('이동형나중', { ownerUid: 'mina', start: ts('2026-10-25'), rollRule: { freq: 'weekly', interval: 1, weekdays: [7] } });
  const rollOverdue = td('이동형밀림', { ownerUid: 'mina', start: ts('2026-10-17'), rollEvery: 1, rollUnit: 'day' });
  const r = run([rec, recDone, roll, rollLater, rollOverdue]);
  const by = Object.fromEntries(r.todos.map((t) => [t.title, t]));
  assert.equal(by['매일약'].done, false);
  assert.equal(by['매일약'].overdue, false); // 반복 항목은 overdue 로 치지 않는다
  assert.equal(by['매일약2'].done, true);
  assert.equal(by['이동형'].done, false);
  assert.equal(by['이동형밀림'].overdue, true);
  assert.ok(!by['이동형나중']); // 아직 다음 회차가 아니다
  assert.equal(r.todos.filter((t) => t.title.startsWith('이동형')).length, 2);
});

test('체크리스트 남은 수와 D-day', () => {
  const plain = td('장보기', { ownerUid: 'mina', checklist: [{ t: '우유', d: true }, { t: '계란', d: false }, { t: '빵', d: false }], dday: true, start: ts('2026-10-21') });
  const overdue = td('지난것', { ownerUid: 'mina', start: ts('2026-10-18'), dday: true });
  const rec = td('반복체크', {
    ownerUid: 'mina', start: ts('2026-10-01'), rule: { freq: 'daily', interval: 1 },
    checklist: [{ t: 'a', d: false }, { t: 'b', d: false }], checksByDate: { '2026-10-21': ['a'], '2026-10-20': ['a', 'b'] },
  });
  const r = run([plain, overdue, rec]);
  const by = Object.fromEntries(r.todos.map((t) => [t.title, t]));
  assert.equal(by['장보기'].checklistLeft, 2);
  assert.equal(by['장보기'].dday, 'D-day');
  assert.equal(by['지난것'].dday, 'D+3');
  assert.equal(by['반복체크'].checklistLeft, 1);
  assert.equal(by['반복체크'].dday, null);
});

test('공휴일: 그날의 공휴일/명절/사용자 지정일 이름', () => {
  const r = digest.buildDigest({
    dateKey: '2026-09-25', nowMs: nowAt('2026-09-25'), memberUid: 'mina', memberName: '민아', names: NAMES, docs: [], categories: [],
    customDays: [{ date: ts('2026-09-25'), name: '가족 모임', holiday: false }],
  });
  assert.deepEqual(r.holidays, ['추석', '가족 모임']);
  const none = run([]);
  assert.deepEqual(none.holidays, []);
});

test('날짜 기본값은 한국시간 오늘', () => {
  // UTC 로는 10-20 16:00 이지만 한국은 10-21 01:00
  assert.equal(digest.todayKeyKst(Date.UTC(2026, 9, 20, 16, 0)), '2026-10-21');
  assert.equal(digest.todayKeyKst(Date.UTC(2026, 9, 20, 14, 59)), '2026-10-20');
});

// ---------- HTTP: 인증 / 입력 / 구성원 찾기 ----------
function fakeRes() {
  const res = { headers: {}, statusCode: 0, body: undefined };
  res.set = (k, v) => { res.headers[k.toLowerCase()] = v; return res; };
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (b) => { res.body = b; return res; };
  return res;
}
function fakeReq({ method = 'GET', auth, query = {} } = {}) {
  const headers = auth === undefined ? {} : { authorization: auth };
  return { method, query, headers, get: (k) => headers[k.toLowerCase()] };
}
const TOKEN = 'unit-test-token-0123456789';
function makeHandler(over = {}) {
  const logs = [];
  const handler = digest.createDigestHandler({
    getToken: () => TOKEN,
    findMember: async (m) => (m === '민아' || m === 'mina' ? { spaceId: 's1', uid: 'mina', name: '민아', names: NAMES } : { error: 'not_found' }),
    loadSpace: async () => ({ docs: [ev('공개일정'), ev('나만일정', { visibility: 'private', ownerUid: 'mina' })], categories: CATS, customDays: [] }),
    now: () => nowAt('2026-10-21', 7),
    log: (m) => logs.push(m),
    ...over,
  });
  return { handler, logs };
}

test('인증: 토큰이 없거나 다르거나 형식이 틀리면 401', async () => {
  const { handler } = makeHandler();
  for (const auth of [undefined, '', 'Bearer ', 'Bearer wrong', `Bearer ${TOKEN}x`, `Bearer ${TOKEN.slice(1)}`, TOKEN, `Basic ${TOKEN}`, `Bearer a ${TOKEN}`]) {
    const res = fakeRes();
    await handler(fakeReq({ auth, query: { member: '민아' } }), res);
    assert.equal(res.statusCode, 401, String(auth));
    assert.equal(res.headers['www-authenticate'], 'Bearer');
    assert.equal(res.body.events, undefined);
  }
});

test('인증: 토큰을 쿼리스트링으로 보내면 안 받는다', async () => {
  const { handler } = makeHandler();
  const res = fakeRes();
  await handler(fakeReq({ query: { member: '민아', token: TOKEN, DIGEST_TOKEN: TOKEN } }), res);
  assert.equal(res.statusCode, 401);
});

test('인증: 서버에 토큰이 설정돼 있지 않으면 빈 토큰으로도 못 들어온다', async () => {
  const { handler } = makeHandler({ getToken: () => '' });
  for (const auth of ['Bearer ', 'Bearer x', undefined]) {
    const res = fakeRes();
    await handler(fakeReq({ auth, query: { member: '민아' } }), res);
    assert.equal(res.statusCode, 401);
  }
});

test('GET 만 허용 (다른 메서드는 405)', async () => {
  const { handler } = makeHandler();
  for (const method of ['POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS', 'HEAD']) {
    const res = fakeRes();
    await handler(fakeReq({ method, auth: `Bearer ${TOKEN}`, query: { member: '민아' } }), res);
    assert.equal(res.statusCode, 405, method);
    assert.equal(res.headers.allow, 'GET');
  }
});

test('정상 요청: 200, CORS 헤더 없음, 캐시 금지, private 제외, 토큰은 로그에 안 남음', async () => {
  const { handler, logs } = makeHandler();
  const res = fakeRes();
  await handler(fakeReq({ auth: `Bearer ${TOKEN}`, query: { member: '민아' } }), res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.date, '2026-10-21');
  assert.equal(res.body.member, '민아');
  assert.deepEqual(res.body.events.map((e) => e.title), ['공개일정']);
  assert.equal(res.headers['cache-control'], 'no-store');
  assert.equal(Object.keys(res.headers).some((k) => k.startsWith('access-control-')), false);
  assert.ok(logs.length > 0);
  assert.ok(!logs.join('\n').includes(TOKEN));
});

test('입력 검증: member 없음/날짜 형식 오류는 400, 못 찾으면 404, 여러 개면 400', async () => {
  const { handler } = makeHandler();
  const auth = `Bearer ${TOKEN}`;
  let res = fakeRes();
  await handler(fakeReq({ auth, query: {} }), res);
  assert.equal(res.statusCode, 400);
  for (const date of ['2026-13-01', '2026-02-30', '20261021', 'abc', '2026-1-1', '']) {
    res = fakeRes();
    await handler(fakeReq({ auth, query: { member: '민아', date } }), res);
    assert.equal(res.statusCode, 400, date);
  }
  res = fakeRes();
  await handler(fakeReq({ auth, query: { member: '없는사람' } }), res);
  assert.equal(res.statusCode, 404);
  const amb = makeHandler({ findMember: async () => ({ error: 'ambiguous' }) });
  res = fakeRes();
  await amb.handler(fakeReq({ auth, query: { member: '민아' } }), res);
  assert.equal(res.statusCode, 400);
  // 날짜 지정
  res = fakeRes();
  await handler(fakeReq({ auth, query: { member: 'mina', date: '2026-09-25' } }), res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body.holidays, ['추석']);
});

test('읽기 중 오류는 500 으로 숨기고 내용을 새지 않는다', async () => {
  const { handler, logs } = makeHandler({ loadSpace: async () => { throw new Error('boom: secret detail'); } });
  const res = fakeRes();
  await handler(fakeReq({ auth: `Bearer ${TOKEN}`, query: { member: '민아' } }), res);
  assert.equal(res.statusCode, 500);
  assert.ok(!JSON.stringify(res.body).includes('boom'));
  assert.ok(!logs.join('\n').includes(TOKEN));
});

test('토큰 비교는 길이가 달라도 안전하게 거절한다', () => {
  assert.equal(digest.tokenMatches('a', 'b'), false);
  assert.equal(digest.tokenMatches('abc', 'abcd'), false);
  assert.equal(digest.tokenMatches('', ''), false);
  assert.equal(digest.tokenMatches(undefined, 'x'), false);
  assert.equal(digest.tokenMatches(TOKEN, TOKEN), true);
});

// ---------- Firestore 읽기 함수 (가짜 Firestore) ----------
function fakeDb(spaces, itemsBySpace = {}) {
  const snap = (docs) => ({ docs, forEach: (f) => docs.forEach(f), size: docs.length });
  const docSnap = (id, data) => ({ id, data: () => data });
  return {
    collection(name) {
      if (name !== 'spaces') throw new Error('unexpected ' + name);
      const q = (filter) => ({ get: async () => snap(Object.entries(spaces).filter(([, v]) => filter(v)).map(([id, v]) => docSnap(id, v))) });
      return {
        ...q(() => true),
        where: (field, op, val) => q((v) => field === 'members' && op === 'array-contains' && (v.members || []).includes(val)),
        doc: (spaceId) => ({
          collection: (sub) => {
            const rows = ((itemsBySpace[spaceId] || {})[sub]) || [];
            const mk = (list) => ({ get: async () => snap(list.map((r) => docSnap(r.id, r.data))) });
            return { ...mk(rows), where: (f, op, v) => { assert.equal(f, 'visibility'); assert.equal(op, '=='); assert.equal(v, 'shared'); return mk(rows.filter((r) => r.data.visibility === v)); } };
          },
        }),
      };
    },
  };
}

test('구성원 찾기: 이름표/uid 로 찾고, 없으면 404, 같은 이름이 여러 곳이면 모호함', async () => {
  const spaces = { s1: { members: ['me', 'mina'], names: NAMES }, s2: { members: ['x'], names: { x: '다른집' } } };
  const db = fakeDb(spaces);
  assert.deepEqual(await digest.findMemberInFirestore(db, '민아'), { spaceId: 's1', uid: 'mina', name: '민아', names: NAMES });
  const byUid = await digest.findMemberInFirestore(db, 'mina');
  assert.equal(byUid.spaceId, 's1');
  assert.equal(byUid.name, '민아');
  assert.deepEqual(await digest.findMemberInFirestore(db, '없음'), { error: 'not_found' });
  const dup = fakeDb({ ...spaces, s3: { members: ['m3'], names: { m3: '민아' } } });
  assert.deepEqual(await digest.findMemberInFirestore(dup, '민아'), { error: 'ambiguous' });
});

test('공간 읽기: 항목은 shared 만 쿼리하고, 카테고리/사용자 지정일을 함께 읽는다', async () => {
  const db = fakeDb({ s1: { members: ['mina'], names: NAMES } }, {
    s1: {
      items: [ev('공개일정'), ev('나만일정', { visibility: 'private' })],
      categories: [{ id: 'c1', data: { name: '병원', order: 7 } }],
      holidays: [{ id: 'h1', data: { date: ts('2026-10-21'), name: '쉬는날', holiday: true } }],
    },
  });
  const data = await digest.loadSpaceFromFirestore(db, 's1');
  assert.deepEqual(data.docs.map((d) => d.id), ['공개일정']);
  assert.deepEqual(data.categories, [{ id: 'c1', name: '병원', order: 7 }]);
  const r = digest.buildDigest({ dateKey: '2026-10-21', nowMs: nowAt('2026-10-21'), memberUid: 'mina', memberName: '민아', names: NAMES, ...data });
  assert.deepEqual(r.holidays, ['쉬는날']);
});
