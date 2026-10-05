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
  <title>개인비서 Blanc - 아이폰 16 프로 캘린더 자동 구독</title>
  <link rel="icon" type="image/png" href="favicon.png">
  <link rel="apple-touch-icon" href="apple-touch-icon.png">
  <meta name="apple-mobile-web-app-title" content="개인비서 Blanc">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="theme-color" content="#1e1b4b">
  <style>
    :root {{
      --primary: #8b5cf6;
      --primary-hover: #7c3aed;
      --accent: #38bdf8;
      --bg: #0b0f19;
      --card-bg: rgba(22, 27, 46, 0.85);
      --card-border: rgba(139, 92, 246, 0.2);
    }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", sans-serif;
      background: radial-gradient(circle at 50% 20%, #1e1b4b 0%, #0b0f19 80%);
      color: #f8fafc;
      margin: 0;
      padding: 24px;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      box-sizing: border-box;
      -webkit-font-smoothing: antialiased;
    }}
    .card {{
      background: var(--card-bg);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border: 1px solid var(--card-border);
      border-radius: 28px;
      padding: 38px 28px 30px;
      max-width: 440px;
      width: 100%;
      box-shadow: 0 20px 50px rgba(0,0,0,0.6), 0 0 40px rgba(124, 58, 237, 0.15);
      text-align: center;
      box-sizing: border-box;
      animation: fadeIn 0.5s ease-out;
    }}
    @keyframes fadeIn {{
      from {{ opacity: 0; transform: translateY(10px); }}
      to {{ opacity: 1; transform: translateY(0); }}
    }}
    .emblem-wrapper {{
      margin-bottom: 20px;
      display: inline-block;
      position: relative;
    }}
    .emblem {{
      width: 92px;
      height: 92px;
      border-radius: 24px;
      box-shadow: 0 16px 36px rgba(124, 58, 237, 0.45), 0 0 24px rgba(56, 189, 248, 0.25);
      border: 1px solid rgba(255, 255, 255, 0.16);
      transition: transform 0.35s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.35s ease;
    }}
    .emblem:hover {{
      transform: scale(1.08) translateY(-2px);
      box-shadow: 0 22px 45px rgba(124, 58, 237, 0.6), 0 0 30px rgba(56, 189, 248, 0.4);
    }}
    .status-badge {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 4px 10px;
      border-radius: 20px;
      background: rgba(16, 185, 129, 0.12);
      border: 1px solid rgba(16, 185, 129, 0.3);
      color: #34d399;
      font-size: 11px;
      font-weight: 600;
      letter-spacing: 0.5px;
      margin-bottom: 12px;
      text-transform: uppercase;
    }}
    .status-dot {{
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: #10b981;
      box-shadow: 0 0 8px #10b981;
      animation: pulse 2s infinite;
    }}
    @keyframes pulse {{
      0%, 100% {{ opacity: 1; transform: scale(1); }}
      50% {{ opacity: 0.5; transform: scale(0.85); }}
    }}
    h1 {{
      font-size: 23px;
      font-weight: 700;
      letter-spacing: -0.5px;
      margin: 0 0 8px 0;
      background: linear-gradient(135deg, #ffffff 40%, #c4b5fd 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }}
    p.subtitle {{
      color: #94a3b8;
      font-size: 13.5px;
      line-height: 1.55;
      margin: 0 0 24px 0;
    }}
    .stats {{
      display: flex;
      justify-content: space-around;
      background: rgba(15, 23, 42, 0.6);
      border: 1px solid rgba(255, 255, 255, 0.06);
      padding: 14px 10px;
      border-radius: 16px;
      margin-bottom: 24px;
    }}
    .stat-item {{
      flex: 1;
      text-align: center;
    }}
    .stat-val {{
      font-size: 19px;
      font-weight: 700;
      color: #38bdf8;
      letter-spacing: -0.5px;
    }}
    .stat-label {{
      font-size: 11px;
      color: #64748b;
      margin-top: 3px;
      font-weight: 500;
    }}
    .btn {{
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      width: 100%;
      padding: 14px 0;
      border-radius: 14px;
      font-size: 14.5px;
      font-weight: 600;
      text-decoration: none;
      margin-bottom: 11px;
      transition: all 0.25s cubic-bezier(0.16, 1, 0.3, 1);
      box-sizing: border-box;
    }}
    .btn-primary {{
      background: linear-gradient(135deg, #7c3aed 0%, #4f46e5 100%);
      color: #ffffff;
      box-shadow: 0 8px 20px rgba(99, 102, 241, 0.35);
    }}
    .btn-primary:hover {{
      transform: translateY(-2px);
      box-shadow: 0 12px 25px rgba(99, 102, 241, 0.5);
    }}
    .btn-secondary {{
      background: rgba(30, 41, 59, 0.7);
      color: #e2e8f0;
      border: 1px solid rgba(255, 255, 255, 0.1);
    }}
    .btn-secondary:hover {{
      background: rgba(51, 65, 85, 0.85);
      border-color: rgba(255, 255, 255, 0.2);
      transform: translateY(-1.5px);
    }}
    .guide {{
      margin-top: 22px;
      padding-top: 18px;
      border-top: 1px solid rgba(255, 255, 255, 0.08);
      font-size: 12px;
      color: #94a3b8;
      text-align: left;
      line-height: 1.6;
    }}
    .guide strong {{
      color: #cbd5e1;
    }}
    .footer-brand {{
      margin-top: 16px;
      font-size: 11px;
      color: #475569;
      letter-spacing: 0.3px;
    }}
  </style>
</head>
<body>
  <div class="card">
    <div class="emblem-wrapper">
      <img src="emblem.jpg" alt="개인비서 Blanc" class="emblem" />
    </div>

    <div>
      <div class="status-badge">
        <span class="status-dot"></span> 24H Concierge Active
      </div>
    </div>

    <h1>개인비서 Blanc</h1>
    <p class="subtitle">VIP 회원을 위한 24시간 실시간 일정 & 자산 브리핑 시스템<br>맥북이 꺼져 있어도 아이폰 AOD와 위젯으로 완벽히 보좌합니다.</p>

    <div class="stats">
      <div class="stat-item">
        <div class="stat-val">{stock_count}건</div>
        <div class="stat-label">📈 M7·반도체 실발</div>
      </div>
      <div class="stat-item">
        <div class="stat-val">{re_count}건</div>
        <div class="stat-label">🏠 청약 (15억 이하)</div>
      </div>
      <div class="stat-item">
        <div class="stat-val">{total_count}건</div>
        <div class="stat-label">✦ 총 보좌 일정</div>
      </div>
    </div>

    <!-- 아이폰 Safari에서 클릭 시 캘린더 구독 창 팝업 -->
    <a href="all.ics" class="btn btn-primary" id="allLink">✦ [통합] 비서실 전체 캘린더 구독하기</a>
    <a href="stocks.ics" class="btn btn-secondary" id="stockLink">📈 주식 실적 발표 전용 구독</a>
    <a href="realestate.ics" class="btn btn-secondary" id="reLink">🏠 수도권 청약 (15억 이하) 구독</a>

    <div class="guide">
      <strong>💡 비서실 안내:</strong><br>
      1. 아이폰 Safari에서 위 버튼을 터치하면 <strong>"캘린더를 구독하시겠습니까?"</strong> 창이 열립니다.<br>
      2. <strong>[구독]</strong>을 탭하고 자동 새로고침 주기를 <strong>'매시간'</strong>으로 설정해 두시면 매일 새벽 최신 정보로 자동 갱신됩니다.<br>
      3. 잠금화면(AOD) 및 홈 화면 캘린더 위젯에서 비서실 일정을 실시간으로 확인하실 수 있습니다.
    </div>

    <div class="footer-brand">
      개인비서 Blanc • Powered by Cloud Pipeline
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

    # 1. all.ics 생성 (로봇 이모지 대신 품격 있는 ✦ 심볼)
    all_ics = build_ics_content(items, "✦ [개인비서 Blanc] 주식 & 부동산 통합")
    with open(os.path.join(PUBLIC_DIR, "all.ics"), "w", encoding="utf-8") as f:
        f.write(all_ics)

    # 2. stocks.ics 생성
    stocks_ics = build_ics_content(stock_items, "📈 [개인비서 Blanc] 주식·실적")
    with open(os.path.join(PUBLIC_DIR, "stocks.ics"), "w", encoding="utf-8") as f:
        f.write(stocks_ics)

    # 3. realestate.ics 생성
    re_ics = build_ics_content(re_items, "🏠 [개인비서 Blanc] 부동산·청약")
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
