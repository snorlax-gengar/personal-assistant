#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
generate_ics.py
- data/schedules.json 데이터를 바탕으로 3개의 구독용 iCalendar (.ics) 파일 생성
  1) public/all.ics         (주식 + 부동산 통합)
  2) public/stocks.ics      (주식 실적발표 전용)
  3) public/realestate.ics  (부동산 청약 전용)
- public/index.html 생성 (아이폰에서 원클릭으로 구독할 수 있는 모바일 웹페이지)
"""

import os
import json
import datetime
import urllib.parse

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_PATH = os.path.join(BASE_DIR, "data", "schedules.json")
PUBLIC_DIR = os.path.join(BASE_DIR, "public")

os.makedirs(PUBLIC_DIR, exist_ok=True)


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


def build_ics_content(items, calendar_name):
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//PersonalAssistant//KO",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        f"X-WR-CALNAME:{calendar_name}",
        "X-WR-TIMEZONE:Asia/Seoul"
    ]

    now_stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    for item in items:
        if item.get("isCompleted", False):
            continue

        item_id = item.get("id", str(datetime.datetime.now().timestamp()))
        title = item.get("title", "일정")
        category = item.get("category", "")
        memo = item.get("memo", "")
        link_url = item.get("linkURL", "")
        time_detail = item.get("timeDetail", "")

        date_obj = parse_date(item.get("date"))
        dt_start_str = date_obj.strftime("%Y%m%d")
        dt_end_obj = date_obj + datetime.timedelta(days=1)
        dt_end_str = dt_end_obj.strftime("%Y%m%d")

        # 이모지 접두사
        emoji = "📌"
        if category == "주식/금융":
            emoji = "📈"
        elif category == "부동산":
            emoji = "🏠"
        elif category == "개인/업무":
            emoji = "💼"

        summary = f"[{emoji}] {title}"
        if time_detail:
            summary += f" ({time_detail})"

        desc_parts = []
        if time_detail:
            desc_parts.append(f"시간: {time_detail}")
        if memo:
            desc_parts.append(f"메모: {memo}")
        if link_url:
            desc_parts.append(f"상세정보: {link_url}")
        desc_parts.append("[PersonalAssistant 자동 비서 구독]")
        description = "\\n".join(desc_parts)

        lines.extend([
            "BEGIN:VEVENT",
            f"UID:{item_id}@personalassistant",
            f"DTSTAMP:{now_stamp}",
            f"DTSTART;VALUE=DATE:{dt_start_str}",
            f"DTEND;VALUE=DATE:{dt_end_str}",
            f"SUMMARY:{summary}",
            f"DESCRIPTION:{description}",
        ])

        if link_url:
            lines.append(f"URL:{link_url}")

        # 알림 1: 당일 오전 9시 알람 (한국시간 기준 all-day는 UTC 00시 시작 -> +9시간)
        lines.extend([
            "BEGIN:VALARM",
            "ACTION:DISPLAY",
            f"DESCRIPTION:{title} D-Day입니다!",
            "TRIGGER:PT9H",
            "END:VALARM"
        ])

        # 알림 2: 전날 오전 9시 알람 (하루 전 09:00 -> -15시간)
        lines.extend([
            "BEGIN:VALARM",
            "ACTION:DISPLAY",
            f"DESCRIPTION:내일 {title} 예정일입니다.",
            "TRIGGER:-PT15H",
            "END:VALARM"
        ])

        lines.append("END:VEVENT")

    lines.append("END:VCALENDAR")
    return "\r\n".join(lines)


def generate_landing_html(total_count, stock_count, re_count):
    html = f"""<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>개인 비서 - 아이폰 16 프로 캘린더 자동 구독</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
      background: #0f172a;
      color: #f8fafc;
      margin: 0;
      padding: 24px;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      box-sizing: border-box;
    }}
    .card {{
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 20px;
      padding: 30px 24px;
      max-width: 440px;
      width: 100%;
      box-shadow: 0 10px 30px rgba(0,0,0,0.5);
      text-align: center;
    }}
    .icon {{
      font-size: 46px;
      margin-bottom: 12px;
    }}
    h1 {{
      font-size: 22px;
      font-weight: 700;
      margin: 0 0 8px 0;
    }}
    p.subtitle {{
      color: #94a3b8;
      font-size: 14px;
      line-height: 1.5;
      margin: 0 0 24px 0;
    }}
    .stats {{
      display: flex;
      justify-content: space-around;
      background: #0f172a;
      padding: 14px;
      border-radius: 12px;
      margin-bottom: 24px;
    }}
    .stat-item {{
      text-align: center;
    }}
    .stat-val {{
      font-size: 18px;
      font-weight: 700;
      color: #38bdf8;
    }}
    .stat-label {{
      font-size: 11px;
      color: #64748b;
      margin-top: 2px;
    }}
    .btn {{
      display: block;
      width: 100%;
      padding: 14px 0;
      border-radius: 12px;
      font-size: 15px;
      font-weight: 600;
      text-decoration: none;
      margin-bottom: 12px;
      transition: all 0.2s;
      box-sizing: border-box;
    }}
    .btn-primary {{
      background: #38bdf8;
      color: #0f172a;
    }}
    .btn-secondary {{
      background: #334155;
      color: #f8fafc;
      border: 1px solid #475569;
    }}
    .guide {{
      margin-top: 24px;
      padding-top: 18px;
      border-top: 1px solid #334155;
      font-size: 12px;
      color: #94a3b8;
      text-align: left;
      line-height: 1.6;
    }}
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">🤖</div>
    <h1>Gengarileo 개인 비서 클라우드 캘린더</h1>
    <p class="subtitle">맥북이 꺼져 있어도 365일 24시간<br>아이폰 16 프로 캘린더 및 위젯으로 자동 갱신됩니다.</p>

    <div class="stats">
      <div class="stat-item">
        <div class="stat-val">{stock_count}건</div>
        <div class="stat-label">📈 주식 실발</div>
      </div>
      <div class="stat-item">
        <div class="stat-val">{re_count}건</div>
        <div class="stat-label">🏠 수도권 청약</div>
      </div>
      <div class="stat-item">
        <div class="stat-val">{total_count}건</div>
        <div class="stat-label">전체 일정</div>
      </div>
    </div>

    <!-- 아이폰 Safari에서 클릭 시 캘린더 구독 창 팝업 -->
    <a href="all.ics" class="btn btn-primary" id="allLink">📱 [통합] 캘린더 구독하기</a>
    <a href="stocks.ics" class="btn btn-secondary" id="stockLink">📈 주식 실적발표만 구독</a>
    <a href="realestate.ics" class="btn btn-secondary" id="reLink">🏠 부동산 청약만 구독</a>

    <div class="guide">
      <strong>💡 아이폰에서 구독하는 방법:</strong><br>
      1. 아이폰 Safari에서 위 버튼을 누르면 <strong>"캘린더를 구독하시겠습니까?"</strong> 창이 뜹니다.<br>
      2. <strong>[구독]</strong>을 누르고 자동 새로고침 주기를 <strong>'매시간'</strong>으로 설정하면 끝!<br>
      3. 잠금화면, Always-On 디스플레이, 홈화면 캘린더 위젯에서 확인하실 수 있습니다.
    </div>
  </div>

  <script>
    // iOS Safari에서 webcal 프로토콜로 바로 열기 지원
    const currentHost = window.location.host;
    const currentPath = window.location.pathname.substring(0, window.location.pathname.lastIndexOf('/'));
    const protocol = window.location.protocol === 'https:' ? 'webcal:' : 'webcal:';
    
    document.getElementById('allLink').href = protocol + '//' + currentHost + currentPath + '/all.ics';
    document.getElementById('stockLink').href = protocol + '//' + currentHost + currentPath + '/stocks.ics';
    document.getElementById('reLink').href = protocol + '//' + currentHost + currentPath + '/realestate.ics';
  </script>
