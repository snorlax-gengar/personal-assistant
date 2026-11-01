#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
telegram_briefing.py — 개인비서 Blanc 모닝 브리핑 (v2)

- 한국 시간 기준 '오늘'로 계산 (GitHub Actions의 UTC 때문에 하루 밀리던 문제 수정)
- 어제·그제 발표된 실적 결과(EPS 서프라이즈) 요약
- 데이터 수집이 실패했거나 키가 없으면 브리핑 하단에 경고 표시
- 비밀키는 환경변수(GitHub Secrets) 또는 .env 에서만 읽음

사용법
  python3 scripts/telegram_briefing.py            # 전송
  python3 scripts/telegram_briefing.py --preview  # 전송하지 않고 미리보기만
"""

import html
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blanc import common  # noqa: E402

EMOJI = {"개인/업무": "💼", "할 일": "✅", "주식/금융": "📈", "부동산": "🏠"}


def esc(s):
    return html.escape(str(s or ""), quote=False)


def link(url, text):
    return '<a href="%s">%s</a>' % (html.escape(url, quote=True), esc(text))


def line_for(item, d_day=None, detailed=False):
    emoji = EMOJI.get(item.get("category"), "📌")
    head = "%s <b>%s</b>" % (emoji, esc(item.get("title")))
    if d_day is not None:
        head += " (D-%d)" % d_day
    if item.get("timeDetail"):
        head += " · " + esc(item["timeDetail"])
    if not detailed:
        return "• " + head
    out = "• " + head
    memo = (item.get("memo") or "").split(" | 공식접수")[0]
    if memo:
        out += "\n   └ " + esc(memo[:180])
    if item.get("linkURL"):
        out += "  " + link(item["linkURL"], "🔗바로가기")
    return out


def build_briefing_message(items, status, today):
    today_str = "%d년 %d월 %d일 (%s)" % (today.year, today.month, today.day, common.weekday_kr(today))
    today_items, urgent, upcoming, results = [], [], [], []

    for it in items:
        d = common.parse_item_date(it.get("date"))
        if not d:
            continue
        diff = (d - today).days
        if it.get("isCompleted"):
            continue
        if diff == 0:
            today_items.append(it)
        elif 1 <= diff <= 3:
            urgent.append((it, diff))
        elif 4 <= diff <= 7:
            upcoming.append((it, diff))
        elif -2 <= diff < 0 and it.get("source") == "finnhub" and "EPS" in (it.get("timeDetail") or ""):
            results.append(it)

    lines = ["✦ <b>개인비서 Blanc 모닝 브리핑</b>", "📅 %s" % today_str, ""]

    if today_items:
        lines.append("🚨 <b>오늘</b> (%d건)" % len(today_items))
        lines += [line_for(it, detailed=True) for it in today_items]
    else:
        lines.append("✨ 오늘 예정된 일정은 없습니다.")
    lines.append("")

    if urgent:
        lines.append("⏳ <b>3일 이내</b> (%d건)" % len(urgent))
        lines += [line_for(it, dd, detailed=True) for it, dd in sorted(urgent, key=lambda x: x[1])]
        lines.append("")

    if upcoming:
        lines.append("📌 <b>이번 주 다가올 일정</b>")
        lines += [line_for(it, dd) for it, dd in sorted(upcoming, key=lambda x: x[1])[:6]]
        if len(upcoming) > 6:
            lines.append("   … 외 %d건" % (len(upcoming) - 6))
        lines.append("")

    if results:
        lines.append("📊 <b>최근 실적 결과</b>")
        for it in results:
            lines.append("• %s — %s" % (esc(it.get("title", "").replace(" 실적 발표", "")), esc(it.get("timeDetail"))))
        lines.append("")

    # 수집 상태 경고
    warn = []
    for name, s in (status.get("sources") or {}).items():
        if s.get("status") == "error":
            last = (s.get("lastSuccess") or "없음")[:10]
            warn.append("⚠️ %s 수집 실패 (마지막 성공 %s)" % (esc(s.get("label", name)), last))
        elif s.get("status") == "not_configured":
            warn.append("➖ %s 미연결 (API 키 필요)" % esc(s.get("label", name)))
    if warn:
        lines.append("━━━━━━━━━━━━━━")
        lines += warn
        lines.append("")

    lines.append("— 개인비서 Blanc")
    return "\n".join(lines)


def send_telegram_message(token, chat_id, text):
    url = "https://api.telegram.org/bot%s/sendMessage" % token
    payload = json.dumps({
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15, context=common._SSL) as res:
            data = json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print("[!] 텔레그램 전송 실패: HTTP %s %s" % (e.code, e.read()[:200]))
        return False
    except Exception as e:
        print("[!] 텔레그램 전송 실패: %s" % e)
        return False
    if data.get("ok"):
        print("[✅] 텔레그램 브리핑 전송 성공!")
        return True
    print("[!] 텔레그램 응답 에러: %s" % data)
    return False


def main():
    items = common.load_json(common.SCHEDULES_PATH, [])
    status = common.load_json(common.STATUS_PATH, {})
    message = build_briefing_message(items, status, common.today_kst())

    print("--- [미리보기] ---")
    print(message)
    print("------------------")

    if "--preview" in sys.argv:
        return

    token = common.get_secret("TELEGRAM_BOT_TOKEN")
    chat_id = common.get_secret("TELEGRAM_CHAT_ID")
    if not token or not chat_id:
        print("[ℹ️] 텔레그램 토큰 또는 Chat ID가 설정되지 않아 미리보기만 출력했습니다.")
        return
    if not send_telegram_message(token, chat_id, message):
        sys.exit(1)


if __name__ == "__main__":
    main()
