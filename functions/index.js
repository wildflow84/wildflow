const { setGlobalOptions } = require('firebase-functions/v2');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const lib = require('./lib');

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
