'use strict';
const test = require('node:test');
const assert = require('node:assert');
const b = require('./briefing');
const { runBriefing } = require('./briefing_run');

// ---------- 도우미 ----------
const KST = 9 * 3600 * 1000;
function ts(key, h = 0, mi = 0) {
  const [y, m, d] = key.split('-').map(Number);
  const ms = Date.UTC(y, m - 1, d, h, mi) - KST;
  return { toMillis: () => ms };
}
const NOW = ts('2026-10-22', 8, 0).toMillis(); // 2026-10-22(목) 08:00 KST
const NAMES = { me: '대희 아빠', mina: '민아' };
const ev = (id, over = {}) => ({ id, data: { type: 'event', title: id, start: ts('2026-10-22', 15), allDay: false, visibility: 'shared', ownerUid: 'me', ...over } });
const td = (id, over = {}) => ({ id, data: { type: 'todo', title: id, start: ts('2026-10-22'), allDay: true, visibility: 'shared', ownerUid: 'me', assignee: '', ...over } });
const body = (docs, extra = {}) => b.buildBody({ nowMs: NOW, docs, names: NAMES, customDays: [], ...extra });
const section = (text, key) => {
  const parts = text.split('\n\n');
  return parts.find((p) => p.startsWith(`## ${key} `)).split('\n');
};

// ---------- 형식 ----------
test('파일 형식: 헤더, 14일치 섹션, 항목 없는 날은 (항목 없음)', () => {
  const text = b.renderFile({ revision: 3, generatedAtMs: NOW, body: body([]) });
  const lines = text.split('\n');
  assert.deepEqual(lines.slice(0, 7), [
    '# OURDAY CALENDAR DIGEST', 'revision: 3', 'generated_at: 2026-10-22T08:00:00+09:00', 'scope: shared-only', 'days: 14', '', '## 2026-10-22 (목)',
  ]);
  const heads = lines.filter((l) => l.startsWith('## '));
  assert.equal(heads.length, 14);
  assert.equal(heads[0], '## 2026-10-22 (목)');
  assert.equal(heads[1], '## 2026-10-23 (금)');
  assert.equal(heads[13], '## 2026-11-04 (수)');
  assert.deepEqual(section(body([]), '2026-10-22'), ['## 2026-10-22 (목)', '(항목 없음)']);
  assert.ok(text.endsWith('\n'));
});

test('일정/할 일 줄 형식과 정렬 (종일 먼저, 그다음 시각순)', () => {
  const docs = [
    ev('늦은회의', { start: ts('2026-10-22', 18, 30), end: ts('2026-10-22', 19, 0), location: '회의실' }),
    ev('종일행사', { allDay: true, start: ts('2026-10-22'), ownerUid: 'mina' }),
    ev('아침', { start: ts('2026-10-22', 9), ownerUid: 'mina' }),
    td('종일할일', { assignee: 'mina' }),
    td('세시까지', { allDay: false, start: ts('2026-10-22', 15), ownerUid: 'mina' }),
  ];
  assert.deepEqual(section(body(docs), '2026-10-22'), [
    '## 2026-10-22 (목)',
    '- [E] 종일 | 종일행사 | 민아 |',
    '- [E] 09:00 | 아침 | 민아 |',
    '- [E] 18:30-19:00 | 늦은회의 | 대희아빠 | 회의실',
    '- [T] 종일 | 종일할일 | 민아 |',
    '- [T] ~15:00 | 세시까지 | 민아 |',
  ]);
});

test('제목/장소의 | 는 / 로, 줄바꿈은 공백으로', () => {
  const lines = section(body([ev('A|B|C', { location: '1층|로비\n옆' })]), '2026-10-22');
  assert.equal(lines[1], '- [E] 15:00 | A/B/C | 대희아빠 | 1층/로비 옆');
  assert.equal(b.cleanField('  x | y '), 'x / y');
});

