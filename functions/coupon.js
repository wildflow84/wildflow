'use strict';
// 쿠폰 판매 기능의 순수 로직: 쿠폰번호 읽기/정규화, 등록 판단, 할 일 만들기, 완료 → 판매 완료 전환. (Firebase 없이 테스트한다)
const { kstParts, kstMidnightMs } = require('./itemcalc');

const MIN_LEN = 6;
const MAX_LEN = 32;
const MAX_IMAGE_B64 = 1_400_000; // 약 1MB 이미지 (Firestore 문서 한도 1MiB 안에 들어가게)

/** 쿠폰번호 정규화: 대문자, 공백/하이픈/점/밑줄 제거. 영문/숫자 6~32자가 아니면 null */
function normalizeCoupon(s) {
  const v = String(s == null ? '' : s).toUpperCase().replace(/[\s\-_.·]/g, '');
  return /^[A-Z0-9]+$/.test(v) && v.length >= MIN_LEN && v.length <= MAX_LEN ? v : null;
}

/** 화면에 보일 번호: 숫자만 있으면 4자리씩 끊어서 */
function formatCoupon(n) {
  return /^\d+$/.test(n) ? n.replace(/(\d{4})(?=\d)/g, '$1 ') : n;
}

/** 번호 뒤 4자리만 보이게 (할 일 제목, 알림에 쓴다) */
const maskCoupon = (n) => `····${String(n).slice(-4)}`;

// ---------- 스크린샷 글자에서 쿠폰번호 후보 뽑기 ----------
const KEYWORD = /(쿠폰\s*번호|교환\s*번호|핀\s*번호|인증\s*번호|바코드\s*번호|기프티콘\s*번호|상품\s*번호|사용\s*번호|PIN|coupon\s*(?:no|number|code)?|voucher)/i;
const BAD_LINE = /(주문\s*번호|승인\s*번호|거래\s*번호|전화|문의|고객\s*센터|TEL|사업자|등록\s*번호|우편|계좌|카드\s*번호|결제|금액|가격|원\b|₩|유효\s*기간|사용\s*기한|만료|까지|발송|구매\s*일)/i;
const DATE_LIKE = /^(19|20)\d{2}[.\-/년]?\d{1,2}[.\-/월]?\d{1,2}/;

function looksLikePhone(digits) {
  return /^(01[016789]\d{7,8}|0[2-6]\d{1}\d{7,8}|1[5-9]\d{2}\d{4})$/.test(digits); // 휴대폰, 지역번호, 15xx/16xx 대표번호
}

/**
 * OCR 글자에서 쿠폰번호 후보를 점수순으로 돌려준다 (정규화된 문자열, 최대 5개).
 * "쿠폰번호" 같은 말이 붙은 줄을 우선하고, 전화번호/날짜/주문번호/금액처럼 보이는 건 뒤로 민다.
 */
function extractCouponCandidates(text) {
  const lines = String(text || '').split(/\r?\n/).map((l) => l.trim());
  const scores = new Map();
  const add = (raw, score) => {
    const n = normalizeCoupon(raw);
    if (!n) return;
    scores.set(n, Math.max(scores.get(n) ?? -Infinity, score));
  };

  lines.forEach((line, idx) => {
    if (!line) return;
    const near = KEYWORD.test(line) || (idx > 0 && KEYWORD.test(lines[idx - 1]) && !BAD_LINE.test(lines[idx - 1]));
    const bad = BAD_LINE.test(line) && !KEYWORD.test(line);
    // 영문/숫자 섞인 코드: 키워드 바로 뒤
    const m = /(쿠폰\s*번호|교환\s*번호|핀\s*번호|인증\s*번호|PIN|coupon\s*(?:no|number|code)?)\s*[:：]?\s*([A-Z0-9][A-Z0-9\s\-]{5,40})/i.exec(line);
    if (m && /[A-Za-z]/.test(m[2]) && /\d/.test(m[2])) add(m[2].replace(/\s+$/, ''), 30);
    // 숫자 덩어리 (공백/하이픈으로 끊긴 것 포함)
    for (const g of line.matchAll(/\d[\d\s\-]{6,38}\d/g)) {
      const raw = g[0];
      const digits = raw.replace(/\D/g, '');
      if (digits.length < 8 || digits.length > 24) continue;
      let s = 0;
      if (near) s += 10;
      if (digits.length >= 10 && digits.length <= 16) s += 3;
      if (/^\d{4}([\s-]\d{4}){1,5}$/.test(raw.trim())) s += 2; // 4자리씩 끊어 적은 모양
      if (bad) s -= 8;
      if (looksLikePhone(digits)) s -= 20;
      if (DATE_LIKE.test(raw.replace(/\s/g, ''))) s -= 15;
      add(digits, s);
    }
    // 키워드 없이 줄 전체가 영문+숫자 코드인 경우 (예: "AB12-CD34-EF56")
    if (/^[A-Z0-9]{3,8}([\s-][A-Z0-9]{3,8}){1,4}$/i.test(line) && /[A-Za-z]/.test(line) && /\d/.test(line)) add(line, near ? 12 : 4);
  });

  return [...scores.entries()]
    .filter(([, s]) => s > -10)
    .sort((a, b) => b[1] - a[1] || b[0].length - a[0].length)
    .slice(0, 5)
    .map(([n]) => n);
}

