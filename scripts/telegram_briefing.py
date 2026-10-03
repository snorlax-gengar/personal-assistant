#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
telegram_briefing.py
- data/schedules.json의 데이터를 바탕으로 오늘의 D-Day 일정 및 임박한 주식 실발/부동산 청약 일정을 브리핑 메시지로 생성
- 텔레그램 Bot API를 통해 모바일로 아침 브리핑 전송
"""

import os
import sys
import json
import datetime
import urllib.request
import urllib.parse
import ssl

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_PATH = os.path.join(BASE_DIR, "data", "schedules.json")
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")

# SSL 설정
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE


def parse_date(date_str):
    if not date_str:
        return datetime.date.today()
    clean_str = date_str.replace("Z", "+00:00")
    try:
        dt = datetime.datetime.fromisoformat(clean_str)
        return dt.date()
    except Exception:
        try:
            return datetime.datetime.strptime(date_str[:10], "%Y-%m-%d").date()
        except Exception:
            return datetime.date.today()


def build_briefing_message(items):
    today = datetime.date.today()
    weekday_kr = ["월", "화", "수", "목", "금", "토", "일"][today.weekday()]
    today_str = f"{today.year}년 {today.month}월 {today.day}일 ({weekday_kr})"

    today_items = []
    urgent_items = []  # D-1 ~ D-3
    upcoming_items = []  # D-4 ~ D-7

    for item in items:
        if item.get("isCompleted", False):
            continue
        item_date = parse_date(item.get("date"))
        d_day = (item_date - today).days

        if d_day == 0:
            today_items.append(item)
        elif 1 <= d_day <= 3:
            urgent_items.append((item, d_day))
        elif 4 <= d_day <= 7:
            upcoming_items.append((item, d_day))

    # 메시지 조합
    lines = [
        "🤖 *[Gengarileo 개인 비서 모닝 브리핑]*",
        f"📅 {today_str}\n"
    ]

    # 1. 오늘 D-Day 일정
    if today_items:
        lines.append(f"🚨 *[오늘의 D-Day 일정]* ({len(today_items)}건)")
        for it in today_items:
            cat = it.get("category", "")
            emoji = "💼" if "개인" in cat else ("📈" if "주식" in cat else "🏠")
            detail = f" ({it.get('timeDetail')})" if it.get("timeDetail") else ""
            memo = f"\n   └ {it.get('memo')}" if it.get("memo") else ""
            lines.append(f"• {emoji} *{it.get('title')}*{detail}{memo}")
        lines.append("")
    else:
        lines.append("✨ *오늘 예정된 D-Day 일정은 없습니다.*\n")

    # 2. 3일 이내 임박 일정
    if urgent_items:
        lines.append(f"⏳ *[3일 이내 임박 일정 (D-3)]* ({len(urgent_items)}건)")
        for it, d_day in urgent_items:
            cat = it.get("category", "")
            emoji = "💼" if "개인" in cat else ("📈" if "주식" in cat else "🏠")
            detail = f" | {it.get('timeDetail')}" if it.get("timeDetail") else ""
            memo = f"\n   └ {it.get('memo')}" if it.get("memo") else ""
            lines.append(f"• {emoji} *{it.get('title')}* (D-{d_day}){detail}{memo}")
        lines.append("")

    # 3. 이번 주 다가올 일정 (D-4 ~ D-7)
    if upcoming_items:
        lines.append(f"📌 *[이번 주 다가올 주요 일정]*")
        for it, d_day in upcoming_items[:4]:  # 최대 4개
            cat = it.get("category", "")
            emoji = "💼" if "개인" in cat else ("📈" if "주식" in cat else "🏠")
            lines.append(f"• {emoji} {it.get('title')} (D-{d_day})")
        lines.append("")

    lines.append("━━━━━━━━━━━━━━━━━")
    lines.append("💡 *오늘도 알차고 멋진 하루 보내세요!* ✨")

    return "\n".join(lines)


def send_telegram_message(token, chat_id, text):
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    payload = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "Markdown"
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=10, context=ssl_context) as res:
            res_data = json.loads(res.read().decode("utf-8"))
            if res_data.get("ok"):
                print("[✅] 텔레그램 브리핑 전송 성공!")
                return True
            else:
                print(f"[!] 텔레그램 응답 에러: {res_data}")
                return False
    except Exception as e:
        print(f"[!] 텔레그램 전송 실패: {e}")
        return False


def main():
    print("=" * 60)
    print("📢 Gengarileo 텔레그램 아침 브리핑 발송 시스템")
    print("=" * 60)

    # 1. 토큰 및 Chat ID 확인
    # 환경변수 우선 -> config.json 차선
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID")

    if not token or not chat_id:
        if os.path.exists(CONFIG_PATH):
            try:
                with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
                    tg_cfg = cfg.get("telegram", {})
                    token = token or tg_cfg.get("botToken")
                    chat_id = chat_id or tg_cfg.get("chatId")
            except Exception:
                pass

    if not os.path.exists(DATA_PATH):
        print(f"[!] 일정이 저장된 파일이 없습니다: {DATA_PATH}")
        sys.exit(1)

    with open(DATA_PATH, "r", encoding="utf-8") as f:
        items = json.load(f)

    # 2. 브리핑 메시지 생성
    message = build_briefing_message(items)
    print("\n--- [미리보기: 전송될 브리핑 메시지] ---")
    print(message)
    print("----------------------------------------\n")

    # 3. 텔레그램 전송
    if not token or not chat_id or token == "YOUR_BOT_TOKEN" or chat_id == "YOUR_CHAT_ID":
        print("[ℹ️] 텔레그램 토큰 또는 Chat ID가 설정되지 않아 화면에 미리보기만 출력되었습니다.")
        print("    텔레그램 봇 토큰과 Chat ID를 설정하시면 매일 아침 모바일로 메시지가 발송됩니다.")
        return

    send_telegram_message(token, chat_id, message)


if __name__ == "__main__":
    main()
