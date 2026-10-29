'use strict';
const test = require('node:test');
const assert = require('node:assert');
const c = require('./coupon');

const KST = 9 * 3600 * 1000;
const NOW = Date.UTC(2026, 9, 29, 3, 0) - 0; // 2026-10-29 12:00 KST

test('번호 정규화: 공백/하이픈 제거, 대문자, 길이 제한', () => {
  assert.equal(c.normalizeCoupon('1234 5678-9012'), '123456789012');
  assert.equal(c.normalizeCoupon(' ab12-cd34 ef56 '), 'AB12CD34EF56');
  assert.equal(c.normalizeCoupon('12345'), null); // 너무 짧음
  assert.equal(c.normalizeCoupon('1'.repeat(33)), null);
  assert.equal(c.normalizeCoupon('12345678가'), null);
  assert.equal(c.normalizeCoupon(''), null);
  assert.equal(c.normalizeCoupon(null), null);
  assert.equal(c.formatCoupon('123456789012'), '1234 5678 9012');
  assert.equal(c.formatCoupon('AB12CD34'), 'AB12CD34');
  assert.equal(c.maskCoupon('123456789012'), '····9012');
});

test('스크린샷 글자에서 쿠폰번호 후보: 쿠폰번호 줄을 우선, 전화/날짜/고객센터는 뒤로', () => {
  const gift = '카카오톡 선물하기\n아메리카노 Tall\n교환처 스타벅스\n쿠폰번호\n1234 5678 9012\n유효기간 2026.12.31\n주문번호 9876543210\n고객센터 1599-1234\n010-1234-5678';
  const r = c.extractCouponCandidates(gift);
  assert.equal(r[0], '123456789012');
  assert.ok(!r.includes('15991234')); // 대표번호
  assert.ok(!r.includes('01012345678')); // 휴대폰
  assert.ok(!r.includes('20261231')); // 날짜
});

test('쿠폰번호가 같은 줄에 있거나 영문+숫자 코드여도 읽는다', () => {
  assert.equal(c.extractCouponCandidates('쿠폰번호 : 8801-2345-6789-0123')[0], '8801234567890123');
  assert.equal(c.extractCouponCandidates('쿠폰번호 : AB12-CD34-EF56\n유효기간 2026-12-31')[0], 'AB12CD34EF56');
  assert.equal(c.extractCouponCandidates('교환번호 1234567890\n상품명 케이크')[0], '1234567890');
  assert.equal(c.extractCouponCandidates('바코드\n8801 2345 6789 0123')[0], '8801234567890123');
});

test('번호가 없으면 빈 목록, 후보는 최대 5개이고 중복 없음', () => {
  assert.deepEqual(c.extractCouponCandidates(''), []);
  assert.deepEqual(c.extractCouponCandidates(null), []);
  assert.deepEqual(c.extractCouponCandidates('안녕하세요\n감사합니다 2026.10.29'), []);
  const many = Array.from({ length: 9 }, (_, i) => `쿠폰번호 ${String(1000000000 + i).repeat(1)}`).join('\n');
  const r = c.extractCouponCandidates(many + '\n' + many);
  assert.equal(r.length, 5);
  assert.equal(new Set(r).size, 5);
});

function fakeFetch(status, json) {
  const calls = [];
  const f = async (url, opts) => { calls.push({ url, opts }); return { status, ok: status >= 200 && status < 300, json: async () => json }; };
  f.calls = calls;
  return f;
}

test('Vision 호출: 글자 읽기, API 꺼짐(403)은 unavailable, 그 밖의 오류는 error', async () => {
  const ok = fakeFetch(200, { responses: [{ fullTextAnnotation: { text: '쿠폰번호 1234 5678 9012' } }] });
  const r = await c.readText({ imageBase64: 'AAAA', fetch: ok, getToken: async () => 'tok' });
  assert.deepEqual(r, { ok: true, text: '쿠폰번호 1234 5678 9012' });
  assert.equal(ok.calls[0].url, 'https://vision.googleapis.com/v1/images:annotate');
  assert.equal(ok.calls[0].opts.headers.Authorization, 'Bearer tok');
  assert.equal(JSON.parse(ok.calls[0].opts.body).requests[0].features[0].type, 'TEXT_DETECTION');
  assert.deepEqual(await c.readText({ imageBase64: 'A', fetch: fakeFetch(403, {}), getToken: async () => 't' }), { ok: false, reason: 'unavailable' });
  assert.deepEqual(await c.readText({ imageBase64: 'A', fetch: fakeFetch(500, {}), getToken: async () => 't' }), { ok: false, reason: 'error' });
  assert.deepEqual(await c.readText({ imageBase64: 'A', fetch: fakeFetch(200, { responses: [{ error: { code: 3 } }] }), getToken: async () => 't' }), { ok: false, reason: 'error' });
  assert.deepEqual(await c.readText({ imageBase64: 'A', fetch: async () => { throw new Error('net'); }, getToken: async () => 't' }), { ok: false, reason: 'error' });
  const empty = await c.readText({ imageBase64: 'A', fetch: fakeFetch(200, { responses: [{}] }), getToken: async () => 't' });
  assert.deepEqual(empty, { ok: true, text: '' });
});

