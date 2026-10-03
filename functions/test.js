const test = require('node:test');
const assert = require('node:assert');
const lib = require('./lib');

const ts = (ms) => ({ toMillis: () => ms });

test('재촉은 같은 회차에서 최대 3번', () => {
  let item = { start: ts(1000), done: false };
  for (let i = 1; i <= 3; i++) {
    const s = lib.nudgeState(item);
    assert.equal(s.allowed, true);
    assert.equal(s.next, i);
    item = { ...item, nudgeKey: s.key, nudgeCount: s.next };
  }
  assert.equal(lib.nudgeState(item).allowed, false);
});

test('날짜가 바뀌거나 완료 상태가 바뀌면 재촉 횟수가 새로 시작', () => {
  const base = { start: ts(1000), done: false, nudgeKey: '1000|0', nudgeCount: 3 };
  assert.equal(lib.nudgeState(base).allowed, false);
  assert.equal(lib.nudgeState({ ...base, start: ts(2000) }).allowed, true); // 이동형이 다음 날짜로
  assert.equal(lib.nudgeState({ ...base, done: true }).count, 0);
});

test('상대가 재촉을 끄면 받지 않는다 (기본은 켜짐)', () => {
  assert.equal(lib.acceptsNudge(undefined), true);
  assert.equal(lib.acceptsNudge({}), true);
  assert.equal(lib.acceptsNudge({ allowNudge: true }), true);
  assert.equal(lib.acceptsNudge({ allowNudge: false }), false);
});

test('완료 알림: 기본 켜짐, 반복 항목은 따로 켜야 함', () => {
  const once = { type: 'todo' };
  const weekly = { type: 'todo', rule: { freq: 'weekly' } };
  const rolling = { type: 'todo', rollEvery: 1 };
  assert.equal(lib.acceptsComplete({}, once), true);
  assert.equal(lib.acceptsComplete({ notifyComplete: false }, once), false);
  assert.equal(lib.acceptsComplete({}, weekly), false);
  assert.equal(lib.acceptsComplete({}, rolling), false);
  assert.equal(lib.acceptsComplete({ notifyCompleteRepeating: true }, weekly), true);
  assert.equal(lib.acceptsComplete({ notifyComplete: false, notifyCompleteRepeating: true }, weekly), false);
  assert.equal(lib.isRepeating({ repeat: 'weekly' }), true);
  assert.equal(lib.isRepeating({ repeat: 'none' }), false);
});

test('메시지 문구와 죽은 토큰 정리', () => {
  const m = lib.nudgeMessage('대희 아빠', { type: 'todo', title: '장보기' }, 2);
  assert.match(m.title, /2\/3/);
  assert.match(m.body, /장보기/);
  assert.deepEqual(
    lib.deadTokens(['a', 'b', 'c'], [
      { success: true },
      { error: { code: 'messaging/registration-token-not-registered' } },
      { error: { code: 'messaging/internal-error' } },
    ]),
    ['b'],
  );
});

test('공유 알림: 기본 켜짐, 끄면 안 감, 같은 항목은 1분에 한 번', () => {
  assert.equal(lib.acceptsShared(undefined), true);
  assert.equal(lib.acceptsShared({}), true);
  assert.equal(lib.acceptsShared({ notifyShared: false }), false);
  const now = 1_000_000;
  assert.equal(lib.canNotifyShared({}, now), true);
  assert.equal(lib.canNotifyShared({ sharedNotifyAt: ts(now - 10_000) }, now), false);
  assert.equal(lib.canNotifyShared({ sharedNotifyAt: ts(now - 61_000) }, now), true);
  const m = lib.shareMessage('민아', { type: 'event', title: '병원' });
  assert.match(m.title, /민아.*일정.*공유/);
});