// ---------- 구글 Cloud Vision 으로 글자 읽기 ----------
/**
 * 이미지(base64 JPEG/PNG)의 글자를 읽는다.
 * @returns {Promise<{ok:true,text:string}|{ok:false,reason:'unavailable'|'error'}>}
 */
async function readText({ imageBase64, fetch: fetchImpl = globalThis.fetch, getToken }) {
  try {
    const token = await getToken();
    const res = await fetchImpl('https://vision.googleapis.com/v1/images:annotate', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requests: [{ image: { content: imageBase64 }, features: [{ type: 'TEXT_DETECTION' }], imageContext: { languageHints: ['ko', 'en'] } }],
      }),
    });
    if (res.status === 403 || res.status === 404) return { ok: false, reason: 'unavailable' }; // API 가 아직 안 켜졌거나 권한 없음
    if (!res.ok) return { ok: false, reason: 'error' };
    const j = await res.json();
    const r = (j.responses || [])[0] || {};
    if (r.error) return { ok: false, reason: 'error' };
    return { ok: true, text: (r.fullTextAnnotation && r.fullTextAnnotation.text) || '' };
  } catch (_) {
    return { ok: false, reason: 'error' };
  }
}

// ---------- 등록 / 상태 ----------
/** 이미 있는 쿠폰 문서로 등록 가능 여부 판단 */
function decideRegister(existing) {
  if (!existing) return { ok: true };
  if (existing.status === 'sold') return { ok: false, code: 'sold', soldAtMs: existing.soldAt && typeof existing.soldAt.toMillis === 'function' ? existing.soldAt.toMillis() : 0 };
  return { ok: false, code: 'pending' };
}

/** 판매 담당: 공간을 만든 사람(members 맨 앞) */
const sellerOf = (members) => (Array.isArray(members) && members.length > 0 ? members[0] : '');

/** 쿠폰 판매 할 일 문서 내용 (오늘 하루짜리, 같이 보기, 담당자 = 판매하는 사람) */
function couponTodo({ number, requesterUid, requesterName, sellerUid, nowMs }) {
  const start = kstMidnightMs(kstParts(nowMs).dn);
  return {
    type: 'todo',
    title: `쿠폰 판매 ${maskCoupon(number)}`,
    note: `${requesterName || '상대'}이(가) 올린 쿠폰이야. 쿠폰 번호: ${formatCoupon(number)}\n스크린샷은 설정 → 쿠폰 판매에서 저장할 수 있어. 이 할 일을 완료하면 판매 완료로 처리돼.`,
    startMs: start,
    allDay: true,
    done: false,
    doneDates: [],
    visibility: 'shared',
    ownerUid: requesterUid,
    assignee: sellerUid || requesterUid,
    repeat: 'none',
    category: 'default',
    categories: ['default'],
    couponId: number,
  };
}

/**
 * 할 일 문서가 바뀔 때 쿠폰 상태를 어떻게 할지.
 * @returns {{action:'sold'|'unsold'|'cancel', couponId:string}|null}
 */
