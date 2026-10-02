"""정밀 천문 계산(ephem)으로 음력 표와 24절기 표를 만들고, 1900~2049는 KASI(korean-lunar-calendar)와 대조한다.

사용: pip install ephem korean-lunar-calendar && python3 tool/gen_calendar_data.py
출력: lib/models/lunar_table.g.dart, lib/models/solar_term_table.g.dart
규칙: 한국 음력 = 동경 135도(UTC+9) 기준 삭(朔)이 있는 날이 초하루, 동지가 든 달이 11월, 중기가 없는 달이 윤달.
"""
import datetime as dt
import math
import sys

import ephem
from korean_lunar_calendar import KoreanLunarCalendar

FIRST_YEAR, LAST_YEAR = 1900, 2200
EPOCH = dt.date(1900, 1, 1)
KST = dt.timedelta(hours=9)

_sun = ephem.Sun()


def sun_longitude(t):
    """겉보기 태양 황경(도). ephem의 겉보기 적경/적위 + 진황도경사로 변환."""
    _sun.compute(t, epoch=t)
    ra, dec = float(_sun.g_ra), float(_sun.g_dec)
    jd = float(t) + 2415020.0  # ephem.Date는 1899-12-31 12:00 기준
    T = (jd - 2451545.0) / 36525.0
    eps0 = 23.0 + 26.0 / 60 + 21.448 / 3600 - (46.8150 * T + 0.00059 * T * T - 0.001813 * T ** 3) / 3600
    omega = math.radians(125.04452 - 1934.136261 * T)
    d_eps = 0.00256 * math.cos(omega)
    eps = math.radians(eps0 + d_eps)
    lon = math.atan2(math.sin(ra) * math.cos(eps) + math.tan(dec) * math.sin(eps), math.cos(ra))
    return math.degrees(lon) % 360


def kr_offset(utc):
    """해당 시점의 한국 표준시 오프셋. 서머타임은 음력 계산에 쓰지 않는다.
    1908-04-01~1911-12-31, 1954-03-21~1961-08-09 은 동경 127.5도(UTC+8:30), 그 외 UTC+9."""
    if utc < dt.datetime(1911, 12, 31, 15, 30):
        return dt.timedelta(hours=8, minutes=30)
    if dt.datetime(1954, 3, 20, 15, 30) <= utc < dt.datetime(1961, 8, 9, 15, 30):
        return dt.timedelta(hours=8, minutes=30)
    return KST


def to_kst_dn(t):
    """ephem 날짜(UTC) -> 한국 표준시 기준 날짜의 1900-01-01로부터의 일수."""
    u = ephem.Date(t).datetime()
    d = u + kr_offset(u)
    return (d.date() - EPOCH).days


def crossing(year, target):
    """해당 양력 연도에서 태양 황경이 target(도)을 지나는 순간."""
    # 춘분(0도)이 3/20.5 무렵이라는 근사로 시작
    doy = 79.5 + ((target % 360) / 360.0) * 365.2422
    if target % 360 >= 285:  # 소한~경칩은 같은 해 1~3월
        doy -= 365.2422
    start = ephem.Date(dt.datetime(year, 1, 1)) + doy
    lo, hi = start - 4, start + 4
    def diff(t):  # target 기준 -180..180 차이
        return (sun_longitude(t) - target + 180) % 360 - 180
    for _ in range(40):
        mid = (lo + hi) / 2
        if diff(mid) < 0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


TERM_LONGS = [(285 + 15 * i) % 360 for i in range(24)]  # 소한 285 ... 동지 270
# 인덱스: 0 소한 1 대한 2 입춘 3 우수 4 경칩 5 춘분 6 청명 7 곡우 8 입하 9 소만 10 망종 11 하지
#        12 소서 13 대서 14 입추 15 처서 16 백로 17 추분 18 한로 19 상강 20 입동 21 소설 22 대설 23 동지


def solar_terms(year):
    out = []
    for lon in TERM_LONGS:
        t = crossing(year, lon)
        out.append(t)
    return out


