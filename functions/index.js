const { setGlobalOptions } = require('firebase-functions/v2');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const crypto = require('node:crypto');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { Timestamp } = require('firebase-admin/firestore');
const lib = require('./lib');
const ics = require('./ics');

initializeApp();
setGlobalOptions({ region: 'asia-northeast3', maxInstances: 3 });

const db = getFirestore();

/** 호출자가 공간 멤버인지 확인하고, 공간/항목/상대 정보를 돌려준다. */
async function context(req, spaceId, itemId) {
  const uid = req.auth && req.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', '로그인이 필요해');
  if (typeof spaceId !== 'string' || typeof itemId !== 'string' || !spaceId || !itemId) {
    throw new HttpsError('invalid-argument', '잘못된 요청이야');
  }
  const spaceSnap = await db.doc(`spaces/${spaceId}`).get();
  const members = (spaceSnap.data() || {}).members || [];
  if (!members.includes(uid)) throw new HttpsError('permission-denied', '이 공간의 멤버가 아니야');
  const itemRef = db.doc(`spaces/${spaceId}/items/${itemId}`);
  const itemSnap = await itemRef.get();
  if (!itemSnap.exists) throw new HttpsError('not-found', '항목을 찾을 수 없어');
  const item = itemSnap.data();
  if (item.visibility !== 'shared') throw new HttpsError('failed-precondition', '같이 보기 항목만 알릴 수 있어');
  const names = (spaceSnap.data() || {}).names || {};
  const partners = members.filter((m) => m !== uid);
  return { uid, actorName: names[uid] || '상대', item, itemRef, partners };
}

/** 상대 기기들에 푸시. 성공 개수를 돌려주고, 죽은 토큰은 지운다. */
async function pushTo(partnerUid, prefs, message, data) {
  const tokens = (prefs && prefs.fcmTokens) || [];
  if (tokens.length === 0) return 0;
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: message,
    data,
    webpush: { fcmOptions: { link: '/' }, notification: { icon: '/icons/Icon-192.png', tag: data.itemId } },
    android: { priority: 'high', notification: { tag: data.itemId } },
  });
  const dead = lib.deadTokens(tokens, res.responses);
  if (dead.length > 0) {
    await db.doc(`users/${partnerUid}`).set({ fcmTokens: FieldValue.arrayRemove(...dead) }, { merge: true });
  }
  return res.successCount;
}

/** 같이 보기 항목에 대해 상대에게 확인 요청(재촉) 푸시. 항목(회차)당 최대 3번. */
exports.nudge = onCall(async (req) => {
  const { spaceId, itemId } = req.data || {};
  const c = await context(req, spaceId, itemId);
  if (c.item.done) throw new HttpsError('failed-precondition', '이미 완료된 항목이야');
  if (c.partners.length === 0) throw new HttpsError('failed-precondition', '아직 상대가 없어');
  const state = lib.nudgeState(c.item);
  if (!state.allowed) throw new HttpsError('resource-exhausted', `이 항목은 ${lib.NUDGE_MAX}번 다 재촉했어`);

  let sent = 0;
  let muted = 0;
  for (const p of c.partners) {
    const prefs = (await db.doc(`users/${p}`).get()).data() || {};
    if (!lib.acceptsNudge(prefs)) {
      muted++;
      continue;
    }
    sent += await pushTo(p, prefs, lib.nudgeMessage(c.actorName, c.item, state.next), { spaceId, itemId, kind: 'nudge' });
  }
  if (muted > 0 && sent === 0) throw new HttpsError('failed-precondition', 'muted');
  if (sent === 0) throw new HttpsError('failed-precondition', 'no-device');
  await c.itemRef.update({ nudgeKey: state.key, nudgeCount: state.next });
  return { count: state.next, max: lib.NUDGE_MAX };
});

/** 같이 하는 항목을 완료했을 때 상대에게 알림. 상대 설정(완료 알림, 반복은 별도)에 따른다. */
exports.notifyComplete = onCall(async (req) => {
  const { spaceId, itemId } = req.data || {};
  const c = await context(req, spaceId, itemId);
  // 방금 내가 완료한 항목만 (아무 항목이나 알림을 보내지 못하게)
  const fresh = Date.now() - (c.item.lastDoneAt ? c.item.lastDoneAt.toMillis() : 0) < 5 * 60 * 1000;
  if (c.item.lastDoneBy !== c.uid || !fresh) return { sent: 0 };
  let sent = 0;
  for (const p of c.partners) {
    const prefs = (await db.doc(`users/${p}`).get()).data() || {};
    if (!lib.acceptsComplete(prefs, c.item)) continue;
    sent += await pushTo(p, prefs, lib.completeMessage(c.actorName, c.item), { spaceId, itemId, kind: 'complete' });
  }
  return { sent };
});