test('등록 판단: 없으면 가능, 판매 완료/대기는 막는다', () => {
  assert.deepEqual(c.decideRegister(null), { ok: true });
  assert.deepEqual(c.decideRegister({ status: 'pending' }), { ok: false, code: 'pending' });
  assert.deepEqual(c.decideRegister({ status: 'sold', soldAt: { toMillis: () => 123 } }), { ok: false, code: 'sold', soldAtMs: 123 });
  assert.equal(c.decideRegister({ status: 'sold' }).soldAtMs, 0);
});

test('판매 할 일: 오늘(한국시간) 종일, 같이 보기, 담당자는 판매하는 사람(방장), 제목은 번호 뒤 4자리만', () => {
  const t = c.couponTodo({ number: '123456789012', requesterUid: 'mina', requesterName: '민아', sellerUid: 'me', nowMs: NOW });
  assert.equal(t.type, 'todo');
  assert.equal(t.title, '쿠폰 판매 ····9012');
  assert.equal(t.visibility, 'shared');
  assert.equal(t.ownerUid, 'mina');
  assert.equal(t.assignee, 'me');
  assert.equal(t.allDay, true);
  assert.equal(t.done, false);
  assert.equal(t.couponId, '123456789012');
  assert.equal(t.startMs, Date.UTC(2026, 9, 28, 15, 0)); // 2026-10-29 00:00 KST
  assert.ok(t.note.includes('1234 5678 9012'));
  assert.equal(c.sellerOf(['me', 'mina']), 'me');
  assert.equal(c.sellerOf([]), '');
  // 판매자를 모르면 올린 사람 몫
  assert.equal(c.couponTodo({ number: '123456789012', requesterUid: 'mina', requesterName: '민아', sellerUid: '', nowMs: NOW }).assignee, 'mina');
});

test('완료 전환: 완료하면 sold, 풀면 unsold, 지우면(안 팔았을 때) cancel', () => {
  const todo = (over) => ({ couponId: 'C1234567', done: false, ...over });
  assert.deepEqual(c.couponTransition(todo(), todo({ done: true })), { action: 'sold', couponId: 'C1234567' });
  assert.deepEqual(c.couponTransition(null, todo({ done: true })), { action: 'sold', couponId: 'C1234567' });
  assert.deepEqual(c.couponTransition(todo({ done: true }), todo({ done: false })), { action: 'unsold', couponId: 'C1234567' });
  assert.deepEqual(c.couponTransition(todo(), null), { action: 'cancel', couponId: 'C1234567' });
  assert.equal(c.couponTransition(todo({ done: true }), null), null); // 이미 판 쿠폰의 할 일을 지워도 기록은 남긴다
  assert.equal(c.couponTransition(todo(), todo({ title: 'x' })), null); // 다른 수정
  assert.equal(c.couponTransition(todo({ done: true }), todo({ done: true })), null);
  assert.equal(c.couponTransition({ done: false }, { done: true }), null); // 쿠폰 할 일이 아님
  assert.equal(c.couponTransition(null, null), null);
});

// ---------- 가짜 Firestore (트랜잭션) ----------
function fakeDb() {
  const store = new Map();
  let autoId = 0;
  const ref = (path) => ({ path, id: path.split('/').pop() });
  const snapOf = (path) => ({ exists: store.has(path), data: () => store.get(path) });
  return {
    store,
    doc: (p) => ref(p),
    collection: (p) => ({ doc: () => ref(`${p}/auto${++autoId}`) }),
    runTransaction: async (fn) => {
      const writes = [];
      const tx = {
        get: async (r) => snapOf(r.path),
        set: (r, d) => writes.push(['set', r.path, d]),
        update: (r, d) => writes.push(['update', r.path, d]),
        delete: (r) => writes.push(['delete', r.path]),
      };
      await fn(tx);
      for (const [op, path, d] of writes) {
        if (op === 'set') store.set(path, d);
        else if (op === 'update') store.set(path, { ...store.get(path), ...d });
        else store.delete(path);
      }
    },
  };
}
const reg = (db, over = {}) => c.runRegister({
  db, timestamp: (ms) => ({ ts: ms }), now: () => 'NOW', spaceId: 's1', number: '123456789012',
  imageBuffer: Buffer.from([0xff, 0xd8, 0xff, 1, 2, 3]), mime: 'image/jpeg', requester: { uid: 'mina', name: '민아' }, sellerUid: 'me', nowMs: NOW, ...over,
});

