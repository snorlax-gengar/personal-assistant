# -*- coding: utf-8 -*-
"""
개인비서 Blanc 공통 유틸리티
- 한국 시간(KST) 기준 날짜 계산 (GitHub Actions 서버는 UTC라서 반드시 이걸 써야 함)
- 비밀키 로딩 (환경변수 → .env 파일 순서, config.json에는 절대 저장하지 않음)
- SSL 검증이 켜진 HTTP 요청
- 일정 아이템 생성/날짜 파싱 (Swift 앱과 호환되는 형식)

Python 3.9 이상 호환 (macOS 기본 python3 포함)
"""

import datetime
import json
import os
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_DIR = os.path.join(BASE_DIR, "data")
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
SCHEDULES_PATH = os.path.join(DATA_DIR, "schedules.json")
STATUS_PATH = os.path.join(DATA_DIR, "sync_status.json")
ENV_PATH = os.path.join(BASE_DIR, ".env")

KST = datetime.timezone(datetime.timedelta(hours=9), "KST")
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) BlancAssistant/2.0"

# 자동 수집 일정의 출처 표시. 이 값이 없는 일정은 사용자가 직접 넣은 일정으로 취급한다.
SOURCE_MANUAL = "manual"
AUTO_SOURCES = ("applyhome", "applyhome_remnant", "lh", "finnhub", "dart")

# 고정 ID 생성용 네임스페이스 (같은 공고/실적은 매번 같은 ID → 완료 체크 등이 유지됨)
_ID_NAMESPACE = uuid.UUID("6f1c3b52-0d1e-4c55-9a8e-8b1a2c4d5e6f")


# ---------------------------------------------------------------------------
# 날짜/시간
# ---------------------------------------------------------------------------
def now_kst():
    return datetime.datetime.now(KST)


def today_kst():
    return now_kst().date()


def iso_utc_now():
    """Swift ISO8601DateFormatter가 확실히 읽을 수 있는 형식 (소수점 초 없음)."""
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def date_to_item_iso(d):
    """
    날짜(date)를 저장용 문자열로 변환.
    한국 시간 정오(12:00 KST = 03:00Z)로 저장해서 어떤 시간대에서 읽어도 날짜가 밀리지 않게 한다.
    """
    return "%04d-%02d-%02dT03:00:00Z" % (d.year, d.month, d.day)


def parse_item_date(date_str):
    """일정의 date 문자열 → 한국 시간 기준 date. 실패하면 None."""
    if not date_str:
        return None
    s = str(date_str).strip()
    try:
        dt = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=KST)
        return dt.astimezone(KST).date()
    except ValueError:
        pass
    return parse_loose_date(s)


def parse_loose_date(value):
    """'2026-11-03', '20261103', '2026.11.03', '2026/11/03' 등을 date로. 실패하면 None."""
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    digits = "".join(ch for ch in s[:10] if ch.isdigit())
    if len(digits) >= 8:
        try:
            return datetime.date(int(digits[0:4]), int(digits[4:6]), int(digits[6:8]))
        except ValueError:
            return None
    return None


def weekday_kr(d):
    return ["월", "화", "수", "목", "금", "토", "일"][d.weekday()]


def fmt_md(d):
    return "%d/%d(%s)" % (d.month, d.day, weekday_kr(d))


# ---------------------------------------------------------------------------
# 설정 & 비밀키
# ---------------------------------------------------------------------------
def load_config():
    if not os.path.exists(CONFIG_PATH):
        return {}
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


_env_cache = None