function couponTransition(before, after) {
  const b = before || null, a = after || null;
  const id = (a && a.couponId) || (b && b.couponId);
  if (!id) return null;
  if (!a) {
    // 할 일을 지움: 아직 안 판 쿠폰이면 등록을 취소해서 다시 올릴 수 있게 한다
    return b.done === true ? null : { action: 'cancel', couponId: b.couponId };
  }
  if (a.done === true && !(b && b.done === true)) return { action: 'sold', couponId: a.couponId };
  if (a.done !== true && b && b.done === true) return { action: 'unsold', couponId: a.couponId };
  return null;
}

module.exports = {
  MIN_LEN, MAX_LEN, MAX_IMAGE_B64,
  normalizeCoupon, formatCoupon, maskCoupon, extractCouponCandidates, readText,
  decideRegister, sellerOf, couponTodo, couponTransition,
};

// ---------- 등록 (Firestore 트랜잭션) ----------
class CouponError extends Error {
  constructor(code, message, details) {
    super(message);
    this.code = code; // 'already-sold' | 'already-pending'
    this.details = details || {};
  }
}

/**
 * 쿠폰을 등록한다: 같은 번호가 이미 있으면(판매 완료/대기 모두) 막고, 없으면 쿠폰 + 스크린샷 + 판매 할 일을 한 번에 만든다.
 * 쿠폰 문서 id 가 곧 정규화된 번호라서 두 사람이 동시에 올려도 하나만 만들어진다.
 * @param {object} o
 * @param {object} o.db Firestore (doc/collection/runTransaction)
 * @param {(ms:number)=>any} o.timestamp Timestamp.fromMillis
 * @param {()=>any} o.now FieldValue.serverTimestamp()
 */
async function runRegister({ db, timestamp, now, spaceId, number, imageBuffer, mime, requester, sellerUid, nowMs }) {
  const base = `spaces/${spaceId}`;
  const couponRef = db.doc(`${base}/coupons/${number}`);
  const imageRef = db.doc(`${base}/couponImages/${number}`);
  const itemRef = db.collection(`${base}/items`).doc();
  const todo = couponTodo({ number, requesterUid: requester.uid, requesterName: requester.name, sellerUid, nowMs });
  const { startMs, ...todoRest } = todo;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(couponRef);
    const d = decideRegister(snap.exists ? snap.data() : null);
    if (!d.ok) {
      throw new CouponError(d.code === 'sold' ? 'already-sold' : 'already-pending',
        d.code === 'sold' ? '이미 판매한 쿠폰이야' : '이미 등록돼서 판매를 기다리는 쿠폰이야', { soldAtMs: d.soldAtMs || 0 });
    }
    tx.set(couponRef, {
      number,
      status: 'pending',
      requestedBy: requester.uid,
      requestedByName: requester.name || '',
      requestedAt: now(),
      itemId: itemRef.id,
      sellerUid: sellerUid || '',
      soldAt: null,
      imageBytes: imageBuffer.length,
    });
    tx.set(imageRef, { data: imageBuffer, mime, createdAt: now() });
    tx.set(itemRef, { ...todoRest, start: timestamp(startMs), lastDoneBy: null });
  });
  return { couponId: number, itemId: itemRef.id };
}

/** 할 일 변화에 따라 쿠폰 상태를 바꾼다 (트리거에서 부른다). 다른 항목이 같은 couponId 를 흉내 내도 itemId 가 다르면 무시한다. */
async function applyTransition({ db, spaceId, itemId, transition, soldBy, now }) {
  if (!transition) return 'skip';
  const base = `spaces/${spaceId}`;
  const ref = db.doc(`${base}/coupons/${transition.couponId}`);
  const imageRef = db.doc(`${base}/couponImages/${transition.couponId}`);
  let result = 'skip';
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const c = snap.data();
    if (c.itemId !== itemId) return;
    if (transition.action === 'sold' && c.status !== 'sold') {
      tx.update(ref, { status: 'sold', soldAt: now(), soldBy: soldBy || '' });
      result = 'sold';
    } else if (transition.action === 'unsold' && c.status === 'sold') {
      tx.update(ref, { status: 'pending', soldAt: null, soldBy: null });
      result = 'unsold';
    } else if (transition.action === 'cancel' && c.status === 'pending') {
      tx.delete(ref);
      tx.delete(imageRef);
      result = 'cancel';
    }
  });
  return result;
}

module.exports.CouponError = CouponError;
module.exports.runRegister = runRegister;
module.exports.applyTransition = applyTransition;