/** 내가 상대에게 새로 공유한 항목이 있다고 알림. 소유자만, 같은 항목은 1분에 한 번. */
exports.notifyShared = onCall(async (req) => {
  const { spaceId, itemId } = req.data || {};
  const c = await context(req, spaceId, itemId);
  if (c.item.ownerUid !== c.uid) return { sent: 0 };
  if (!lib.canNotifyShared(c.item, Date.now())) return { sent: 0 };
  let sent = 0;
  for (const p of c.partners) {
    const prefs = (await db.doc(`users/${p}`).get()).data() || {};
    if (!lib.acceptsShared(prefs)) continue;
    sent += await pushTo(p, prefs, lib.shareMessage(c.actorName, c.item, p), { spaceId, itemId, kind: 'shared' });
  }
  await c.itemRef.update({ sharedNotifyAt: FieldValue.serverTimestamp() });
  return { sent };
});

// ---------------------------------------------------------------------------
// 일정 구독 (아스날 경기, 드라마 방영 일정 등 .ics 주소)
// ---------------------------------------------------------------------------

async function fetchFeed(rawUrl) {
  const url = new URL(rawUrl.trim().replace(/^webcal:/i, 'https:'));
  if (url.protocol !== 'https:') throw new HttpsError('invalid-argument', 'https 주소만 가능해');
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 20000);
  try {
    const res = await fetch(url, { signal: ctl.signal, headers: { 'User-Agent': 'soondaehui-calendar/1.0' } });
    if (!res.ok) throw new HttpsError('unavailable', `구독 주소가 응답하지 않아 (HTTP ${res.status})`);
    const text = await res.text();
    if (text.length > 5 * 1024 * 1024) throw new HttpsError('invalid-argument', '파일이 너무 커');
    if (!text.includes('BEGIN:VCALENDAR')) throw new HttpsError('invalid-argument', '캘린더(.ics) 파일이 아니야');
    return text;
  } finally {
    clearTimeout(timer);
  }
}

const itemIdFor = (subId, e) =>
  `sub_${subId}_${crypto.createHash('sha1').update(e.uid || `${e.title}|${e.startMs}`).digest('hex').slice(0, 20)}`;

/** 구독 하나를 동기화: 피드의 일정을 항목으로 만들거나 갱신하고, 피드에서 사라진 일정은 지운다. */
async function syncOne(spaceId, subId) {
  const subRef = db.doc(`spaces/${spaceId}/subscriptions/${subId}`);
  const sub = (await subRef.get()).data();
  if (!sub) throw new HttpsError('not-found', '구독을 찾을 수 없어');
  try {
    const { events, skippedRepeating } = ics.parseFeed(await fetchFeed(sub.url));
    const col = db.collection(`spaces/${spaceId}/items`);
    const existing = await col.where('subscriptionId', '==', subId).get();
    const have = new Set(existing.docs.map((d) => d.id));
    const seen = new Set();
    let writes = [];
    const flush = async () => {
      for (let i = 0; i < writes.length; i += 400) {
        const batch = db.batch();
        writes.slice(i, i + 400).forEach((w) => w(batch));
        await batch.commit();
      }
      writes = [];
    };
    for (const e of events) {
      const id = itemIdFor(subId, e);
      if (seen.has(id)) continue;
      seen.add(id);
      const ref = col.doc(id);
      // 일정 내용은 매번 피드대로 갱신, 카테고리/공개범위/색은 처음 만들 때만 정해서 사용자가 바꾼 걸 지키지 않음
      const source = {
        type: 'event', title: e.title, note: e.note, location: e.location,
        start: Timestamp.fromMillis(e.startMs),
        end: e.endMs === null ? null : Timestamp.fromMillis(e.endMs),
        allDay: e.allDay, subscriptionId: subId,
      };
      if (have.has(id)) writes.push((b) => b.set(ref, source, { merge: true }));
      else {
        writes.push((b) => b.set(ref, {
          ...source, done: false, doneDates: [], categories: [sub.categoryId || 'default'],
          visibility: sub.visibility || 'shared', ownerUid: sub.ownerUid, repeat: 'none',
          rollEvery: 0, rollUnit: 'day', rollFrom: 'schedule', color: null, checklist: [], exceptions: [],
        }));
      }
    }
    for (const id of have) if (!seen.has(id)) writes.push((b) => b.delete(col.doc(id)));
    await flush();
    await subRef.set({ lastSyncAt: FieldValue.serverTimestamp(), lastCount: seen.size, skippedRepeating, error: null }, { merge: true });
    return { count: seen.size, skippedRepeating };
  } catch (err) {
    await subRef.set({ lastSyncAt: FieldValue.serverTimestamp(), error: String(err.message || err).slice(0, 200) }, { merge: true });
    throw err;
  }
}