// ---------- 프라이버시 ----------
test('private 항목은 어떤 경우에도 파일에 나오지 않는다 (소유자/담당자가 누구든)', () => {
  const docs = [
    ev('공개일정'),
    ev('나만일정', { visibility: 'private', ownerUid: 'mina' }),
    ev('아빠나만일정', { visibility: 'private', ownerUid: 'me' }),
    ev('값없음', { visibility: undefined }),
    ev('이상한값', { visibility: 'PRIVATE' }),
    td('나만할일', { visibility: 'private', ownerUid: 'mina' }),
    td('나만배정', { visibility: 'private', assignee: 'mina' }),
    td('나만반복', { visibility: 'private', rule: { freq: 'daily', interval: 1 } }),
    td('나만지난', { visibility: 'private', start: ts('2026-10-10') }),
    ev('나만여러날', { visibility: 'private', start: ts('2026-10-22'), end: ts('2026-10-25'), allDay: true }),
  ];
  const text = b.renderFile({ revision: 1, generatedAtMs: NOW, body: body(docs) });
  assert.ok(text.includes('공개일정'));
  for (const bad of ['나만', '값없음', '이상한값']) assert.ok(!text.includes(bad), bad);
});

// ---------- 소유자/담당자 ----------
test('이름 정규화: 공백 제거, 담당자가 있으면 담당자, 모르면 공통', () => {
  assert.equal(b.normalizeName('대희 아빠'), '대희아빠');
  assert.equal(b.normalizeName(' 민 아 '), '민아');
  const docs = [
    td('아빠가만든것', { ownerUid: 'me' }),
    td('민아에게맡김', { ownerUid: 'me', assignee: 'mina' }),
    td('주인모름', { ownerUid: 'ghost' }),
    td('주인없음', { ownerUid: '' }),
  ];
  const lines = section(body(docs), '2026-10-22');
  assert.ok(lines.includes('- [T] 종일 | 아빠가만든것 | 대희아빠 |'));
  assert.ok(lines.includes('- [T] 종일 | 민아에게맡김 | 민아 |'));
  assert.ok(lines.includes('- [T] 종일 | 주인모름 | 공통 |'));
  assert.ok(lines.includes('- [T] 종일 | 주인없음 | 공통 |'));
});

// ---------- 반복 / 음력 / 멀티데이 ----------
test('반복: 매주, 예외 날짜, 종료일, 멀티데이, 이동형은 다음 1회만', () => {
  const docs = [
    ev('매주목', { allDay: true, start: ts('2026-10-01'), rule: { freq: 'weekly', interval: 1, weekdays: [4] }, exceptions: ['2026-10-29'] }),
    ev('종료됨', { allDay: true, start: ts('2026-10-01'), rule: { freq: 'daily', interval: 1 }, repeatUntil: ts('2026-10-23') }),
    ev('출장', { allDay: true, start: ts('2026-10-23'), end: ts('2026-10-25') }),
    ev('긴회의', { start: ts('2026-10-24', 14), end: ts('2026-10-25', 11, 0) }),
    td('약먹기', { start: ts('2026-10-26'), rollEvery: 1, rollUnit: 'day' }),
  ];
  const text = body(docs);
  assert.ok(section(text, '2026-10-22').includes('- [E] 종일 | 매주목 | 대희아빠 |'));
  assert.ok(!section(text, '2026-10-29').some((l) => l.includes('매주목'))); // 제외한 날
  assert.ok(section(text, '2026-10-22').some((l) => l.includes('매주목'))); // 반복 첫 주기
  assert.ok(section(text, '2026-11-04').every((l) => !l.includes('매주목'))); // 수요일이라 해당 없음
  assert.ok(section(text, '2026-10-23').some((l) => l.includes('종료됨')));
  assert.ok(!section(text, '2026-10-24').some((l) => l.includes('종료됨'))); // repeatUntil 다음 날
  for (const d of ['2026-10-23', '2026-10-24', '2026-10-25']) assert.ok(section(text, d).some((l) => l.includes('| 출장 |')), d);
  assert.ok(!section(text, '2026-10-26').some((l) => l.includes('| 출장 |')));
  // 여러 날 시각 일정: 첫날만 시각, 나머지 날은 종일
  assert.ok(section(text, '2026-10-24').includes('- [E] 14:00 | 긴회의 | 대희아빠 |'));
  assert.ok(section(text, '2026-10-25').includes('- [E] 종일 | 긴회의 | 대희아빠 |'));
  // 이동형 반복 할 일은 문서에 있는 다음 날짜에 한 번만
  const rolling = text.split('\n').filter((l) => l.includes('약먹기'));
  assert.equal(rolling.length, 1);
  assert.ok(section(text, '2026-10-26').some((l) => l.includes('약먹기')));
});

