#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
개인비서 Blanc 자동 수집기 v2 (sync_collector.py)

바뀐 점
- 실제 API에서 받은 데이터만 저장합니다. 실패하면 '가짜 예시 일정'을 만들지 않고,
  직전에 성공한 데이터를 그대로 유지한 뒤 data/sync_status.json에 실패 사유를 남깁니다.
- 같은 공고/실적은 항상 같은 ID → 완료 체크가 유지되고 중복이 생기지 않습니다.
- 지난 일정도 60일간 기록으로 남깁니다 (실적 결과 EPS, 당첨발표 등 사후 확인용).
- 날짜는 모두 한국 시간 기준입니다.

사용법
  python3 scripts/sync_collector.py            # 전체 수집
  python3 scripts/sync_collector.py --check    # 키 설정 여부만 확인
"""

import datetime
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from blanc import common, realestate, stocks  # noqa: E402
from blanc.common import FetchError  # noqa: E402

BACKUPS_DIR = os.path.join(common.DATA_DIR, "backups")
HISTORY_DAYS = 60
MAX_BACKUPS = 30
AUTO_CATEGORIES = ("주식/금융", "부동산")

SECRETS = {
    "DATA_GO_KR_KEY": "공공데이터포털 (청약홈·LH 청약 공고)",
    "FINNHUB_KEY": "Finnhub (미국 실적 발표)",
    "DART_KEY": "OpenDART (국내 실적 공시)",
    "TELEGRAM_BOT_TOKEN": "텔레그램 봇 토큰",
    "TELEGRAM_CHAT_ID": "텔레그램 chat id",
}

# v1 수집기가 만들던 '예시(가짜) 일정'을 알아보는 표시들
_LEGACY_MEMO = re.compile(
    r"(공식접수: (청약홈|LH청약플러스|SH청약)$)|(실적 발표 예정 \(공시 확인\))|(^[A-Z0-9.]+ (FY\d{2} Q\d|Q\d|\d분기|3분기))")


def is_legacy_fake(item):
    if item.get("source"):
        return False
    if item.get("category") not in AUTO_CATEGORIES:
        return False
    memo = item.get("memo", "") or ""
    if "아이폰 단축어" in memo:
        return False
    if " · " in item.get("title", ""):
        return False  # v2 형식 (Swift 앱이 source를 지운 경우)
    if item.get("category") == "부동산" and "공식접수:" in memo:
        return True
    return bool(_LEGACY_MEMO.search(memo.split(" | [")[0].strip()) or item.get("priceWon"))


def source_of(item):
    s = item.get("source")
    if s:
        return s
    return common.SOURCE_MANUAL


def create_backup(items):
    if not items:
        return
    os.makedirs(BACKUPS_DIR, exist_ok=True)
    stamp = common.now_kst().strftime("%Y%m%d_%H%M%S")
    common.save_json(os.path.join(BACKUPS_DIR, "backup_before_sync_%s.json" % stamp), items)
    files = sorted(glob.glob(os.path.join(BACKUPS_DIR, "backup_before_sync_*.json")))
    for old in files[:-MAX_BACKUPS]:
        try:
            os.remove(old)
        except OSError:
            pass


def merge(existing, fetched_by_source, status, today):
    """
    existing: 기존 일정 목록
    fetched_by_source: {source: [items]}  (이번에 '성공'한 출처만 들어있음)
    """
    history_cutoff = today - datetime.timedelta(days=HISTORY_DAYS)
    prev_by_id = {str(i.get("id", "")).upper(): i for i in existing}

    final = []
    dropped_legacy = 0
    for item in existing:
        if is_legacy_fake(item):
            dropped_legacy += 1
            continue
        src = source_of(item)
        if src == common.SOURCE_MANUAL:
            final.append(item)
            continue
        d = common.parse_item_date(item.get("date"))
        if d and d < history_cutoff:
            continue  # 오래된 자동 일정 정리
        if src in fetched_by_source:
            # 이번에 새로 받은 출처: 새 목록에 없는 '지난 일정'만 기록으로 유지
            new_ids = {i["id"] for i in fetched_by_source[src]}
            if str(item.get("id")).upper() not in new_ids and d and d < today:
                final.append(item)
            continue
        final.append(item)  # 실패/미설정 출처 → 직전 데이터 유지

    for src, items in fetched_by_source.items():
        for it in items:
            prev = prev_by_id.get(it["id"])
            if prev:
                it["isCompleted"] = prev.get("isCompleted", False)
                it["createdAt"] = prev.get("createdAt", it["createdAt"])
            final.append(it)

    # 중복 ID 제거 (뒤에 온 것이 최신)
    seen = {}
    for it in final:
        seen[str(it.get("id")).upper()] = it
    final = sorted(seen.values(), key=lambda x: (common.parse_item_date(x.get("date")) or today, x.get("title", "")))
    if dropped_legacy:
        print("[*] 이전 버전이 만든 예시(가짜) 일정 %d건 정리" % dropped_legacy)
    return final


def run_source(name, label, fn, status, fetched):
    try:
        result = fn()
    except FetchError as e:
        status[name] = {"status": "error", "label": label, "message": str(e)[:300]}
        print("  [!] %s 실패 → 직전 데이터 유지: %s" % (label, e))
        return
    except Exception as e:  # 예상 못한 형식 변화 등
        status[name] = {"status": "error", "label": label, "message": "%s: %s" % (type(e).__name__, e)}
        print("  [!] %s 처리 중 오류 → 직전 데이터 유지: %s" % (label, e))
        return
    if isinstance(result, dict):
        fetched.update(result)
        count = sum(len(v) for v in result.values())
    else:
        fetched[name] = result
        count = len(result)
    status[name] = {"status": "ok", "label": label, "count": count}


def check_keys():
    print("비밀키 설정 상태 (환경변수 또는 .env):")
    for k, desc in SECRETS.items():
        print("  %s %-20s %s" % ("✅" if common.get_secret(k) else "❌", k, desc))


def main():
    if "--check" in sys.argv:
        check_keys()
        return

    print("=" * 60)
    print("🚀 개인비서 Blanc 수집기 v2  (%s KST)" % common.now_kst().strftime("%Y-%m-%d %H:%M"))
    print("=" * 60)

    today = common.today_kst()
    config = common.load_config()
    re_cfg = config.get("realEstate", {})
    stock_list = config.get("stocks", [])

    status = {}
    fetched = {}

    data_key = common.get_secret("DATA_GO_KR_KEY")
    finnhub_key = common.get_secret("FINNHUB_KEY")
    dart_key = common.get_secret("DART_KEY")

    # 1. 청약홈 (APT + 무순위)
    print("\n[🏠] 청약홈 분양 공고")
    if data_key:
        try:
            res, errors = realestate.fetch_applyhome(data_key, re_cfg, today)
            for src, items in res.items():
                if src in errors:
                    status[src] = {"status": "error", "label": "청약홈", "message": errors[src][:300]}
                else:
                    fetched[src] = items
                    status[src] = {"status": "ok", "label": "청약홈" + (" 무순위" if "remnant" in src else ""), "count": len(items)}
        except Exception as e:
            status["applyhome"] = {"status": "error", "label": "청약홈", "message": str(e)[:300]}
            print("  [!] 청약홈 실패: %s" % e)
    else:
        status["applyhome"] = {"status": "not_configured", "label": "청약홈", "message": "DATA_GO_KR_KEY 없음"}
        print("  [-] DATA_GO_KR_KEY 미설정 → 건너뜀")

    # 2. LH
    print("\n[🏠] LH 공공분양·신혼희망타운 공고")
    if data_key:
        run_source("lh", "LH청약플러스", lambda: realestate.fetch_lh(data_key, re_cfg, today), status, fetched)
    else:
        status["lh"] = {"status": "not_configured", "label": "LH청약플러스", "message": "DATA_GO_KR_KEY 없음"}
        print("  [-] DATA_GO_KR_KEY 미설정 → 건너뜀")

    # 3. 미국 실적
    print("\n[📈] 미국 실적 발표 (Finnhub)")
    if finnhub_key:
        run_source("finnhub", "미국 실적(Finnhub)", lambda: stocks.fetch_finnhub(finnhub_key, stock_list, today), status, fetched)
    else:
        status["finnhub"] = {"status": "not_configured", "label": "미국 실적(Finnhub)", "message": "FINNHUB_KEY 없음"}
        print("  [-] FINNHUB_KEY 미설정 → 건너뜀")

    # 4. 국내 실적
    print("\n[📈] 국내 실적 공시 (OpenDART)")
    if dart_key:
        run_source("dart", "국내 공시(DART)", lambda: stocks.fetch_dart(dart_key, stock_list, today), status, fetched)
    else:
        status["dart"] = {"status": "not_configured", "label": "국내 공시(DART)", "message": "DART_KEY 없음"}
        print("  [-] DART_KEY 미설정 → 건너뜀")

    # 5. 병합 & 저장
    existing = common.load_json(common.SCHEDULES_PATH, [])
    create_backup(existing)
    final = merge(existing, fetched, status, today)
    common.save_json(common.SCHEDULES_PATH, final)

    prev_status = common.load_json(common.STATUS_PATH, {})
    for name, st in status.items():
        if st["status"] == "ok":
            st["lastSuccess"] = common.now_kst().isoformat(timespec="seconds")
        else:
            st["lastSuccess"] = (prev_status.get("sources", {}).get(name) or {}).get("lastSuccess")
    common.save_json(common.STATUS_PATH, {
        "updatedAt": common.now_kst().isoformat(timespec="seconds"),
        "sources": status,
    })

    print("\n" + "=" * 60)
    print("[✅] 저장 완료: 총 %d건" % len(final))
    for name, st in status.items():
        icon = {"ok": "✅", "error": "⚠️", "not_configured": "➖"}[st["status"]]
        extra = "%d건" % st.get("count", 0) if st["status"] == "ok" else st.get("message", "")
        print("  %s %-22s %s" % (icon, st["label"], extra))


if __name__ == "__main__":
    main()
