'use strict';
// 브리핑 파일 기록의 Firestore 쪽 연결: 가족 공간 찾기, 데이터 읽기, 파일 맞추기. 실패해도 앱에는 영향이 없게 오류는 삼키고 로그만 남긴다.
const briefing = require('./briefing');
const { loadSpaceFromFirestore } = require('./digest');

/** 가족 공간 id 와 이름표. 공간이 없으면 null */
async function findFamilySpace(db) {
  const snap = await db.collection('spaces').get();
  const spaces = [];
  snap.forEach((d) => {
    const data = d.data() || {};
    spaces.push({ id: d.id, members: Array.isArray(data.members) ? data.members : [], names: data.names && typeof data.names === 'object' ? data.names : {} });
  });
  const id = briefing.pickFamilySpace(spaces);
  return id ? spaces.find((s) => s.id === id) : null;
}

/**
 * 다이제스트 파일을 최신으로 맞춘다.
 * @param {object} o
 * @param {object} o.db Firestore
 * @param {string} [o.token] GitHub 토큰. 없으면 아무것도 하지 않는다
 * @param {string} [o.onlySpaceId] 이 공간이 가족 공간일 때만 한다 (이벤트 트리거용)
 * @param {Function} [o.fetch]
 * @param {number} [o.nowMs]
 * @param {(msg:string)=>void} [o.log] 토큰은 절대 넘기지 않는다
 * @returns {Promise<string>} 'no-token' | 'no-space' | 'other-space' | 'unchanged' | 'written' | 'error'
 */
async function runBriefing({ db, token, onlySpaceId, fetch, nowMs = Date.now(), log = () => {} }) {
  if (!token) return 'no-token';
  try {
    const space = await findFamilySpace(db);
    if (!space) return 'no-space';
    if (onlySpaceId && onlySpaceId !== space.id) return 'other-space';
    const data = await loadSpaceFromFirestore(db, space.id);
    const body = briefing.buildBody({ nowMs, docs: data.docs, names: space.names, customDays: data.customDays });
    const client = briefing.createGithubClient({ token, fetch });
    const res = await briefing.syncFile({ client, body, nowMs });
    log(`briefing ${res.status} revision=${res.revision}`);
    return res.status;
  } catch (e) {
    // 앱 동작에는 영향이 없다. 상태 코드만 남기고 토큰이나 응답 본문은 남기지 않는다.
    log(`briefing error ${e && e.status ? `status=${e.status}` : e && e.name ? e.name : 'unknown'}`);
    return 'error';
  }
}

module.exports = { runBriefing, findFamilySpace };
