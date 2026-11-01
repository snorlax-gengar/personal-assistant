# ✦ 개인비서 Blanc (Personal Assistant Blanc)

macOS 상단 메뉴바/바탕화면 및 **아이폰 16 프로 캘린더·위젯**과 100% 자동 연동되는 **올인원 프라이빗 비서(Executive Concierge) 서비스**입니다.

맥북이 꺼져 있어도 GitHub Actions 클라우드 서버가 매일 스스로 작동하여 **미국 M7/반도체 실적 발표**와 **수도권 15억 이하 청약(일반분양, 신희타, 공공, 줍줍)** 일정을 자동 수집하고, 아이폰 캘린더 및 텔레그램 모닝 리포트로 전달합니다.

---

## ✨ 핵심 기능

1. **📱 아이폰 16 프로 24시간 자동 연동 (맥북이 꺼져 있어도 동작!)**
   * GitHub Actions 클라우드 스케줄러가 매일 새벽 최신 주식/부동산 일정을 자동 수집
   * WebCal 구독 링크를 통해 아이폰 캘린더, 잠금화면 위젯, AOD(상시표시화면)에 실시간 반영
   * 전날 오전 9시 + 당일 오전 9시 스마트 푸시 알람 울림

2. **📢 텔레그램 모바일 모닝 브리핑**
   * 매일 아침 8시(KST) 비서가 텔레그램으로 오늘 D-Day 일정 및 임박한 핵심 일정을 정중하게 브리핑

3. **🏠 수도권 15억 이하 알짜 청약 엄격 선별**
   * 분양가 15억원 이하의 알짜 분양 단지만 필터링하여 분양가 정보와 함께 자동 제공

4. **⚡ 스마트 자연어 한 줄 등록기 (Fantastical 스타일)**
   * 마우스 클릭 없이 `내일 저녁 7시 치과 예약`, `10/25 엔비디아 실적` 타이핑 후 Enter로 1초 등록

5. **🎨 카테고리별 독립 캘린더 분류**
   * 📈 `[Blanc] 주식·실적` (초록색)
   * 🏠 `[Blanc] 부동산·청약` (주황색)
   * 💼 `[Blanc] 개인·업무` (파란색)
   * ✅ `[Blanc] 할 일` (보라색)

6. **🎞️ 고정 너비 롤링 전광판 (macOS 상단 메뉴바)**
   * 가로 155pt 고정으로 주변 Wi-Fi, 배터리 아이콘 흔들림 전혀 없음
   * 3.5초마다 다가오는 주요 일정이 아래에서 위로 부드럽게 자동 전환

7. **⌨️ 전역 단축키 (`⌥ + Space`)**
   * 어떤 작업을 하고 있든 `Option + Space`를 누르면 Blanc 비서실 대시보드가 즉시 팝업

8. **🔗 실발 시간대(장전/장후) & 원클릭 웹 링크 (`↗`)**
   * 실적 발표 시간대 배지 (`장 마감 후 (AMC)`, `장 시작 전 (BMO)`)
   * 각 일정 우측 화살표 클릭 시 Yahoo Finance, 네이버 증권, 네이버 부동산/청약홈 페이지 즉시 연결

9. **🖥️ 바탕화면 플로팅 글래스모피즘 위젯**
   * 드래그 이동 가능한 반투명 위젯 카드를 화면 원하는 곳에 상시 표시

---

## 🚀 실행 및 빌드 방법

### 1. 앱 실행
바탕화면의 `GengarileoAssistant` 폴더 안의 **`GengarileoAssistant.app`**을 더블 클릭하여 실행할 수 있습니다.

### 2. 코드 수정 후 재컴파일
```bash
cd /Users/declan/Desktop/GengarileoAssistant
./build_app.sh
```

### 3. 아이폰 캘린더 웹 구독 주소
```text
webcal://raw.githubusercontent.com/snorlax-gengar/personal-assistant/main/public/all.ics
```
웹 대시보드: https://snorlax-gengar.github.io/personal-assistant/

---

## 🔧 v2 데이터 엔진 (2026-11)

이전 버전은 수집 API가 실패하면 **코드에 적힌 예시 일정**을 대신 넣었습니다. v2부터는 실제 공고/공시만 사용하고, 실패하면 직전 데이터를 유지하면서 `data/sync_status.json`·텔레그램·웹 대시보드에 실패 사실을 표시합니다.

| 데이터 | 출처 | 비밀키 |
|---|---|---|
| 청약 (일반분양·국민·무순위) | 한국부동산원 청약홈 분양정보 API | `DATA_GO_KR_KEY` |
| LH 공공분양·신혼희망타운 | LH 분양임대공고문 API | `DATA_GO_KR_KEY` |
| 미국 실적 발표 (+EPS 결과) | Finnhub | `FINNHUB_KEY` |
| 삼성전자·SK하이닉스 공시 | OpenDART | `DART_KEY` |
| 모닝 브리핑 | Telegram Bot | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` |

- 비밀키는 **GitHub Secrets**(Actions용)와 로컬 `.env`(`.env.example` 복사)에만 둡니다. `config.json`에 넣지 마세요.
- 키 점검: `python3 scripts/sync_collector.py --check`
- 브리핑 미리보기: `python3 scripts/telegram_briefing.py --preview`
- 맥 앱 ↔ GitHub 동기화: `scripts/mac_sync.sh` (맥 앱이 자동 실행. 수집은 GitHub Actions 전담)
