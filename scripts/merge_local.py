#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
merge_local.py — 맥 앱 데이터와 GitHub 데이터의 3-way 병합

  python3 merge_local.py BASE LOCAL REMOTE OUT

BASE   : 마지막으로 맞춰졌던 버전 (git HEAD)
LOCAL  : 맥 앱이 지금 가진 버전 (개인 일정 추가/삭제/완료 체크)
REMOTE : GitHub 최신 버전 (자동 수집 + 아이폰 단축어로 추가한 일정)

규칙
- 자동 수집 일정(source가 있는 것)은 GitHub 쪽이 기준. 단, 맥에서 '완료' 체크한 것은 유지.
- 개인 일정은 맥에서 바꾼 쪽이 우선. 한쪽에서 지운 일정은 지운 상태로.
- 양쪽에서 새로 생긴 일정은 모두 유지.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blanc import common  # noqa: E402


def by_id(items):
    out = {}
    for it in items or []:
        if isinstance(it, dict) and it.get("id"):
            it["id"] = str(it["id"]).upper()
            out[it["id"]] = it
    return out


def is_auto(it):
    return (it or {}).get("source") in common.AUTO_SOURCES


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    base = by_id(common.load_json(sys.argv[1], []))
    local = by_id(common.load_json(sys.argv[2], []))
    remote = by_id(common.load_json(sys.argv[3], []))

    merged = []
    stats = {"local_new": 0, "remote_new": 0, "local_deleted": 0, "local_changed": 0}
    for _id in set(base) | set(local) | set(remote):
        b, l, r = base.get(_id), local.get(_id), remote.get(_id)
        if l and r:
            if is_auto(r) or is_auto(l):
                item = dict(r)
                if b is not None and l.get("isCompleted") != b.get("isCompleted"):
                    item["isCompleted"] = l.get("isCompleted")
            elif b is not None and l != b:
                item = l
                stats["local_changed"] += 1
            else:
                item = r
            merged.append(item)
        elif l and not r:
            if b is None:
                merged.append(l)  # 맥에서 새로 추가
                stats["local_new"] += 1
            # else: GitHub 쪽에서 삭제(만료된 자동 일정 등) → 제외
        elif r and not l:
            if b is None:
                merged.append(r)  # GitHub/아이폰에서 새로 추가
                stats["remote_new"] += 1
            else:
                stats["local_deleted"] += 1  # 맥에서 삭제 → 제외

    today = common.today_kst()
    merged.sort(key=lambda x: ((common.parse_item_date(x.get("date")) or today).isoformat(), x.get("title", "")))
    common.save_json(sys.argv[4], merged)
    print("[merge] 총 %d건 | 맥 신규 %d · 맥 수정 %d · 맥 삭제 %d · GitHub 신규 %d" % (
        len(merged), stats["local_new"], stats["local_changed"], stats["local_deleted"], stats["remote_new"]))


if __name__ == "__main__":
    main()