test('음력 반복과 공휴일/명절 줄 ([H])', () => {
  // 2027-02-07 = 설날. 14일 범위가 닿도록 2027-02-01 기준으로 만든다
  const now = ts('2027-02-01', 8, 0).toMillis();
  const docs = [ev('음력생일', { allDay: true, start: ts('2026-02-17'), rule: { freq: 'yearly', interval: 1, lunar: true } })];
  const text = b.buildBody({ nowMs: now, docs, names: NAMES, customDays: [{ date: ts('2027-02-03'), name: '가족 | 휴가', holiday: false }] });
  const seol = text.split('\n\n').find((p) => p.startsWith('## 2027-02-07'));
  assert.ok(seol.includes('- [H] 설날'));
  assert.ok(seol.includes('- [E] 종일 | 음력생일 | 대희아빠 |'));
  assert.ok(text.split('\n\n').find((p) => p.startsWith('## 2027-02-06')).includes('- [H] 설날 연휴'));
  assert.ok(text.includes('- [H] 가족 / 휴가')); // 사용자 지정일 (| 치환)
  // 오늘 이전엔 안 나오고, 안 맞는 날엔 안 나온다
  assert.ok(!text.split('\n\n').find((p) => p.startsWith('## 2027-02-08')).includes('음력생일'));
});

// ---------- 할 일: 지난/완료 ----------
test('마감이 지난 미완료 할 일은 오늘 섹션에 "지남", 오늘 완료한 건 "완료"', () => {
  const docs = [
    td('지난종일', { start: ts('2026-10-18') }),
    td('아침에지남', { allDay: false, start: ts('2026-10-22', 6) }),
    td('오늘3시', { allDay: false, start: ts('2026-10-22', 15) }),
    td('어제끝낸것', { start: ts('2026-10-21'), done: true, lastDoneAt: ts('2026-10-22', 7) }),
    td('옛날에끝낸것', { start: ts('2026-10-10'), done: true, lastDoneAt: ts('2026-10-11', 7) }),
    td('오늘완료', { done: true }),
    td('내일할일', { start: ts('2026-10-23') }),
    td('내일완료', { start: ts('2026-10-23'), done: true }),
    td('반복약', { start: ts('2026-10-01'), rule: { freq: 'daily', interval: 1 }, doneDates: ['2026-10-22'] }),
  ];
  const text = body(docs);
  const today = section(text, '2026-10-22');
  assert.ok(today.includes('- [T] 종일 | 지난종일 | 대희아빠 | 지남'));
  assert.ok(today.includes('- [T] ~06:00 | 아침에지남 | 대희아빠 | 지남'));
  assert.ok(today.includes('- [T] ~15:00 | 오늘3시 | 대희아빠 |'));
  assert.ok(today.includes('- [T] 종일 | 어제끝낸것 | 대희아빠 | 완료'));
  assert.ok(today.includes('- [T] 종일 | 오늘완료 | 대희아빠 | 완료'));
  assert.ok(today.includes('- [T] 종일 | 반복약 | 대희아빠 | 완료'));
  assert.ok(!today.some((l) => l.includes('옛날에끝낸것')));
  // 지난 할 일은 오늘 섹션에만 (다른 날 섹션에는 안 나온다)
  assert.equal(text.split('\n').filter((l) => l.includes('지난종일')).length, 1);
  assert.ok(section(text, '2026-10-23').includes('- [T] 종일 | 내일할일 | 대희아빠 |'));
  assert.ok(section(text, '2026-10-23').includes('- [T] 종일 | 내일완료 | 대희아빠 | 완료'));
  assert.ok(section(text, '2026-10-23').some((l) => l.includes('반복약'))); // 반복은 날마다
});