test('등록: 쿠폰 + 스크린샷 + 할 일이 함께 만들어진다', async () => {
  const db = fakeDb();
  const r = await reg(db);
  assert.equal(r.couponId, '123456789012');
  const coupon = db.store.get('spaces/s1/coupons/123456789012');
  assert.equal(coupon.status, 'pending');
  assert.equal(coupon.requestedBy, 'mina');
  assert.equal(coupon.sellerUid, 'me');
  assert.equal(coupon.itemId, r.itemId);
  assert.equal(coupon.imageBytes, 6);
  const img = db.store.get('spaces/s1/couponImages/123456789012');
  assert.equal(img.mime, 'image/jpeg');
  assert.ok(Buffer.isBuffer(img.data));
  const item = db.store.get(`spaces/s1/items/${r.itemId}`);
  assert.equal(item.couponId, '123456789012');
  assert.equal(item.assignee, 'me');
  assert.equal(item.visibility, 'shared');
  assert.deepEqual(item.start, { ts: Date.UTC(2026, 9, 28, 15, 0) });
  assert.ok(!('startMs' in item));
});

test('같은 쿠폰을 또 등록하면 막는다: 판매 대기 중이면 pending, 판매 완료면 sold (새 할 일도 안 생김)', async () => {
  const db = fakeDb();
  await reg(db);
  const items = () => [...db.store.keys()].filter((k) => k.includes('/items/')).length;
  assert.equal(items(), 1);
  await assert.rejects(() => reg(db), (e) => e instanceof c.CouponError && e.code === 'already-pending');
  assert.equal(items(), 1);
  db.store.set('spaces/s1/coupons/123456789012', { ...db.store.get('spaces/s1/coupons/123456789012'), status: 'sold', soldAt: { toMillis: () => 5 } });
  await assert.rejects(() => reg(db, { requester: { uid: 'me', name: '대희 아빠' } }), (e) => e instanceof c.CouponError && e.code === 'already-sold' && e.details.soldAtMs === 5);
  assert.equal(items(), 1);
  // 다른 번호는 가능
  await reg(db, { number: '999988887777' });
  assert.equal(items(), 2);
});

test('판매 전환: 완료 → sold(할 일이 맞을 때만), 완료 해제 → 되돌림, 지움 → 등록 취소(다시 올릴 수 있음)', async () => {
  const db = fakeDb();
  const { itemId } = await reg(db);
  const cp = () => db.store.get('spaces/s1/coupons/123456789012');
  const run = (transition, id = itemId) => c.applyTransition({ db, spaceId: 's1', itemId: id, transition, soldBy: 'me', now: () => 'NOW2' });
  // 다른 항목이 같은 couponId 를 흉내 내도 무시
  assert.equal(await run({ action: 'sold', couponId: '123456789012' }, 'otherItem'), 'skip');
  assert.equal(cp().status, 'pending');
  assert.equal(await run({ action: 'sold', couponId: '123456789012' }), 'sold');
  assert.equal(cp().status, 'sold');
  assert.equal(cp().soldBy, 'me');
  assert.equal(await run({ action: 'sold', couponId: '123456789012' }), 'skip'); // 두 번째는 변화 없음
  assert.equal(await run({ action: 'cancel', couponId: '123456789012' }), 'skip'); // 이미 판 것은 취소 안 됨
  assert.equal(await run({ action: 'unsold', couponId: '123456789012' }), 'unsold');
  assert.equal(cp().status, 'pending');
  assert.equal(await run({ action: 'cancel', couponId: '123456789012' }), 'cancel');
  assert.equal(cp(), undefined);
  assert.equal(db.store.has('spaces/s1/couponImages/123456789012'), false);
  await reg(db); // 취소했으니 다시 등록할 수 있다
  assert.equal(await run(null), 'skip');
  assert.equal(await run({ action: 'sold', couponId: 'NOPE12345' }), 'skip'); // 없는 쿠폰
});
