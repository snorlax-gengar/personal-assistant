#!/bin/bash
# =============================================================================
# mac_sync.sh — 맥 앱 ↔ GitHub 일정 동기화 (개인비서 Blanc)
#
#  1) GitHub 최신 데이터(자동 수집 + 아이폰 단축어 일정)를 받아오고
#  2) 맥 앱에서 바꾼 개인 일정과 3-way 병합한 뒤
#  3) 바뀐 게 있으면 GitHub에 올립니다 → Actions가 아이폰 캘린더(.ics)를 갱신
#
#  API 수집은 GitHub Actions에서만 합니다 (키가 맥에 없어도 동작).
#  종료 코드: 0 성공 · 2 GitHub 연결 실패(로컬 데이터는 그대로) · 3 병합 실패 · 4 pull 충돌
# =============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"

DATA="data/schedules.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ "$BRANCH" != "main" ]; then
  echo "[!] 현재 브랜치가 main이 아니라($BRANCH) 동기화를 건너뜁니다."
  exit 3
fi

echo "[*] GitHub 최신 데이터 확인 중..."
if ! git fetch -q origin main 2>"$TMP/err"; then
  echo "[!] GitHub 연결 실패 (오프라인이거나 SSH 키 문제): $(head -c 300 "$TMP/err")"
  exit 2
fi

git show HEAD:"$DATA"        > "$TMP/base.json"   2>/dev/null || echo "[]" > "$TMP/base.json"
git show origin/main:"$DATA" > "$TMP/remote.json" 2>/dev/null || echo "[]" > "$TMP/remote.json"
cp "$DATA" "$TMP/local.json" 2>/dev/null || echo "[]" > "$TMP/local.json"

python3 scripts/merge_local.py "$TMP/base.json" "$TMP/local.json" "$TMP/remote.json" "$TMP/merged.json" || exit 3

# 데이터 변경분은 merged.json에 담겼으므로 data/, public/ 의 로컬 수정은 되돌리고 최신으로 이동
git checkout -q HEAD -- data public 2>/dev/null
if ! git pull -q --rebase --autostash origin main 2>"$TMP/err"; then
  git rebase --abort 2>/dev/null
  cp "$TMP/merged.json" "$DATA"
  echo "[!] GitHub 최신 코드 받기 실패(충돌): $(head -c 300 "$TMP/err")"
  exit 4
fi

cp "$TMP/merged.json" "$DATA"

if git diff --quiet -- "$DATA"; then
  echo "[✅] 동기화 완료 (변경 없음)"
  exit 0
fi

git add "$DATA"
git commit -q -m "chore(mac): 맥 앱 개인 일정 동기화" -- "$DATA"
for i in 1 2 3; do
  if git push -q origin HEAD:main 2>"$TMP/err"; then
    echo "[✅] 동기화 완료 (맥 변경사항 업로드 → 아이폰 캘린더 곧 반영)"
    exit 0
  fi
  git pull -q --rebase --autostash origin main 2>/dev/null
  sleep 2
done
echo "[!] 업로드 실패 (다음 동기화 때 재시도): $(head -c 300 "$TMP/err")"
exit 2