def _load_dotenv():
    global _env_cache
    if _env_cache is not None:
        return _env_cache
    values = {}
    if os.path.exists(ENV_PATH):
        with open(ENV_PATH, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                values[k.strip()] = v.strip().strip('"').strip("'")
    _env_cache = values
    return values


def get_secret(name):
    """환경변수(GitHub Secrets) 우선, 없으면 로컬 .env. 비어 있으면 None."""
    val = os.environ.get(name) or _load_dotenv().get(name)
    if val and not val.startswith("여기에") and val.upper() not in ("", "YOUR_KEY", "CHANGE_ME"):
        return val
    return None


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------
def _ssl_context():
    try:
        import certifi  # 있으면 사용 (macOS python.org 설치본 인증서 문제 대응)
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        return ssl.create_default_context()


_SSL = _ssl_context()


class FetchError(Exception):
    pass


def http_get(url, params=None, headers=None, timeout=15, retries=2, raw_query=None):
    """
    GET 요청. params는 일반 dict, raw_query는 이미 인코딩된 쿼리 문자열(공공데이터 serviceKey 등).
    실패 시 FetchError (상태 코드와 응답 앞부분 포함).
    """
    query = urllib.parse.urlencode(params or {}, doseq=True)
    if raw_query:
        query = (query + "&" if query else "") + raw_query
    full = url + ("?" + query if query else "")
    hdrs = {"User-Agent": USER_AGENT, "Accept": "application/json, */*"}
    hdrs.update(headers or {})
    last_err = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(full, headers=hdrs)
            with urllib.request.urlopen(req, timeout=timeout, context=_SSL) as res:
                return res.read()
        except urllib.error.HTTPError as e:
            body = ""
            try:
                body = e.read()[:300].decode("utf-8", "replace")
            except Exception:
                pass
            last_err = FetchError("HTTP %s: %s" % (e.code, body.strip()))
            if e.code in (400, 401, 403, 404):
                break  # 재시도해도 소용없는 오류
        except Exception as e:  # 타임아웃, 연결 오류 등
            last_err = FetchError("%s: %s" % (type(e).__name__, e))
        if attempt < retries:
            time.sleep(1.5 * (attempt + 1))
    raise last_err


def http_get_json(url, params=None, headers=None, timeout=15, retries=2, raw_query=None):
    raw = http_get(url, params=params, headers=headers, timeout=timeout, retries=retries, raw_query=raw_query)
    text = raw.decode("utf-8", "replace").strip()
    try:
        return json.loads(text)
    except ValueError:
        # 공공데이터포털은 키 오류일 때 XML을 돌려준다
        if "SERVICE_KEY" in text or "SERVICE KEY" in text or "returnAuthMsg" in text:
            raise FetchError("API 키 오류 (등록되지 않았거나 아직 활성화 전): " + text[:200])
        raise FetchError("JSON이 아닌 응답: " + text[:200])


def data_go_kr_key_query(key):
    """
    공공데이터포털 키는 'Encoding'(이미 %로 인코딩)과 'Decoding'(원문) 두 가지가 있다.
    어느 쪽을 넣어도 동작하도록 원문으로 되돌린 뒤 한 번만 인코딩한다.
    """
    decoded = urllib.parse.unquote(key)
    return "serviceKey=" + urllib.parse.quote(decoded, safe="")


# ---------------------------------------------------------------------------
# 일정 아이템
# ---------------------------------------------------------------------------
def stable_id(*parts):
    """출처+고유번호로 항상 같은 UUID를 만든다 (Swift 앱이 대문자로 저장하므로 대문자)."""
    key = "|".join(str(p) for p in parts)
    return str(uuid.uuid5(_ID_NAMESPACE, key)).upper()


def make_item(source, key_parts, title, category, date, memo="", link_url=None,
              search_url=None, time_detail=None, price_won=None, is_completed=False):
    item = {
        "id": stable_id(source, *key_parts),
        "title": title,
        "category": category,
        "date": date_to_item_iso(date),
        "isCompleted": bool(is_completed),
        "isDDay": True,
        "memo": memo or "",
        "source": source,
        "createdAt": iso_utc_now(),
    }
    if link_url:
        item["linkURL"] = link_url
    if search_url:
        item["searchURL"] = search_url
    if time_detail:
        item["timeDetail"] = time_detail
    if price_won:
        item["priceWon"] = int(price_won)
    return item


def naver_search_url(query):
    return "https://search.naver.com/search.naver?query=" + urllib.parse.quote_plus(query)


def format_eok(won):
    """원 → '8.7억' / '12억'"""
    if not won:
        return ""
    eok = won / 100_000_000
    if abs(eok - round(eok)) < 0.05:
        return "%d억" % round(eok)
    return "%.1f억" % eok


def load_json(path, default):
    if not os.path.exists(path):
        return default
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print("[!] %s 읽기 실패: %s" % (path, e))
        return default


def save_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, path)