// ---------- revision ----------
test('revision: 본문이 달라졌을 때만 +1, generated_at 만 바뀌면 안 올리고 안 쓴다', () => {
  const b1 = body([ev('A')]);
  const placeholder = '# OURDAY CALENDAR DIGEST\nrevision: 0\ngenerated_at: -\nscope: shared-only\ndays: 14\n';
  assert.deepEqual(b.decideWrite(placeholder, b1), { write: true, revision: 1 });
  assert.deepEqual(b.decideWrite('', b1), { write: true, revision: 1 });
  const file1 = b.renderFile({ revision: 4, generatedAtMs: NOW, body: b1 });
  assert.deepEqual(b.parseDigest(file1), { revision: 4, body: b1 });
  // 같은 본문, 시각만 다름 -> 쓰지 않음, revision 그대로
  const later = b.renderFile({ revision: 4, generatedAtMs: NOW + 3600000, body: b1 });
  assert.deepEqual(b.decideWrite(file1, b1), { write: false, revision: 4 });
  assert.deepEqual(b.decideWrite(later, b1), { write: false, revision: 4 });
  // 본문이 달라지면 +1
  assert.deepEqual(b.decideWrite(file1, body([ev('A'), ev('B')])), { write: true, revision: 5 });
  // CRLF 로 저장돼 있어도 같은 본문으로 본다
  assert.equal(b.decideWrite(file1.replace(/\n/g, '\r\n'), b1).write, false);
});

// ---------- GitHub 호출 (가짜 fetch) ----------
const TOKEN = 'ghp_unit_test_token_0123456789';
function fakeGithub({ initial, conflicts = 0, putStatus = 200, getStatus } = {}) {
  const calls = [];
  let file = initial == null ? null : { text: initial, sha: 'sha0' };
  let remainingConflicts = conflicts;
  const res = (status, json) => ({ status, ok: status >= 200 && status < 300, json: async () => json });
  const fetch = async (url, opts) => {
    calls.push({ url, opts });
    if (opts.method === 'GET') {
      if (getStatus) return res(getStatus, { message: 'Bad credentials' });
      if (!file) return res(404, { message: 'Not Found' });
      return res(200, { sha: file.sha, encoding: 'base64', content: Buffer.from(file.text).toString('base64').replace(/(.{60})/g, '$1\n') });
    }
    if (remainingConflicts > 0) {
      remainingConflicts--;
      // 그 사이 다른 쪽이 파일을 바꿨다고 흉내
      file = { text: file ? file.text : '', sha: `sha${calls.length}` };
      return res(409, { message: 'conflict' });
    }
    if (putStatus !== 200) return res(putStatus, { message: 'server said no' });
    const body = JSON.parse(opts.body);
    file = { text: Buffer.from(body.content, 'base64').toString('utf8'), sha: 'sha-new' };
    return res(200, {});
  };
  return { fetch, calls, get file() { return file; } };
}

test('GitHub: 파일 읽기(GET ?ref=브랜치)와 쓰기(PUT message/content/sha/branch)', async () => {
  const gh = fakeGithub({ initial: '# OURDAY CALENDAR DIGEST\nrevision: 0\n' });
  const client = b.createGithubClient({ token: TOKEN, fetch: gh.fetch });
  const bd = body([ev('A')]);
  const r = await b.syncFile({ client, body: bd, nowMs: NOW });
  assert.deepEqual(r, { status: 'written', revision: 1 });
  const [get, put] = gh.calls;
  assert.equal(get.opts.method, 'GET');
  assert.equal(get.url, 'https://api.github.com/repos/wildflow84/family-portfolio/contents/calendar/digest.md?ref=calendar-digest');
  assert.equal(put.opts.method, 'PUT');
  assert.equal(put.url, 'https://api.github.com/repos/wildflow84/family-portfolio/contents/calendar/digest.md');
  const sent = JSON.parse(put.opts.body);
  assert.deepEqual(Object.keys(sent).sort(), ['branch', 'content', 'message', 'sha']);
  assert.equal(sent.branch, 'calendar-digest');
  assert.equal(sent.sha, 'sha0');
  assert.equal(sent.message, 'calendar digest: revision 1');
  assert.deepEqual(b.parseDigest(Buffer.from(sent.content, 'base64').toString('utf8')), { revision: 1, body: bd });
  assert.equal(get.opts.headers.Authorization, `Bearer ${TOKEN}`);
  assert.ok(!put.opts.body.includes(TOKEN)); // 토큰은 본문에 안 들어간다
});