async function requireMember(req, spaceId) {
  const uid = req.auth && req.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', '로그인이 필요해');
  const members = ((await db.doc(`spaces/${spaceId}`).get()).data() || {}).members || [];
  if (!members.includes(uid)) throw new HttpsError('permission-denied', '이 공간의 멤버가 아니야');
  return uid;
}

exports.syncSubscription = onCall({ timeoutSeconds: 120 }, async (req) => {
  const { spaceId, subId } = req.data || {};
  if (!spaceId || !subId) throw new HttpsError('invalid-argument', '잘못된 요청이야');
  await requireMember(req, spaceId);
  return syncOne(spaceId, subId);
});

/** 구독을 지우고 그 구독에서 만든 일정도 같이 지운다. */
exports.removeSubscription = onCall({ timeoutSeconds: 120 }, async (req) => {
  const { spaceId, subId } = req.data || {};
  if (!spaceId || !subId) throw new HttpsError('invalid-argument', '잘못된 요청이야');
  await requireMember(req, spaceId);
  const items = await db.collection(`spaces/${spaceId}/items`).where('subscriptionId', '==', subId).get();
  for (let i = 0; i < items.docs.length; i += 400) {
    const batch = db.batch();
    items.docs.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  await db.doc(`spaces/${spaceId}/subscriptions/${subId}`).delete();
  return { removed: items.size };
});

/** 12시간마다 모든 구독을 새로 받아온다 (킥오프 시간 변경, 새 경기 반영). */
exports.syncAllSubscriptions = onSchedule({ schedule: 'every 12 hours', timeZone: 'Asia/Seoul', timeoutSeconds: 300 }, async () => {
  const subs = await db.collectionGroup('subscriptions').get();
  for (const d of subs.docs) {
    const spaceId = d.ref.parent.parent.id;
    try {
      await syncOne(spaceId, d.id);
    } catch (err) {
      console.warn('구독 동기화 실패', spaceId, d.id, err.message);
    }
  }
});

// ---------------------------------------------------------------------------
// 일정/할 일 알림 (정해둔 시각에 푸시). 5분마다 확인한다.
// ---------------------------------------------------------------------------
exports.sendReminders = onSchedule({ schedule: 'every 5 minutes', timeZone: 'Asia/Seoul', timeoutSeconds: 120 }, async () => {
  const now = Date.now();
  const due = await db
    .collectionGroup('items')
    .where('remindAt', '>', Timestamp.fromMillis(now - lib.REMIND_WINDOW_MS))
    .where('remindAt', '<=', Timestamp.fromMillis(now))
    .get();
  const spaces = {};
  for (const d of due.docs) {
    const item = d.data();
    if (!lib.dueForReminder(item, now)) continue;
    const spaceId = d.ref.parent.parent.id;
    spaces[spaceId] = spaces[spaceId] || ((await db.doc(`spaces/${spaceId}`).get()).data() || {}).members || [];
    const prefs = {};
    for (const u of spaces[spaceId]) prefs[u] = (await db.doc(`users/${u}`).get()).data() || {};
    const message = lib.reminderMessage(item, now);
    let sent = 0;
    for (const u of lib.reminderRecipients(item, spaces[spaceId], prefs)) {
      sent += await pushTo(u, prefs[u], message, { spaceId, itemId: d.id, kind: 'reminder' });
    }
    // 같은 알림 시각으로 다시 보내지 않게 표시 (일정 시간을 바꾸면 remindAt이 달라져 새로 보냄)
    await d.ref.update({ remindSentFor: item.remindAt });
    console.log('알림', spaceId, d.id, '보낸 기기', sent);
  }
});
