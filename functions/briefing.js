'use strict';
// 브리핑용 다이제스트 파일 기록: 공유(shared) 일정/할 일을 14일치 마크다운으로 만들어 GitHub 저장소 파일을 최신 상태로 다시 쓴다.
// 순수 로직(파일 만들기, revision 판단, 디바운스)과 GitHub 호출(주입한 fetch)을 나눠서 Firebase/네트워크 없이 테스트한다.
const { ymd, dateKeyOf } = require('./lunar');
const calc = require('./itemcalc');
const { holidayNamesOn } = require('./holidays');

const DAYS = 14;
const WEEKDAY = ['일', '월', '화', '수', '목', '금', '토']; // ymd().wd: 1=월 ... 7=일 -> 7 % 7 = 0

const TARGET = Object.freeze({
  owner: 'wildflow84',
  repo: 'family-portfolio',
  branch: 'calendar-digest',
  path: 'calendar/digest.md',
});

// ---------- 문자열 도우미 ----------
/** 이름표 정규화: 공백 제거 ("대희 아빠" -> "대희아빠") */
const normalizeName = (n) => String(n == null ? '' : n).replace(/\s+/g, '');

/** 필드 값 정리: 줄바꿈은 공백으로, 구분자 '|' 는 '/' 로 */
const cleanField = (s) => String(s == null ? '' : s).replace(/[\r\n]+/g, ' ').replace(/\|/g, '/').trim();

const hhmm = (p) => `${String(p.h).padStart(2, '0')}:${String(p.mi).padStart(2, '0')}`;

/** 한국시간 ISO8601 (+09:00) */
function isoKst(ms) {
  return new Date(ms + calc.KST_MS).toISOString().slice(0, 19) + '+09:00';
}

// ---------- 항목 -> 줄 ----------
/** 이름표(uid -> 이름)로 사람 표시. 모르면 "공통" */
function personLabel(uid, names) {
  const n = uid && names ? normalizeName(names[uid]) : '';
  return n || '공통';
}

/** 일정 시간: "HH:MM-HH:MM" / "HH:MM" / "종일". 여러 날 시각 일정은 첫날만 시각, 나머지 날은 "종일" */
function eventTime(item, dn) {
  if (item.allDay) return '종일';
  const multiDay = !item.isRecurring && item.end && item.end.dn !== item.start.dn;
  if (multiDay) return dn === item.start.dn ? hhmm(item.start) : '종일';
  const hasEnd = item.end && (item.end.h !== 0 || item.end.mi !== 0);
  return hasEnd ? `${hhmm(item.start)}-${hhmm(item.end)}` : hhmm(item.start);
}

const todoTime = (item) => (item.allDay ? '종일' : `~${hhmm(item.start)}`);

const bySchedule = (a, b) => {
  const ka = a.allDay ? -1 : a.start.h * 60 + a.start.mi;
  const kb = b.allDay ? -1 : b.start.h * 60 + b.start.mi;
  return ka - kb || a.startMs - b.startMs || a.title.localeCompare(b.title, 'ko');
};

/**
 * 14일치 본문(날짜 섹션들)을 만든다. 헤더(revision, generated_at)는 포함하지 않는다.
 * @param {object} p
 * @param {number} p.nowMs
 * @param {Array<{id:string,data:object}>} p.docs 항목 문서들 (여기서 한 번 더 shared 만 남긴다)
 * @param {Object<string,string>} p.names uid -> 이름표
 * @param {Array<{date:any,name:string,holiday?:boolean}>} [p.customDays]
 * @returns {string} 마지막 줄바꿈 없음
 */