</body>
</html>
"""
    return html


def main():
    if not os.path.exists(DATA_PATH):
        print(f"[!] schedules.json이 없습니다: {DATA_PATH}")
        return

    with open(DATA_PATH, "r", encoding="utf-8") as f:
        items = json.load(f)

    stock_items = [i for i in items if i.get("category") == "주식/금융"]
    re_items = [i for i in items if i.get("category") == "부동산"]

    # 1. all.ics 생성
    all_ics = build_ics_content(items, "🤖 [Gengarileo] 주식 & 부동산 통합")
    with open(os.path.join(PUBLIC_DIR, "all.ics"), "w", encoding="utf-8") as f:
        f.write(all_ics)

    # 2. stocks.ics 생성
    stocks_ics = build_ics_content(stock_items, "📈 [Gengarileo] 주식·실적")
    with open(os.path.join(PUBLIC_DIR, "stocks.ics"), "w", encoding="utf-8") as f:
        f.write(stocks_ics)

    # 3. realestate.ics 생성
    re_ics = build_ics_content(re_items, "🏠 [Gengarileo] 부동산·청약")
    with open(os.path.join(PUBLIC_DIR, "realestate.ics"), "w", encoding="utf-8") as f:
        f.write(re_ics)

    # 4. index.html 생성
    html = generate_landing_html(len(items), len(stock_items), len(re_items))
    with open(os.path.join(PUBLIC_DIR, "index.html"), "w", encoding="utf-8") as f:
        f.write(html)

    print(f"[✅] 캘린더 배포 파일 생성 완료 ({PUBLIC_DIR}):")
    print(f"     • all.ics ({len(items)}건)")
    print(f"     • stocks.ics ({len(stock_items)}건)")
    print(f"     • realestate.ics ({len(re_items)}건)")
    print(f"     • index.html (아이폰 원클릭 구독 웹페이지)")


if __name__ == "__main__":
    main()
