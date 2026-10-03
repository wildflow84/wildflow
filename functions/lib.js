// 서버 함수의 순수 로직 (Firebase 없이 테스트 가능)

const NUDGE_MAX = 3; // 항목당 재촉 최대 횟수

/** 반복(규칙/이동형) 항목인지 */
function isRepeating(item) {
  return !!(item.rule || item.rollRule || (item.rollEvery || 0) > 0 || (item.repeat && item.repeat !== 'none'));
}

function millis(ts) {
  if (!ts) return 0;
  if (typeof ts.toMillis === 'function') return ts.toMillis();
  if (typeof ts._seconds === 'number') return ts._seconds * 1000;
  return Number(ts) || 0;
}

/** 재촉 횟수는 "같은 회차" 안에서만 센다: 날짜가 넘어가거나 완료 상태가 바뀌면 새로 시작 */
function nudgeKey(item) {
  return `${millis(item.start)}|${item.done ? 1 : 0}`;
}

/**
 * 재촉 가능 여부와 다음 횟수.
 * @returns {{allowed: boolean, count: number, next: number, key: string}}
 */
function nudgeState(item) {
  const key = nudgeKey(item);
  const count = item.nudgeKey === key ? item.nudgeCount || 0 : 0;
  return { allowed: count < NUDGE_MAX, count, next: count + 1, key };
}

/** 상대가 재촉을 받을 수 있는지 (기본 켜짐) */
function acceptsNudge(prefs) {
  return !prefs || prefs.allowNudge !== false;
}

/** 새로 공유됐다는 알림을 받을지 (기본 켜짐) */
function acceptsShared(prefs) {
  return !prefs || prefs.notifyShared !== false;
}

const SHARE_COOLDOWN_MS = 60 * 1000; // 같은 항목은 1분에 한 번만 알림

function canNotifyShared(item, nowMs) {
  return nowMs - millis(item.sharedNotifyAt) >= SHARE_COOLDOWN_MS;
}

/** 완료 알림을 받을지: 기본 켜짐, 반복 항목은 따로 켜야 한다 */
function acceptsComplete(prefs, item) {
  const p = prefs || {};
  if (p.notifyComplete === false) return false;
  if (isRepeating(item)) return p.notifyCompleteRepeating === true;
  return true;
}

function nudgeMessage(actorName, item, count) {
  const kind = item.type === 'todo' ? '할 일' : '일정';
  return {
    title: `${actorName}의 확인 요청 (${count}/${NUDGE_MAX})`,
    body: `${kind} "${item.title}" 확인해줘`,
  };
}

function shareMessage(actorName, item) {
  const kind = item.type === 'todo' ? '할 일' : '일정';
  return { title: `${actorName}이(가) ${kind}을(를) 공유했어`, body: `"${item.title}"` };
}

function completeMessage(actorName, item) {
  return { title: `${actorName}이(가) 완료했어`, body: `"${item.title}"` };
}

/** FCM 응답에서 더 이상 못 쓰는 토큰만 골라낸다 */
function deadTokens(tokens, responses) {
  const dead = [];
  responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
      dead.push(tokens[i]);
    }
  });
  return dead;
}

module.exports = {
  NUDGE_MAX,
  isRepeating,
  nudgeKey,
  nudgeState,
  acceptsNudge,
  acceptsComplete,
  acceptsShared,
  canNotifyShared,
  shareMessage,
  SHARE_COOLDOWN_MS,
  nudgeMessage,
  completeMessage,
  deadTokens,
};