function buildBody({ nowMs, docs, names, customDays = [] }) {
  const today = calc.kstParts(nowMs).dn;
  // 프라이버시: 같이 보기(shared) 항목만. 소유자가 누구든 private 은 절대 쓰지 않는다.
  const items = [];
  for (const d of docs) {
    const data = d.data || {};
    if (data.visibility !== 'shared' || !data.start) continue;
    items.push(calc.toItem(d.id, data));
  }
  const custom = customDays
    .map((c) => ({ dn: calc.kstParts(calc.millis(c.date)).dn, name: String(c.name || ''), holiday: c.holiday !== false }))
    .filter((c) => c.name);

  const sections = [];
  for (let i = 0; i < DAYS; i++) {
    const dn = today + i;
    const lines = [];
    for (const name of [...new Set(holidayNamesOn(dn, custom))]) lines.push(`- [H] ${cleanField(name)}`);

    const events = items.filter((it) => it.type === 'event' && calc.occursOn(it, dn)).sort(bySchedule);
    for (const it of events) {
      lines.push(`- [E] ${eventTime(it, dn)} | ${cleanField(it.title)} | ${personLabel(it.ownerUid, names)} | ${cleanField(it.location)}`.trimEnd());
    }

    const todos = [];
    for (const it of items) {
      if (it.type !== 'todo') continue;
      const done = calc.isDoneOn(it, dn);
      const overdue = !done && calc.isOverdue(it, nowMs);
      const occurs = calc.occursOn(it, dn);
      if (i === 0) {
        // 오늘 섹션: 오늘 마감 + 마감이 지난 미완료 + 오늘 완료한 지난 할 일
        const doneToday = it.done && !it.isRecurring && it.start.dn < today && it.lastDoneMs && calc.kstParts(it.lastDoneMs).dn === today;
        if (!occurs && !overdue && !doneToday) continue;
        todos.push({ it, status: overdue ? '지남' : it.done || done ? '완료' : '' });
      } else if (occurs) {
        todos.push({ it, status: done ? '완료' : '' });
      }
    }
    todos.sort((a, b) => bySchedule(a.it, b.it));
    for (const { it, status } of todos) {
      const who = personLabel(it.assignee || it.ownerUid, names);
      lines.push(`- [T] ${todoTime(it)} | ${cleanField(it.title)} | ${who} | ${status}`.trimEnd());
    }

    const { y, m, d, wd } = ymd(dn);
    const head = `## ${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')} (${WEEKDAY[wd % 7]})`;
    sections.push([head, ...(lines.length > 0 ? lines : ['(항목 없음)'])].join('\n'));
  }
  return sections.join('\n\n');
}

/** 파일 전체 본문 */
function renderFile({ revision, generatedAtMs, body }) {
  return [
    '# OURDAY CALENDAR DIGEST',
    `revision: ${revision}`,
    `generated_at: ${isoKst(generatedAtMs)}`,
    'scope: shared-only',
    `days: ${DAYS}`,
    '',
    body,
    '',
  ].join('\n');
}

/** 기존 파일에서 revision 과 날짜 섹션 본문을 읽는다. 읽을 수 없으면 revision 0, 본문 빈 문자열 */
function parseDigest(text) {
  const t = String(text == null ? '' : text).replace(/\r\n/g, '\n');
  const rev = /^revision:\s*(\d+)\s*$/m.exec(t);
  const at = t.search(/^## /m);
  return { revision: rev ? Number(rev[1]) : 0, body: at >= 0 ? t.slice(at).trim() : '' };
}

/** 이전 파일 내용과 새 본문을 비교해 쓸지, 어떤 revision 으로 쓸지 정한다. 본문이 같으면 쓰지 않는다. */
function decideWrite(existingText, newBody) {
  const prev = parseDigest(existingText);
  if (prev.body === String(newBody).trim()) return { write: false, revision: prev.revision };
  return { write: true, revision: prev.revision + 1 };
}

// ---------- GitHub Contents API ----------
class GithubError extends Error {
  constructor(status, message) {
    super(`GitHub ${status}${message ? `: ${message}` : ''}`);
    this.status = status;
  }
}

/**
 * GitHub 파일 읽기/쓰기. 토큰은 요청 헤더에만 쓰고, 오류 메시지/로그에는 절대 넣지 않는다.
 * @param {{token:string, fetch?:Function, target?:object}} o
 */
function createGithubClient({ token, fetch: fetchImpl = globalThis.fetch, target = TARGET }) {
  const url = `https://api.github.com/repos/${target.owner}/${target.repo}/contents/${target.path.split('/').map(encodeURIComponent).join('/')}`;
  const headers = () => ({
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'ourday-briefing',
    'Content-Type': 'application/json',
  });
  const apiMessage = async (res) => {
    try {
      const j = await res.json();
      return typeof j.message === 'string' ? j.message.slice(0, 120) : '';
    } catch (_) {
      return '';
    }
  };
  return {
    /** @returns {Promise<{sha:string,text:string}|null>} 파일이 없으면 null */
    async getFile() {
      const res = await fetchImpl(`${url}?ref=${encodeURIComponent(target.branch)}`, { method: 'GET', headers: headers() });
      if (res.status === 404) return null;
      if (!res.ok) throw new GithubError(res.status, await apiMessage(res));
      const j = await res.json();
      const text = Buffer.from(String(j.content || ''), j.encoding === 'base64' ? 'base64' : 'utf8').toString('utf8');
      return { sha: j.sha, text };
    },
    /** @returns {Promise<{ok:true}|{conflict:true}>} sha 충돌(409/422)은 conflict 로 돌려준다 */
    async putFile({ text, sha, message }) {
      const body = { message, content: Buffer.from(text, 'utf8').toString('base64'), branch: target.branch };
      if (sha) body.sha = sha;
      const res = await fetchImpl(url, { method: 'PUT', headers: headers(), body: JSON.stringify(body) });
      if (res.status === 409 || res.status === 422) return { conflict: true };
      if (!res.ok) throw new GithubError(res.status, await apiMessage(res));
      return { ok: true };
    },
  };
}

/**
 * 파일을 최신 상태로 맞춘다.
 * 본문이 같으면 아무것도 하지 않고, 다르면 revision +1 로 쓴다. sha 충돌이면 최신을 다시 읽어 재시도한다.
 * @returns {Promise<{status:'unchanged'|'written', revision:number}>}
 */
async function syncFile({ client, body, nowMs, maxAttempts = 3 }) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const file = await client.getFile();
    const decision = decideWrite(file ? file.text : '', body);
    if (!decision.write) return { status: 'unchanged', revision: decision.revision };
    const text = renderFile({ revision: decision.revision, generatedAtMs: nowMs, body });
    const res = await client.putFile({ text, sha: file ? file.sha : undefined, message: `calendar digest: revision ${decision.revision}` });
    if (res.ok) return { status: 'written', revision: decision.revision };
    // 충돌: 그 사이 파일이 바뀌었다. 다시 읽어서(바뀐 본문이 이미 같을 수도 있다) 재시도
  }
  throw new GithubError(409, 'sha 충돌이 계속돼서 포기');
}

