# -*- coding: utf-8 -*-
"""
부동산 청약 수집기 (실제 공고 데이터만 사용, 추정/예시 데이터 없음)

1) 한국부동산원 청약홈 분양정보 조회 서비스 (공공데이터포털, odcloud)
   - APT 분양정보 상세 (일반분양/국민주택)  getAPTLttotPblancDetail
   - APT 주택형별 분양가                     getAPTLttotPblancMdl
   - 무순위/잔여세대 상세                    getRemndrLttotPblancDetail
   - 무순위/잔여세대 주택형별 분양가          getRemndrLttotPblancMdl
2) 한국토지주택공사(LH) 분양임대공고문 조회 서비스
   - 공공분양(05), 신혼희망타운(39)

필요한 비밀키: DATA_GO_KR_KEY (공공데이터포털 일반 인증키, 하나로 두 서비스 모두 사용)
"""

import datetime

from . import common
from .common import FetchError

APPLYHOME_BASE = "https://api.odcloud.kr/api/ApplyhomeInfoDetailSvc/v1/"
LH_URL = "https://apis.data.go.kr/B552555/lhLeaseNoticeInfo1/lhLeaseNoticeInfo1"

CATEGORY = "부동산"
LOOKBACK_DAYS = 75   # 이 기간 안에 공고된 단지를 조회 (공고 → 접수까지 보통 2~3주)
KEEP_PAST_DAYS = 14  # 일정이 이만큼 지난 단지는 건너뜀

APPLYHOME_PORTAL = "https://www.applyhome.co.kr/ai/aia/selectAPTLttotPblancListView.do"
LH_PORTAL = "https://apply.lh.or.kr/lhapply/apply/wt/wrtanc/selectWrtancList.do?mi=1026"


def _g(row, *keys):
    """여러 후보 키 중 처음으로 값이 있는 것을 반환 (API 필드명 변경 대비)."""
    for k in keys:
        v = row.get(k)
        if v not in (None, "", " "):
            return v
    return None


def _matches_region(text, regions, max_tokens=None):
    """
    단어 '시작' 기준으로 비교 (예: '강동' → '강동구' O, '장성동' X / '양주' → '양주시' O, '남양주시' X).
    주소는 앞 3단어(시·도 / 시·군·구 / 구)만 본다.
    """
    if not regions:
        return True
    tokens = (text or "").replace("(", " ").replace(")", " ").split()
    if max_tokens:
        tokens = tokens[:max_tokens]
    return any(t.startswith(r) for t in tokens for r in regions)


def _odcloud_all(endpoint, key, conds, per_page=500, max_pages=10):
    rows = []
    for page in range(1, max_pages + 1):
        params = {"page": page, "perPage": per_page}
        params.update(conds)
        data = common.http_get_json(APPLYHOME_BASE + endpoint, params=params,
                                    raw_query=common.data_go_kr_key_query(key))
        if isinstance(data, dict) and data.get("code") and data.get("code") < 0:
            raise FetchError("청약홈 API 오류 %s: %s" % (data.get("code"), data.get("msg")))
        chunk = (data or {}).get("data") or []
        rows.extend(chunk)
        total = (data or {}).get("matchCount") or (data or {}).get("totalCount") or 0
        if len(chunk) < per_page or len(rows) >= total:
            break
    return rows


def _model_prices(endpoint, key, house_manage_no):
    """주택형별 최고분양가(만원) 목록 → 원 단위 리스트."""
    try:
        rows = _odcloud_all(endpoint, key, {"cond[HOUSE_MANAGE_NO::EQ]": house_manage_no}, per_page=100, max_pages=2)
    except FetchError as e:
        print("    [!] 분양가 조회 실패 (%s): %s" % (house_manage_no, e))
        return None
    prices = []
    for r in rows:
        amt = _g(r, "LTTOT_TOP_AMOUNT", "SUPLY_AMOUNT")
        try:
            v = int(str(amt).replace(",", "").strip())
            if v > 0:
                prices.append(v * 10_000)  # 만원 → 원
        except (TypeError, ValueError):
            continue
    return prices


def _price_text(prices):
    if not prices:
        return None
    lo, hi = common.format_eok(min(prices)), common.format_eok(max(prices))
    return lo if lo == hi else "%s~%s" % (lo, hi)


def _classify_main(row):
    secd = (_g(row, "HOUSE_SECD_NM") or "") + (_g(row, "HOUSE_NM") or "")
    if "신혼희망" in secd:
        return "신혼희망타운"
    if (_g(row, "HOUSE_DTL_SECD_NM") or "") == "국민":
        return "공공분양"
    return "일반분양"


def _range_text(a, b):
    if a and b and a != b:
        return "%s~%s" % (common.fmt_md(a), common.fmt_md(b))
    return common.fmt_md(a or b)