test('GitHub: 본문이 같으면 다시 커밋하지 않는다 (PUT 없음)', async () => {
  const bd = body([ev('A')]);
  const gh = fakeGithub({ initial: b.renderFile({ revision: 7, generatedAtMs: NOW - 86400000, body: bd }) });
  const r = await b.syncFile({ client: b.createGithubClient({ token: TOKEN, fetch: gh.fetch }), body: bd, nowMs: NOW });
  assert.deepEqual(r, { status: 'unchanged', revision: 7 });
  assert.deepEqual(gh.calls.map((c) => c.opts.method), ['GET']);
});

test('GitHub: sha 충돌(409)이면 최신을 다시 읽어 재시도, 파일이 없으면 sha 없이 새로 만든다', async () => {
  const gh = fakeGithub({ initial: '# x\nrevision: 2\n', conflicts: 1 });
  const r = await b.syncFile({ client: b.createGithubClient({ token: TOKEN, fetch: gh.fetch }), body: body([ev('A')]), nowMs: NOW });
  assert.deepEqual(r, { status: 'written', revision: 3 });
  assert.deepEqual(gh.calls.map((c) => c.opts.method), ['GET', 'PUT', 'GET', 'PUT']);
  assert.equal(JSON.parse(gh.calls[3].opts.body).sha, 'sha2'); // 충돌 뒤 새로 읽은 sha 로 재시도

  const none = fakeGithub({});
  const r2 = await b.syncFile({ client: b.createGithubClient({ token: TOKEN, fetch: none.fetch }), body: body([]), nowMs: NOW });
  assert.equal(r2.revision, 1);
  assert.equal('sha' in JSON.parse(none.calls[1].opts.body), false);

  const stuck = fakeGithub({ initial: '# x\nrevision: 2\n', conflicts: 99 });
  await assert.rejects(() => b.syncFile({ client: b.createGithubClient({ token: TOKEN, fetch: stuck.fetch }), body: body([ev('A')]), nowMs: NOW }), /409/);
});

test('GitHub: 오류 메시지에 토큰이 들어가지 않는다', async () => {
  const gh = fakeGithub({ getStatus: 401 });
  await assert.rejects(
    () => b.createGithubClient({ token: TOKEN, fetch: gh.fetch }).getFile(),
    (e) => e instanceof b.GithubError && e.status === 401 && !e.message.includes(TOKEN) && !String(e.stack).includes(TOKEN),
  );
  const bad = fakeGithub({ initial: '', putStatus: 500 });
  await assert.rejects(() => b.syncFile({ client: b.createGithubClient({ token: TOKEN, fetch: bad.fetch }), body: body([ev('A')]), nowMs: NOW }), /500/);
});

// ---------- 공간 / 변경 걸러내기 / 디바운스 ----------
test('가족 공간: 구성원이 가장 많은 공간', () => {
  assert.equal(b.pickFamilySpace([]), null);
  assert.equal(b.pickFamilySpace([{ id: 's1', members: ['a'] }, { id: 's2', members: ['a', 'b'] }]), 's2');
  assert.equal(b.pickFamilySpace([{ id: 'b', members: ['x'] }, { id: 'a', members: ['y'] }]), 'a');
});

test('변경 걸러내기: 나만 보기끼리나 알림 필드만 바뀐 건 건너뛴다', () => {
  const base = { type: 'event', title: 'A', visibility: 'shared', start: ts('2026-10-22', 9), remindAt: ts('2026-10-22', 8) };
  assert.equal(b.isRelevantChange(null, base), true); // 생성
  assert.equal(b.isRelevantChange(base, null), true); // 삭제
  assert.equal(b.isRelevantChange(base, { ...base, title: 'B' }), true);
  assert.equal(b.isRelevantChange(base, { ...base, start: ts('2026-10-23', 9) }), true);
  assert.equal(b.isRelevantChange(base, { ...base, remindAt: ts('2026-10-22', 7), remindTimes: [1] }), false);
  assert.equal(b.isRelevantChange(base, { ...base, note: '메모만' }), false);
  assert.equal(b.isRelevantChange(base, { ...base, visibility: 'private' }), true); // 공유 -> 나만: 목록에서 빠져야 한다
  assert.equal(b.isRelevantChange({ ...base, visibility: 'private' }, base), true);
  const priv = { ...base, visibility: 'private' };
  assert.equal(b.isRelevantChange(priv, { ...priv, title: 'B' }), false);
  assert.equal(b.isRelevantChange(null, priv), false);
});