def main():
    print("절기 계산 중...", file=sys.stderr)
    terms = {}
    for y in range(FIRST_YEAR - 1, LAST_YEAR + 3):
        terms[y] = solar_terms(y)

    # 절기 표: 연도별 24개의 (KST 기준 일수) -> 연중일(1..366)
    term_rows = []
    for y in range(FIRST_YEAR, LAST_YEAR + 1):
        row = []
        for t in terms[y]:
            dn = to_kst_dn(t)
            d = EPOCH + dt.timedelta(days=dn)
            assert d.year == y, (y, d)
            row.append(d.timetuple().tm_yday)
        term_rows.append(row)

    # 중기(30도 배수) 목록: (KST dn, 월번호)
    zhongqi = []
    for y in range(FIRST_YEAR - 1, LAST_YEAR + 3):
        for lon, t in zip(TERM_LONGS, terms[y]):
            if lon % 30 == 0:
                month_no = ((lon // 30 + 1) % 12) + 1
                zhongqi.append((to_kst_dn(t), month_no, lon, y))
    zhongqi.sort()

    # 삭(新月) 목록
    print("삭 계산 중...", file=sys.stderr)
    starts = []
    t = ephem.Date("1898/12/1")
    end = ephem.Date("%d/6/1" % (LAST_YEAR + 3))
    while t < end:
        nm = ephem.next_new_moon(t)
        starts.append(to_kst_dn(nm))
        t = nm + 1
    # 중복 제거(같은 날 두 번은 없음)
    assert all(b > a for a, b in zip(starts, starts[1:]))

    def zq_in(a, b):  # [a,b) 에 든 중기들
        return [z for z in zhongqi if a <= z[0] < b]

    # 동지가 든 달 인덱스
    winter = []
    for i in range(len(starts) - 1):
        if any(z[1] == 11 for z in zq_in(starts[i], starts[i + 1])):
            winter.append(i)

    months = []  # (start_dn, length, lunar_year, month_no, leap)
    for a, b in zip(winter, winter[1:]):
        n = b - a
        assert n in (12, 13), (a, b, n)
        # 동지가 든 해(양력)
        wy = (EPOCH + dt.timedelta(days=starts[a])).year
        # 동지가 든 달의 시작이 11월 하순인지 12월인지와 무관하게 동지가 속한 양력 해
        z = [z for z in zq_in(starts[a], starts[a + 1]) if z[1] == 11][0]
        wy = z[3]
        leap_idx = None
        if n == 13:
            for j in range(a + 1, b):
                if not zq_in(starts[j], starts[j + 1]):
                    leap_idx = j
                    break
            assert leap_idx is not None
        no, ly = 11, wy
        for j in range(a, b):
            if leap_idx is not None and j == leap_idx:
                months.append((starts[j], starts[j + 1] - starts[j], ly, prev_no, True))
                continue
            months.append((starts[j], starts[j + 1] - starts[j], ly, no, False))
            prev_no = no
            no += 1
            if no == 13:
                no = 1
                ly += 1
    # 해별 표: months는 11월부터 시작하므로 음력 연도 기준으로 묶는다
    years = {}
    for st, ln, ly, no, leap in months:
        y = years.setdefault(ly, {"leap": 0, "bits": [], "months": []})
        y["months"].append((st, ln, no, leap))
    rows = []
    for ly in range(FIRST_YEAR, LAST_YEAR + 1):
        y = years.get(ly)
        if not y:
            continue
        ms = sorted(y["months"])
        if ms[0][2] != 1 or ms[0][3] or len(ms) < 12:
            continue
        leap = next((m[2] for m in ms if m[3]), 0)
        mask = sum((1 if m[1] == 30 else 0) << i for i, m in enumerate(ms))
        rows.append((ly, ms[0][0], leap, mask, len(ms)))

    astro_rows = {r[0]: r for r in rows}

    # ---- KASI 공식 데이터 (1900~2049) ----
    kasi = KoreanLunarCalendar()
    kasi_rows, month_golden = load_kasi(kasi)

    # ---- 검증: 천문 계산 결과가 KASI와 일치하는가 (1913~2049, 일 단위 전수) ----
    mism = full_day_check(list(astro_rows.values()), kasi, from_year=1913)
    if MISM_YEARS:
        print("  불일치 연도:", dict(sorted(MISM_YEARS.items())))
    print("천문 계산 vs KASI (1913~2049, 일 단위 전수): 불일치 %d일" % mism)
    if mism:
        sys.exit(1)

    # ---- 병합: 2049년까지 KASI, 2050년부터 천문 계산 ----
    merged = [kasi_rows[y] for y in sorted(kasi_rows)]
    last = merged[-1]
    last_end = last[1] + sum(30 if (last[3] >> i) & 1 else 29 for i in range(last[4]))
    first_astro = astro_rows[last[0] + 1]
    assert first_astro[1] == last_end, ("경계 불연속", last_end, first_astro[1])
    for y in range(last[0] + 1, LAST_YEAR + 1):
        r = astro_rows[y]
        assert 353 <= sum(30 if (r[3] >> i) & 1 else 29 for i in range(r[4])) <= 385
        merged.append(r)

    write_tables(merged, term_rows, month_golden)


def load_kasi(kasi):
    """KASI 패키지를 하루씩 변환해서 연도별 표와 월 시작 골든 목록을 만든다."""
    days = []
    d = dt.date(1900, 1, 1)
    end = dt.date(2050, 12, 31)
    while d <= end:
        assert kasi.setSolarDate(d.year, d.month, d.day)
        days.append(((d - EPOCH).days, kasi.lunarYear, kasi.lunarMonth, kasi.lunarDay, kasi.isIntercalation))
        d += dt.timedelta(days=1)
    starts = [[off, ly, lm, leap, 0] for off, ly, lm, ld, leap in days if ld == 1]
    for i in range(len(starts) - 1):
        starts[i][4] = starts[i + 1][0] - starts[i][0]
    starts = starts[:-1]
    years = {}
    for off, ly, lm, leap, ln in starts:
        y = years.setdefault(ly, {"start": off, "leap": 0, "bits": []})
        if lm == 1 and not leap:
            y["start"] = off
        if leap:
            y["leap"] = lm
        y["bits"].append(1 if ln == 30 else 0)
    rows = {}
    for ly in sorted(years):
        y = years[ly]
        if len(y["bits"]) < 12:
            continue
        rows[ly] = (ly, y["start"], y["leap"], sum(b << i for i, b in enumerate(y["bits"])), len(y["bits"]))
    golden = [(off, ly, lm, 1 if leap else 0) for off, ly, lm, leap, _ in starts]
    return rows, golden


def lunar_of_day(rows, dn):
    """표 기준으로 dn의 (음력년, 월, 일, 윤달)."""
    for ly, start, leap, mask, n in rows:
        total = sum(30 if (mask >> i) & 1 else 29 for i in range(n))
        if start <= dn < start + total:
            off = dn - start
            no, is_leap = 1, False
            for i in range(n):
                ln = 30 if (mask >> i) & 1 else 29
                if off < ln:
                    return (ly, no, off + 1, is_leap)
                off -= ln
                if leap and no == leap and not is_leap:
                    is_leap = True
                else:
                    is_leap = False
                    no += 1
    return None


MISM_YEARS = {}


def full_day_check(rows, kasi, from_year=1913):
    mism = 0
    by_start = sorted(rows, key=lambda r: r[1])
    d = dt.date(from_year, 1, 1)
    last = dt.date(2049, 12, 31)
    while d <= last:
        dn = (d - EPOCH).days
        got = lunar_of_day(rows, dn)
        kasi.setSolarDate(d.year, d.month, d.day)
        want = (kasi.lunarYear, kasi.lunarMonth, kasi.lunarDay, bool(kasi.isIntercalation))
        if got != want:
            mism += 1
            MISM_YEARS[d.year] = MISM_YEARS.get(d.year, 0) + 1
        d += dt.timedelta(days=1)
    return mism


def write_tables(rows, term_rows, month_golden):
    with open("lib/models/lunar_table.g.dart", "w") as f:
        f.write("// 자동 생성: tool/gen_calendar_data.py (1900~2049 KASI 공식 데이터, 2050~2200 천문 계산)\n")
        f.write("// 각 행: [음력해, 설날(1900-01-01부터의 일수), 윤달 월(없으면 0), 월길이 비트(30일=1, 윤달 포함 순서), 월 개수]\n")
        f.write("const int lunarTableFirstYear = %d;\nconst int lunarTableLastYear = %d;\n" % (rows[0][0], rows[-1][0]))
        f.write("const List<List<int>> lunarTable = [\n")
        for r in rows:
            f.write("  [%d, %d, %d, %d, %d],\n" % r)
        f.write("];\n")
    import os
    os.makedirs("test/golden", exist_ok=True)
    with open("test/golden/lunar_month_starts.csv", "w") as f:
        f.write("# 1900-01-01 기준 일수, 음력년, 월, 윤달(1/0) -- KASI 월 시작일 (1900~2050)\n")
        for off, ly, lm, leap in month_golden:
            f.write("%d,%d,%d,%d\n" % (off, ly, lm, leap))
    with open("lib/models/solar_term_table.g.dart", "w") as f:
        f.write("// 자동 생성: tool/gen_calendar_data.py (ephem 기반 겉보기 태양 황경, KST 날짜)\n")
        f.write("// 각 행은 해당 양력 연도의 24절기 연중일(1..366). 순서: 소한 대한 입춘 우수 경칩 춘분 청명 곡우 입하 소만 망종 하지 소서 대서 입추 처서 백로 추분 한로 상강 입동 소설 대설 동지\n")
        f.write("const int solarTermFirstYear = %d;\n" % FIRST_YEAR)
        f.write("const List<List<int>> solarTermTable = [\n")
        for r in term_rows:
            f.write("  [%s],\n" % ", ".join(map(str, r)))
        f.write("];\n")
    print("완료: lunar_table.g.dart (%d년), solar_term_table.g.dart (%d년)" % (len(rows), len(term_rows)))


if __name__ == "__main__":
    main()