def _build_notice_items(source, row, sub_type, prices, max_price, milestones, today, remnant=False):
    name = (_g(row, "HOUSE_NM") or "이름 없는 단지").strip()
    manage_no = _g(row, "HOUSE_MANAGE_NO") or name
    pblanc_no = _g(row, "PBLANC_NO") or ""
    addr = _g(row, "HSSPLY_ADRES") or ""
    total_units = _g(row, "TOT_SUPLY_HSHLDCO")
    link = _g(row, "PBLANC_URL", "HMPG_ADRES") or APPLYHOME_PORTAL
    d = common.parse_loose_date

    if remnant:
        sched = [
            ("특별공급", d(_g(row, "SPSPLY_RCEPT_BGNDE")), d(_g(row, "SPSPLY_RCEPT_ENDDE")), "특별공급 접수"),
            ("1순위", d(_g(row, "SUBSCRPT_RCEPT_BGNDE", "GNRL_RCEPT_BGNDE")),
             d(_g(row, "SUBSCRPT_RCEPT_ENDDE", "GNRL_RCEPT_ENDDE")), "청약 접수"),
        ]
    else:
        sched = [
            ("특별공급", d(_g(row, "SPSPLY_RCEPT_BGNDE")), d(_g(row, "SPSPLY_RCEPT_ENDDE")), "특별공급 접수"),
            ("1순위", d(_g(row, "GNRL_RNK1_CRSPAREA_RCPTDE", "RCEPT_BGNDE")),
             d(_g(row, "GNRL_RNK1_CRSPAREA_ENDDE", "GNRL_RNK1_CRSPAREA_RCPTDE")), "1순위 접수"),
            ("2순위", d(_g(row, "GNRL_RNK2_CRSPAREA_RCPTDE")), d(_g(row, "GNRL_RNK2_CRSPAREA_ENDDE")), "2순위 접수"),
        ]
    sched.append(("당첨발표", d(_g(row, "PRZWNER_PRESNATN_DE")), None, "당첨자 발표"))
    sched.append(("계약", d(_g(row, "CNTRCT_CNCLS_BGNDE")), d(_g(row, "CNTRCT_CNCLS_ENDDE")), "계약"))

    # 전체 진행표 (메모에 표시)
    timeline = " → ".join("%s %s" % (lbl, _range_text(a, b)) for lbl, a, b, _ in sched if a)

    price_text = _price_text(prices)
    tags = []
    if _g(row, "SPECLT_RDN_EARTH_AT") == "Y":
        tags.append("투기과열")
    if _g(row, "PARCPRC_ULS_AT") == "Y":
        tags.append("분양가상한제")
    memo_parts = [addr]
    if total_units:
        memo_parts.append("총 %s세대" % total_units)
    memo_parts.append("분양가 %s" % price_text if price_text else "분양가: 공고문 확인")
    if tags:
        memo_parts.append("·".join(tags))
    if timeline:
        memo_parts.append(timeline)
    memo_parts.append("공식접수: 청약홈")
    memo = " | ".join(p for p in memo_parts if p)

    items = []
    for label, start, end, title_suffix in sched:
        if label not in milestones or not start:
            continue
        if (end or start) < today - datetime.timedelta(days=KEEP_PAST_DAYS):
            continue
        detail_bits = []
        if end and end != start:
            detail_bits.append("~%s" % common.fmt_md(end))
        if price_text:
            detail_bits.append("분양가 %s" % price_text)
        items.append(common.make_item(
            source, (manage_no, pblanc_no, label),
            title="[%s] %s · %s" % (sub_type, name, title_suffix),
            category=CATEGORY,
            date=start,
            memo=memo,
            link_url=link,
            search_url=common.naver_search_url("%s 청약" % name),
            time_detail=" · ".join(detail_bits) or None,
            price_won=min(prices) if prices else None,
        ))
    return items


def _relevant(row, today, remnant=False):
    """일정 중 하나라도 '최근 2주 이후'인 공고만."""
    keys = ["PRZWNER_PRESNATN_DE", "CNTRCT_CNCLS_ENDDE", "SPSPLY_RCEPT_ENDDE",
            "GNRL_RNK1_CRSPAREA_ENDDE", "RCEPT_ENDDE", "SUBSCRPT_RCEPT_ENDDE", "GNRL_RCEPT_ENDDE"]
    cutoff = today - datetime.timedelta(days=KEEP_PAST_DAYS)
    for k in keys:
        dt = common.parse_loose_date(row.get(k))
        if dt and dt >= cutoff:
            return True
    return False


