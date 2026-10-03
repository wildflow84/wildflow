const test = require('node:test');
const assert = require('node:assert');
const { parseFeed, parseDate, zonedToUtcMs } = require('./ics');

test('시간대 변환: 런던/서울/UTC', () => {
  // 2026-10-24 12:30 영국(BST, UTC+1) = 11:30 UTC = 20:30 KST
  assert.equal(zonedToUtcMs(2026, 10, 24, 12, 30, 0, 'Europe/London'), Date.UTC(2026, 9, 24, 11, 30));
  // 겨울(GMT): 2026-12-26 15:00 런던 = 15:00 UTC
  assert.equal(zonedToUtcMs(2026, 12, 26, 15, 0, 0, 'Europe/London'), Date.UTC(2026, 11, 26, 15, 0));
  assert.equal(zonedToUtcMs(2026, 10, 3, 9, 0, 0, 'Asia/Seoul'), Date.UTC(2026, 9, 3, 0, 0));
  assert.equal(parseDate('20261024T113000Z').ms, Date.UTC(2026, 9, 24, 11, 30));
  assert.equal(parseDate('20261024T123000', { TZID: 'Europe/London' }).ms, Date.UTC(2026, 9, 24, 11, 30));
  assert.equal(parseDate('20261024').dateOnly, true);
  assert.equal(parseDate('20261024').ms, Date.UTC(2026, 9, 23, 15, 0)); // 한국 자정
  assert.equal(parseDate('nope'), null);
});

const FEED = `BEGIN:VCALENDAR
BEGIN:VEVENT
UID:m1@x
DTSTART:20261024T113000Z
DTEND:20261024T133000Z
SUMMARY:Arsenal v Everton
LOCATION:Emirates Stadium\\, London
DESCRIPTION:Premier League\\nMatchweek 9
END:VEVENT
BEGIN:VEVENT
UID:m2@x
DTSTART;VALUE=DATE:20261101
DTEND;VALUE=DATE:20261103
SUMMARY:Cup
 week
END:VEVENT
BEGIN:VEVENT
UID:m3@x
DTSTART:20261110T200000Z
STATUS:CANCELLED
SUMMARY:Cancelled
END:VEVENT
BEGIN:VEVENT
UID:m4@x
DTSTART:20261111T200000Z
RRULE:FREQ=WEEKLY
SUMMARY:Weekly
END:VEVENT
BEGIN:VEVENT
UID:m5@x
DTSTART:20261112T200000Z
DURATION:PT2H
SUMMARY:Duration
END:VEVENT
END:VCALENDAR`;

test('피드 파싱: 이스케이프, 종일 기간, 취소/반복 제외, DURATION', () => {
  const { events, skippedRepeating } = parseFeed(FEED);
  assert.equal(skippedRepeating, 1);
  assert.equal(events.length, 3);
  const [a, b, c] = events;
  assert.equal(a.title, 'Arsenal v Everton');
  assert.equal(a.location, 'Emirates Stadium, London');
  assert.equal(a.note, 'Premier League\nMatchweek 9');
  assert.equal(a.endMs - a.startMs, 2 * 3600 * 1000);
  assert.equal(a.allDay, false);
  assert.equal(b.title, 'Cupweek');
  assert.equal(b.allDay, true);
  assert.equal(b.endMs - b.startMs, 24 * 3600 * 1000); // 1~2일 (3일 미포함)
  assert.equal(c.endMs - c.startMs, 2 * 3600 * 1000);
});
