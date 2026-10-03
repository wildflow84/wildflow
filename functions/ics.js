// iCalendar(.ics) 구독 피드 파서: 경기 일정/방영 일정처럼 단순한 일정용.
// 반복(RRULE) 일정은 지원하지 않고 건너뛴다.

function unfold(text) {
  const out = [];
  for (const raw of text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n')) {
    if ((raw.startsWith(' ') || raw.startsWith('\t')) && out.length) out[out.length - 1] += raw.slice(1);
    else out.push(raw);
  }
  return out;
}

const unescapeText = (v) =>
  v.replace(/\\n/gi, '\n').replace(/\\,/g, ',').replace(/\;/g, ';').replace(/\\\\/g, '\\');

function parseLine(line) {
  const colon = line.indexOf(':');
  if (colon <= 0) return null;
  const head = line.slice(0, colon).split(';');
  const params = {};
  for (const p of head.slice(1)) {
    const eq = p.indexOf('=');
    if (eq > 0) params[p.slice(0, eq).toUpperCase()] = p.slice(eq + 1);
  }
  return { name: head[0].toUpperCase(), params, value: line.slice(colon + 1) };
}

/** tz 시간대의 벽시계 시각(년월일시분초)을 UTC 밀리초로 */
function zonedToUtcMs(y, mo, d, h, mi, s, tz) {
  const guess = Date.UTC(y, mo - 1, d, h, mi, s);
  let fmt;
  try {
    fmt = new Intl.DateTimeFormat('en-US', {
      timeZone: tz, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric',
      hour: 'numeric', minute: 'numeric', second: 'numeric',
    });
  } catch {
    return guess; // 알 수 없는 시간대 이름: 그대로
  }
  const wall = (ms) => {
    const p = Object.fromEntries(fmt.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
    return Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
  };
  let ms = guess - (wall(guess) - guess);
  ms = guess - (wall(ms) - ms);
  return ms;
}

const KST = 'Asia/Seoul';

/** DATE / DATE-TIME 값을 {ms, dateOnly}로. Z는 UTC, TZID는 그 시간대, 아무것도 없으면 한국 시간으로 본다. */
function parseDate(value, params = {}) {
  const m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/.exec(value.trim());
  if (!m) return null;
  const [y, mo, d] = [+m[1], +m[2], +m[3]];
  if (m[4] === undefined) return { ms: zonedToUtcMs(y, mo, d, 0, 0, 0, KST), dateOnly: true };
  const [h, mi, s] = [+m[4], +m[5], +(m[6] || 0)];
  if (m[7] === 'Z') return { ms: Date.UTC(y, mo - 1, d, h, mi, s), dateOnly: false };
  return { ms: zonedToUtcMs(y, mo, d, h, mi, s, params.TZID || KST), dateOnly: false };
}

/** @returns {{events: Array, skippedRepeating: number}} */
function parseFeed(text) {
  const events = [];
  let skippedRepeating = 0;
  let cur = null;
  for (const line of unfold(text)) {
    const t = line.trim();
    if (t === 'BEGIN:VEVENT') { cur = {}; continue; }
    if (t === 'END:VEVENT') {
      if (cur) {
        const e = toEvent(cur);
        if (e === 'repeating') skippedRepeating++;
        else if (e) events.push(e);
      }
      cur = null;
      continue;
    }
    const p = parseLine(line);
    if (p && cur) cur[p.name] = cur[p.name] || p;
  }
  return { events, skippedRepeating };
}

function toEvent(m) {
  if (m.RRULE) return 'repeating';
  if (!m.DTSTART) return null;
  const start = parseDate(m.DTSTART.value, m.DTSTART.params);
  if (!start) return null;
  if (((m.STATUS && m.STATUS.value) || '').toUpperCase() === 'CANCELLED') return null;
  let endMs = null;
  if (m.DTEND) {
    const e = parseDate(m.DTEND.value, m.DTEND.params);
    if (e) endMs = start.dateOnly ? e.ms - 24 * 3600 * 1000 : e.ms; // 종일의 DTEND는 다음 날(미포함)
  } else if (m.DURATION && !start.dateOnly) {
    const d = /^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?$/.exec(m.DURATION.value);
    if (d) endMs = start.ms + ((+d[1] || 0) * 86400 + (+d[2] || 0) * 3600 + (+d[3] || 0) * 60) * 1000;
  }
  if (endMs !== null && endMs <= start.ms) endMs = null;
  const text = (k) => (m[k] ? unescapeText(m[k].value).trim() : '');
  return {
    uid: text('UID'),
    title: text('SUMMARY') || '(제목 없음)',
    note: text('DESCRIPTION'),
    location: text('LOCATION'),
    startMs: start.ms,
    endMs,
    allDay: start.dateOnly,
  };
}

module.exports = { parseFeed, parseDate, zonedToUtcMs };
