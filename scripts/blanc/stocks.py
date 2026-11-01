# -*- coding: utf-8 -*-
"""
주식 실적 발표 수집기 (실제 데이터만 사용)

1) 미국 상장 종목: Finnhub Earnings Calendar  (비밀키 FINNHUB_KEY)
   - 발표일, 장전(BMO)/장후(AMC), EPS·매출 예상치, 발표 후 실제치 → 서프라이즈 자동 계산
2) 국내 종목: 금융감독원 OpenDART 공시 목록  (비밀키 DART_KEY)
   - 영업(잠정)실적 공시, 기업설명회(IR) 개최 공시 → 실제 공시일/IR 일시
"""

import datetime
import io
import re
import zipfile

from . import common
from .common import FetchError

CATEGORY = "주식/금융"
FINNHUB_URL = "https://finnhub.io/api/v1/calendar/earnings"
DART_LIST_URL = "https://opendart.fss.or.kr/api/list.json"
DART_DOC_URL = "https://opendart.fss.or.kr/api/document.xml"

PAST_DAYS = 21     # 지난 실적도 이 기간은 결과(EPS)와 함께 유지
AHEAD_DAYS = 120   # 앞으로 이 기간의 발표일 조회

HOUR_TEXT = {
    "bmo": "장 시작 전 (BMO) · 한국시간 당일 밤",
    "amc": "장 마감 후 (AMC) · 한국시간 다음날 새벽",
    "dmh": "장중 발표",
}


def _money(v):
    if v is None:
        return None
    try:
        v = float(v)
    except (TypeError, ValueError):
        return None
    if abs(v) >= 1e9:
        return "$%.2fB" % (v / 1e9)
    if abs(v) >= 1e6:
        return "$%.1fM" % (v / 1e6)
    return "$%.0f" % v


def _surprise(actual, est):
    try:
        a, e = float(actual), float(est)
    except (TypeError, ValueError):
        return None
    if e == 0:
        return None
    pct = (a - e) / abs(e) * 100
    word = "상회" if pct > 0 else ("하회" if pct < 0 else "부합")
    return "%+.1f%% %s" % (pct, word)


def fetch_finnhub(key, stocks, today):
    items = []
    frm = (today - datetime.timedelta(days=PAST_DAYS)).isoformat()
    to = (today + datetime.timedelta(days=AHEAD_DAYS)).isoformat()
    us = [s for s in stocks if s.get("market", "US") == "US"]
    failures = []
    for s in us:
        sym, name = s["ticker"], s.get("name", s["ticker"])
        try:
            data = common.http_get_json(FINNHUB_URL, params={"from": frm, "to": to, "symbol": sym, "token": key})
        except FetchError as e:
            failures.append("%s: %s" % (sym, e))
            print("  [!] Finnhub %s 실패: %s" % (sym, e))
            if "401" in str(e) or "403" in str(e):
                raise  # 키 문제면 나머지도 실패하므로 중단
            continue
        rows = (data or {}).get("earningsCalendar") or []
        if not rows:
            print("  [-] %s(%s): 기간 내 예정된 실적 발표 없음" % (name, sym))
        for r in rows:
            d = common.parse_loose_date(r.get("date"))
            if not d:
                continue
            q, y = r.get("quarter"), r.get("year")
            period = "FY%s Q%s" % (y, q) if q and y else ""
            hour = (r.get("hour") or "").lower()
            eps_est, eps_act = r.get("epsEstimate"), r.get("epsActual")
            rev_est, rev_act = r.get("revenueEstimate"), r.get("revenueActual")

            memo_bits = ["%s %s" % (sym, period or "실적 발표")]
            if eps_est is not None:
                memo_bits.append("EPS 예상 %.2f" % float(eps_est))
            if rev_est:
                memo_bits.append("매출 예상 %s" % _money(rev_est))

            if eps_act is not None:
                surprise = _surprise(eps_act, eps_est)
                detail = "발표 완료 · EPS %.2f%s" % (float(eps_act), " (%s)" % surprise if surprise else "")
                memo_bits.append("EPS 실제 %.2f" % float(eps_act))
                if rev_act:
                    rs = _surprise(rev_act, rev_est)
                    memo_bits.append("매출 실제 %s%s" % (_money(rev_act), " (%s)" % rs if rs else ""))
            else:
                detail = HOUR_TEXT.get(hour, "발표 시간 미정")
                if d < today:
                    detail = "발표 완료 · 결과 집계 중"

            items.append(common.make_item(
                "finnhub", (sym, y or d.year, q or d.month),
                title="%s 실적 발표" % name,
                category=CATEGORY,
                date=d,
                memo=" | ".join(memo_bits),
                link_url="https://finance.yahoo.com/quote/%s/" % sym,
                search_url=common.naver_search_url("%s 실적" % name),
                time_detail=detail,
            ))
            print("  -> %s(%s) %s %s · %s" % (name, sym, d, period, detail))
    if failures and len(failures) == len(us):
        raise FetchError("모든 종목 조회 실패: " + failures[0])
    return items


