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

function shareMessage(actorName, item, partnerUid) {
  const kind = item.type === 'todo' ? '할 일' : '일정';
  // 상대에게 맡긴 할 일이면 그렇게 알려준다
  if (item.type === 'todo' && partnerUid && item.assignee === partnerUid) {
    return { title: `${actorName}이(가) 할 일을 맡겼어`, body: `"${item.title}"` };
  }
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

const REMIND_WINDOW_MS = 15 * 60 * 1000; // 놓친 알림은 15분까지만 늦게 보낸다

/** 지금 알림을 보낼 차례인지: remindAt이 지났고(최대 15분), 같은 시각으로 이미 보낸 적 없고, 아직 끝난 게 아니면 */
function dueForReminder(item, nowMs) {
  const at = millis(item.remindAt);
  if (!at || at > nowMs || nowMs - at > REMIND_WINDOW_MS) return false;
  if (millis(item.remindSentFor) === at) return false;
  if (item.done) return false;
  return true;
}

function reminderMessage(item, nowMs) {
  const startMs = millis(item.start);
  let when;
  if (item.allDay) when = '오늘';
  else {
    const diff = Math.round((startMs - nowMs) / 60000);
    when = diff <= 1 ? '지금' : diff < 90 ? `${diff}분 뒤` : diff < 36 * 60 ? `${Math.round(diff / 60)}시간 뒤` : '내일';
  }
  const kind = item.type === 'todo' ? '마감' : '일정';
  return { title: `${when} ${kind}`, body: `"${item.title}"` };
}

/** 알림 받을 사람들: 만든 사람은 항상, 같이 보기 항목이면 상대도 (상대가 끄지 않았다면) */
function reminderRecipients(item, members, prefsByUid) {
  return members.filter((u) => {
    const p = prefsByUid[u] || {};
    if (p.notifyReminder === false) return false;
    if (u === item.ownerUid) return true;
    return item.visibility === 'shared';
  });
}

// ---------------------------------------------------------------------------
// 출발 시간 알림: 현재 위치에서 장소까지 걸리는 시간으로 "지금 출발할 때"를 계산한다.
// ---------------------------------------------------------------------------
const DEPART_WINDOW_MS = 15 * 60 * 1000; // 놓친 알림은 15분까지만 늦게 보낸다
const DEPART_BUFFER_MIN = 10; // 도착 여유 시간
const LOC_FRESH_MS = 3 * 60 * 60 * 1000; // 이 시간보다 오래된 위치는 쓰지 않는다

/** 두 좌표 사이 직선거리(m) */
function haversineM(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/** 길찾기 서비스를 못 쓸 때의 어림값(초): 직선거리 x 1.4(굽은 길), 평균 35km/h */
function fallbackDurationSec(distM) {
  return Math.round(((distM * 1.4) / (35000 / 3600)));
}

/** 이동 수단별 어림 시간(초). car는 길찾기 실패 시의 대체값, walk/transit은 직선거리 기반 어림값 */
function estimateDurationSec(mode, distM) {
  if (mode === 'walk') return Math.round((distM * 1.3) / (4500 / 3600)); // 시속 4.5km, 굽은 길 1.3배
  if (mode === 'transit') return Math.round((distM * 1.35) / (22000 / 3600)) + 10 * 60; // 시속 22km + 걷기/대기 10분
  return fallbackDurationSec(distM);
}

/** 위치가 쓸 만큼 최근인지 */
function locFresh(lastLoc, nowMs) {
  if (!lastLoc || typeof lastLoc.lat !== 'number' || typeof lastLoc.lng !== 'number') return false;
  const at = millis(lastLoc.at);
  return !!at && nowMs - at <= LOC_FRESH_MS && at <= nowMs + 60000;
}

/** 지금 출발 알림을 보낼 차례인지 */
function dueForDepart(item, durationSec, nowMs) {
  const startMs = millis(item.departFrom);
  if (!startMs || startMs <= nowMs) return false;
  if (item.done) return false;
  if (millis(item.departSentFor) === startMs) return false;
  const leaveAt = startMs - durationSec * 1000 - DEPART_BUFFER_MIN * 60000;
  return nowMs >= leaveAt && nowMs - leaveAt <= DEPART_WINDOW_MS;
}

function kstHHmm(ms) {
  return new Date(ms + 9 * 3600 * 1000).toISOString().slice(11, 16);
}

function departMessage(item, durationSec, approximate, reason) {
  const modeName = item.departMode === 'walk' ? '걸어서 ' : item.departMode === 'transit' ? '대중교통으로 ' : '';
  const startMs = millis(item.departFrom);
  const min = Math.max(1, Math.round(durationSec / 60));
  const where = item.location ? ` ${item.location}` : '';
  return {
    title: '지금 출발해야 해',
    body: `"${item.title}"${where} · ${modeName}약 ${min}분${approximate ? '(대략' + (reason ? ', 길찾기 ' + reason : '') + ')' : ''} 걸려, ${kstHHmm(startMs)} 시작`,
  };
}

module.exports = {
  DEPART_WINDOW_MS,
  DEPART_BUFFER_MIN,
  LOC_FRESH_MS,
  haversineM,
  fallbackDurationSec,
  estimateDurationSec,
  locFresh,
  dueForDepart,
  departMessage,
  REMIND_WINDOW_MS,
  dueForReminder,
  reminderMessage,
  reminderRecipients,
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
