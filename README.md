# 🤖 GengarileoAssistant (겐가릴레오 개인 비서)

macOS 메뉴바/바탕화면 및 **아이폰 16 프로 캘린더·위젯**과 100% 자동 연동되는 **올인원 개인 비서 서비스**입니다.

맥북이 꺼져 있어도 GitHub Actions 클라우드 서버가 매일 새벽 스스로 작동하여 **미국 M7/반도체 실적 발표**와 **수도권 청약(일반분양, 신희타, 공공, 줍줍)** 일정을 수집하고, 아이폰 캘린더로 전달합니다.

---

## ✨ 핵심 기능

1. **📱 아이폰 16 프로 24시간 자동 연동 (맥북이 꺼져 있어도 동작!)**
   * GitHub Actions 클라우드 스케줄러가 매일 새벽 5시 최신 주식/부동산 일정을 자동 수집
   * WebCal 구독 링크를 통해 아이폰 캘린더, 잠금화면 위젯, AOD(상시표시화면)에 실시간 반영
   * 전날 오전 9시 + 당일 오전 9시 스마트 푸시 알람 울림

2. **🎨 카테고리별 독립 캘린더 분류**
   * 📈 `[Gengarileo] 주식·실적` (초록색)
   * 🏠 `[Gengarileo] 부동산·청약` (주황색)
   * 💼 `[Gengarileo] 개인·업무` (파란색)
   * ✅ `[Gengarileo] 할 일` (보라색)

3. **🎞️ 고정 너비 롤링 전광판 (macOS 상단 메뉴바)**
   * 가로 155pt 고정으로 주변 Wi-Fi, 배터리 아이콘 흔들림 전혀 없음
   * 3.5초마다 다가오는 주요 일정이 아래에서 위로 부드럽게 자동 전환

4. **⌨️ 전역 단축키 (`⌥ + Space`)**
   * 어떤 창을 쓰고 있든 `Option + Space`를 누르면 Gengarileo 대시보드가 즉시 팝업

5. **🔗 실발 시간대(장전/장후) & 원클릭 상세 웹 링크 (`↗`)**
   * 실적 발표 시간대 배지 (`장 마감 후 (AMC)`, `장 시작 전 (BMO)`)
   * 각 일정 우측 화살표 클릭 시 Yahoo Finance, 네이버 증권, 네이버 부동산/청약홈 페이지 즉시 연결

6. **☀️ 출근 시간 아침 9시 모닝 브리핑 시스템 알림**
   * 매일 아침 9시 맥북 우측 상단에 오늘 놓치면 안 되는 D-Day 요약 알림 배너 팝업

7. **🖥️ 바탕화면 플로팅 글래스모피즘 위젯**
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

### 3. GitHub 원격 저장소 연결 (아이폰 클라우드 동기화용)
```bash
cd /Users/declan/Desktop/GengarileoAssistant
git remote add origin https://github.com/본인GitHub아이디/GengarileoAssistant.git
git push -u origin main
```