# ---------------------------------------------------------------------------
# OpenDART (국내)
# ---------------------------------------------------------------------------
_DATE_PATTERNS = [
    re.compile(r"(20\d{2})\s*[-./년]\s*(\d{1,2})\s*[-./월]\s*(\d{1,2})"),
]


def _ir_date_from_document(key, rcept_no, filed):
    """IR 개최 공시 원문에서 실제 개최 일자를 찾는다. 못 찾으면 None."""
    try:
        raw = common.http_get(DART_DOC_URL, params={"crtfc_key": key, "rcept_no": rcept_no}, timeout=20, retries=1)
        with zipfile.ZipFile(io.BytesIO(raw)) as zf:
            text = ""
            for n in zf.namelist():
                b = zf.read(n)
                for enc in ("utf-8", "euc-kr", "cp949"):
                    try:
                        text += b.decode(enc)
                        break
                    except UnicodeDecodeError:
                        continue
    except Exception as e:
        print("    [!] IR 공시 원문 조회 실패 (%s): %s" % (rcept_no, e))
        return None
    text = re.sub(r"<[^>]+>", " ", text)
    # '일시' / '개최일' 근처의 날짜를 우선 사용
    idx = max(text.find("일시"), text.find("개최일"))
    windows = [text[idx: idx + 300]] if idx >= 0 else []
    windows.append(text)
    for w in windows:
        for pat in _DATE_PATTERNS:
            for m in pat.finditer(w):
                try:
                    d = datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
                except ValueError:
                    continue
                if d >= filed:
                    return d
    return None


def fetch_dart(key, stocks, today):
    items = []
    kr = [s for s in stocks if s.get("market") == "KR"]
    bgn = (today - datetime.timedelta(days=89)).strftime("%Y%m%d")
    end = today.strftime("%Y%m%d")
    for s in kr:
        corp = s.get("dartCorpCode")
        name = s.get("name", s["ticker"])
        if not corp:
            print("  [-] %s: config.json에 dartCorpCode가 없어 건너뜀" % name)
            continue
        data = common.http_get_json(DART_LIST_URL, params={
            "crtfc_key": key, "corp_code": corp, "bgn_de": bgn, "end_de": end, "page_count": 100})
        status = (data or {}).get("status")
        if status == "013":  # 조회된 데이터 없음
            continue
        if status != "000":
            raise FetchError("DART 오류 %s: %s" % (status, (data or {}).get("message")))
        code = s["ticker"].split(".")[0]
        for r in data.get("list", []):
            report = r.get("report_nm", "")
            rcept_no = r.get("rcept_no")
            filed = common.parse_loose_date(r.get("rcept_dt"))
            if not filed:
                continue
            link = "https://dart.fss.or.kr/dsaf001/main.do?rcpNo=%s" % rcept_no
            if "잠정" in report and "실적" in report:
                items.append(common.make_item(
                    "dart", (corp, rcept_no),
                    title="%s 잠정실적 공시" % name, category=CATEGORY, date=filed,
                    memo="%s | %s | DART 공시 원문 확인" % (code, report.strip()),
                    link_url=link, search_url=common.naver_search_url("%s 잠정실적" % name),
                    time_detail="공시 완료" if filed < today else "오늘 공시"))
                print("  -> %s 잠정실적 공시 %s" % (name, filed))
            elif "기업설명회" in report:
                ir_date = _ir_date_from_document(key, rcept_no, filed)
                if ir_date and ir_date >= today - datetime.timedelta(days=PAST_DAYS):
                    items.append(common.make_item(
                        "dart", (corp, rcept_no),
                        title="%s 실적 발표 (IR·컨퍼런스콜)" % name, category=CATEGORY, date=ir_date,
                        memo="%s | %s (공시일 %s) | 시간·방식은 공시 원문 확인" % (code, report.strip(), common.fmt_md(filed)),
                        link_url=link, search_url=common.naver_search_url("%s 실적 발표" % name),
                        time_detail="IR 개최"))
                    print("  -> %s IR 개최 %s (공시 %s)" % (name, ir_date, filed))
                elif not ir_date:
                    items.append(common.make_item(
                        "dart", (corp, rcept_no),
                        title="%s IR 개최 공시" % name, category=CATEGORY, date=filed,
                        memo="%s | %s | 개최 일시는 공시 원문 확인" % (code, report.strip()),
                        link_url=link, time_detail="일시 원문 확인"))
    return items