test('디바운스: 연속 수정은 마지막 이벤트만 실행', async () => {
  let last = null;
  const store = { setLast: async (id) => { last = id; }, getLast: async () => last };
  let runs = 0;
  const waits = [];
  const sleep = (ms) => new Promise((r) => waits.push(r)).then(() => ms);
  const mk = (id) => b.debounced({ store, eventId: id, sleep, debounceMs: 45000, run: async () => { runs++; return id; } });
  const p1 = mk('e1');
  const p2 = mk('e2');
  const p3 = mk('e3');
  await new Promise((r) => setImmediate(r));
  waits.forEach((w) => w());
  assert.deepEqual(await Promise.all([p1, p2, p3]), ['superseded', 'superseded', 'e3']);
  assert.equal(runs, 1);
});

// ---------- runBriefing (가짜 Firestore + 가짜 GitHub) ----------
function fakeDb(spaces, items) {
  const snap = (docs) => ({ docs, forEach: (f) => docs.forEach(f) });
  const docSnap = (id, data) => ({ id, data: () => data });
  return {
    collection: (name) => {
      assert.equal(name, 'spaces');
      return { get: async () => snap(Object.entries(spaces).map(([id, v]) => docSnap(id, v))),
        doc: (spaceId) => ({
          collection: (sub) => {
            const rows = (items[spaceId] || {})[sub] || [];
            const mk = (list) => ({ get: async () => snap(list.map((r) => docSnap(r.id, r.data))) });
            return { ...mk(rows), where: (f, op, v) => { assert.equal(f, 'visibility'); assert.equal(v, 'shared'); return mk(rows.filter((r) => r.data.visibility === v)); } };
          },
        }) };
    },
  };
}

test('runBriefing: 토큰이 없으면 아무것도 하지 않는다', async () => {
  let fetched = 0;
  const r = await runBriefing({ db: fakeDb({}, {}), token: '', fetch: async () => { fetched++; } });
  assert.equal(r, 'no-token');
  assert.equal(fetched, 0);
});

test('runBriefing: 가족 공간의 공유 항목만 써서 파일을 만든다, 다른 공간 이벤트는 무시, 같은 내용은 재커밋 없음', async () => {
  const db = fakeDb(
    { s1: { members: ['me', 'mina'], names: NAMES }, s2: { members: ['x'], names: { x: '다른집' } } },
    { s1: { items: [ev('공개일정'), ev('나만일정', { visibility: 'private' })] } },
  );
  const gh = fakeGithub({ initial: '# OURDAY CALENDAR DIGEST\nrevision: 0\n' });
  const logs = [];
  const run = (extra = {}) => runBriefing({ db, token: TOKEN, fetch: gh.fetch, nowMs: NOW, log: (m) => logs.push(m), ...extra });
  assert.equal(await run({ onlySpaceId: 's2' }), 'other-space');
  assert.equal(gh.calls.length, 0);
  assert.equal(await run({ onlySpaceId: 's1' }), 'written');
  const written = gh.file.text;
  assert.ok(written.includes('공개일정') && !written.includes('나만일정'));
  assert.ok(written.includes('revision: 1'));
  assert.equal(await run(), 'unchanged'); // 스케줄 실행: 본문 같음 -> 커밋 없음
  assert.equal(gh.calls.filter((c) => c.opts.method === 'PUT').length, 1);
  assert.ok(!logs.join('\n').includes(TOKEN));
});

test('runBriefing: 실패해도 던지지 않고(앱 영향 없음) 토큰을 로그에 남기지 않는다', async () => {
  const logs = [];
  const db = fakeDb({ s1: { members: ['me'], names: NAMES } }, { s1: { items: [ev('A')] } });
  const gh = fakeGithub({ getStatus: 401 });
  const r = await runBriefing({ db, token: TOKEN, fetch: gh.fetch, nowMs: NOW, log: (m) => logs.push(m) });
  assert.equal(r, 'error');
  assert.ok(logs.some((l) => l.includes('status=401')));
  assert.ok(!logs.join('\n').includes(TOKEN));
  const boom = await runBriefing({ db: { collection: () => { throw new Error(`boom ${TOKEN}`); } }, token: TOKEN, log: (m) => logs.push(m) });
  assert.equal(boom, 'error');
  assert.ok(!logs.join('\n').includes(TOKEN));
});