def fetch_applyhome(key, cfg, today):
    """청약홈 일반 APT + 무순위/잔여세대."""
    regions = cfg.get("regions", [])
    types = set(cfg.get("types", []))
    max_price = cfg.get("maxPriceWon") or 0
    milestones = set(cfg.get("milestones", ["특별공급", "1순위", "당첨발표"]))
    since = (today - datetime.timedelta(days=LOOKBACK_DAYS)).isoformat()

    results = {"applyhome": [], "applyhome_remnant": []}
    jobs = [
        ("applyhome", "getAPTLttotPblancDetail", "getAPTLttotPblancMdl", False),
        ("applyhome_remnant", "getRemndrLttotPblancDetail", "getRemndrLttotPblancMdl", True),
    ]
    errors = {}
    for source, ep_detail, ep_model, remnant in jobs:
        if remnant and "무순위" not in types:
            continue
        try:
            rows = _odcloud_all(ep_detail, key, {"cond[RCRIT_PBLANC_DE::GTE]": since})
        except FetchError as e:
            errors[source] = str(e)
            print("  [!] 청약홈(%s) 조회 실패: %s" % (source, e))
            continue
        print("  [*] 청약홈 %s: 최근 공고 %d건 조회" % ("무순위" if remnant else "APT", len(rows)))
        for row in rows:
            addr = row.get("HSSPLY_ADRES") or ""
            if addr:
                in_region = _matches_region(addr, regions, max_tokens=3)
            else:
                in_region = _matches_region(row.get("HOUSE_NM"), regions)
            if not in_region:
                continue
            if not _relevant(row, today, remnant):
                continue
            sub_type = "무순위" if remnant else _classify_main(row)
            if types and sub_type not in types and not (sub_type == "공공분양" and "공공주택" in types):
                continue
            prices = _model_prices(ep_model, key, row.get("HOUSE_MANAGE_NO"))
            if max_price and prices and min(prices) > max_price:
                print("    [X] %s 제외: 최저 분양가 %s > 상한" % (row.get("HOUSE_NM"), common.format_eok(min(prices))))
                continue
            new = _build_notice_items(source, row, sub_type, prices, max_price, milestones, today, remnant)
            if new:
                print("    [+] %s (%s, %s) 일정 %d개" % (row.get("HOUSE_NM"), sub_type, _price_text(prices) or "분양가 미확인", len(new)))
            results[source].extend(new)
    return results, errors


def _find_ds_list(obj):
    if isinstance(obj, dict):
        if "dsList" in obj and isinstance(obj["dsList"], list):
            return obj["dsList"]
        for v in obj.values():
            r = _find_ds_list(v)
            if r is not None:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = _find_ds_list(v)
            if r is not None:
                return r
    return None


def fetch_lh(key, cfg, today):
    """LH 공공분양(05) / 신혼희망타운(39) 공고."""
    regions = cfg.get("regions", [])
    types = set(cfg.get("types", []))
    region_codes = cfg.get("lhRegionCodes", ["11", "41"])  # 11 서울, 41 경기, 28 인천
    type_codes = []
    if not types or "공공분양" in types or "공공주택" in types:
        type_codes.append(("05", "공공분양"))
    if not types or "신혼희망타운" in types:
        type_codes.append(("39", "신혼희망타운"))

    st = (today - datetime.timedelta(days=LOOKBACK_DAYS)).strftime("%Y%m%d")
    ed = (today + datetime.timedelta(days=1)).strftime("%Y%m%d")
    items = []
    seen = set()
    for code, sub_type in type_codes:
        for cnp in region_codes:
            params = {"PG_SZ": 100, "PAGE": 1, "UPP_AIS_TP_CD": code, "CNP_CD": cnp,
                      "PAN_ST_DT": st, "PAN_ED_DT": ed}
            data = common.http_get_json(LH_URL, params=params, raw_query=common.data_go_kr_key_query(key))
            rows = _find_ds_list(data) or []
            for r in rows:
                pan_id = r.get("PAN_ID") or r.get("PAN_NM")
                if pan_id in seen:
                    continue
                seen.add(pan_id)
                name = (r.get("PAN_NM") or "").strip()
                if not _matches_region(name + " " + (r.get("CNP_CD_NM") or ""), regions):
                    continue
                notice_d = common.parse_loose_date(r.get("PAN_NT_ST_DT"))
                close_d = common.parse_loose_date(r.get("CLSG_DT"))
                if not close_d or close_d < today - datetime.timedelta(days=KEEP_PAST_DAYS):
                    continue
                status = r.get("PAN_SS") or ""
                memo = " | ".join(filter(None, [
                    r.get("CNP_CD_NM"),
                    r.get("AIS_TP_CD_NM"),
                    "공고 %s" % common.fmt_md(notice_d) if notice_d else None,
                    "마감 %s" % common.fmt_md(close_d),
                    "상태: %s" % status if status else None,
                    "분양가·세부 접수일정은 공고문 확인",
                    "공식접수: LH청약플러스",
                ]))
                items.append(common.make_item(
                    "lh", (pan_id, "close"),
                    title="[%s] %s · 접수 마감" % (sub_type, name),
                    category=CATEGORY,
                    date=close_d,
                    memo=memo,
                    link_url=r.get("DTL_URL") or LH_PORTAL,
                    search_url=common.naver_search_url(name),
                    time_detail=status or None,
                ))
                print("    [+] LH %s (%s) 마감 %s" % (name, sub_type, close_d))
    return items