// ---------- 공간 고르기 / 변경 걸러내기 / 디바운스 ----------
/** 가족 공간: 구성원이 가장 많은 공간 (같으면 id 순). 없으면 null */
function pickFamilySpace(spaces) {
  const list = [...spaces].map((s) => ({ id: s.id, n: Array.isArray(s.members) ? s.members.length : 0 }));
  if (list.length === 0) return null;
  list.sort((a, b) => b.n - a.n || (a.id < b.id ? -1 : 1));
  return list[0].id;
}

// 요약 내용과 상관없는 서버 쪽 필드 (알림 시각, 재촉 횟수 등)
const VOLATILE = new Set([
  'remindAt', 'remindTimes', 'remindSentFor', 'departFrom', 'departSentFor', 'nudgeKey', 'nudgeCount',
  'sharedNotifyAt', 'lastDoneBy', 'photoUrl', 'note', 'lat', 'lng', 'overseas', 'color', 'checklist', 'checksByDate',
]);

const stable = (v) => {
  if (v == null || typeof v !== 'object') return JSON.stringify(v === undefined ? null : v);
  if (typeof v.toMillis === 'function') return `t${v.toMillis()}`;
  if (Array.isArray(v)) return `[${v.map(stable).join(',')}]`;
  return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${stable(v[k])}`).join(',')}}`;
};

/** 이 변경이 다이제스트에 영향을 줄 수 있는지. 나만 보기끼리의 수정이나 알림 필드만 바뀐 경우는 건너뛴다. */
function isRelevantChange(before, after) {
  const sharedB = !!before && before.visibility === 'shared';
  const sharedA = !!after && after.visibility === 'shared';
  if (!sharedB && !sharedA) return false;
  const pick = (d) => {
    if (!d) return null;
    const o = {};
    for (const k of Object.keys(d)) if (!VOLATILE.has(k)) o[k] = d[k];
    return o;
  };
  return stable(pick(before)) !== stable(pick(after));
}

/**
 * 연속 수정 디바운스: 마지막 이벤트만 [debounceMs] 뒤에 [run] 을 실행한다.
 * @param {{store:{setLast:Function,getLast:Function}, eventId:string, sleep:Function, debounceMs:number, run:Function}} o
 * @returns {Promise<'superseded'|any>}
 */
async function debounced({ store, eventId, sleep, debounceMs, run }) {
  await store.setLast(eventId);
  await sleep(debounceMs);
  if ((await store.getLast()) !== eventId) return 'superseded';
  return run();
}

module.exports = {
  DAYS, TARGET, normalizeName, cleanField, isoKst, personLabel, eventTime, todoTime,
  buildBody, renderFile, parseDigest, decideWrite, GithubError, createGithubClient, syncFile,
  pickFamilySpace, isRelevantChange, debounced,
};
