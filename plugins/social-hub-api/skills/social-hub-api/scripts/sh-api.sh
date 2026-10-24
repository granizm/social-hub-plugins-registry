#!/usr/bin/env bash
# Social Hub API (https://social-hub.granizm.net/api/v1) を API トークンで読む CLI。
# 中継: web (トークン検証 → 発行者のアカウント) → そのアカウントの social-hub-rs → 各 SNS。
#
# 使い方: sh-api.sh <command> [args]
#   check                         疎通・トークン・profile・verify・表示名・トーク件数をまとめて確認 (最初にこれ)
#   profiles                      profile ごとの状態と、使える機能
#   verify                        profile ごとのログイン確認 (auth/verify)
#   me                            profile ごとの自分のアカウント (users/me)
#   conversations [N]             トーク一覧の件数と先頭 N 件 (既定 10)
#   recent [N] [since_days]       直近に「受け取った」メッセージ N 件 (既定 10 件 / 7 日)。新しい順・JST
#   messages <title|id> [N]       1 つのトークの直近メッセージ N 件 (既定 10)。title は recent / conversations から解決
#   get <path?query>              任意の GET (例: get '/users/search?query=foo')。JSON をそのまま出す
#
#   login [--account NAME] [--url URL]   トークンを標準入力から受け取り ~/.config/social-hub/credentials に保存 (権限 600)
#   logout [--account NAME]              保存したトークンを消す
#   where                         どの設定先からトークンを読んだかを表示 (値は出さない)
#
# トークンの探し順 (先に見つかったものを使う):
#   1. 環境変数 SOCIAL_HUB_API_TOKEN
#   2. 環境変数 SOCIAL_HUB_API_TOKEN_FILE (トークンだけを書いたファイル)
#   3. カレントディレクトリの .env の SOCIAL_HUB_API_TOKEN= 行 (読むだけ。source しない)
#   4. ${XDG_CONFIG_HOME:-~/.config}/social-hub/credentials の [${SOCIAL_HUB_ACCOUNT:-default}] の token=
#      (権限が 600 より緩いと読まない)
# URL も同じ順で SOCIAL_HUB_API_URL / .env / credentials の url= を見る。既定 https://social-hub.granizm.net/api/v1
# その他: SOCIAL_HUB_PROFILE 対象 profile をカンマ区切りで (未指定なら全 profile)
#         SOCIAL_HUB_ACCOUNT credentials のセクション名 (既定 default)
#
# 🔴 読み取り (GET) だけを行う。送信・既読・リアクション・authorize は呼ばない。
# 🔴 トークンの値は出力しない (長さと先頭 3 文字まで)。
set -euo pipefail

DEFAULT_URL="https://social-hub.granizm.net/api/v1"
CRED_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/social-hub/credentials"
ACCOUNT="${SOCIAL_HUB_ACCOUNT:-default}"
TOKEN=""; BASE=""; TOKEN_SRC=""; URL_SRC=""

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "$1 が必要です"; }
need curl; need jq

# .env から KEY= の値を 1 つ読む (クォートを外す)。ファイルは実行しない
dotenv_get() {
  [[ -f .env ]] || return 0
  sed -n -E "s/^[[:space:]]*(export[[:space:]]+)?$1[[:space:]]*=[[:space:]]*//p" .env | tail -1 | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/; s/[[:space:]]+$//'
}

# credentials の [section] から key の値を読む
cred_get() {
  [[ -f "$CRED_FILE" ]] || return 0
  awk -v sec="$ACCOUNT" -v key="$1" '
    /^[[:space:]]*[#;]/ { next }
    /^[[:space:]]*\[/ { gsub(/^[[:space:]]*\[|\][[:space:]]*$/, ""); cur = $0; next }
    cur == sec { i = index($0, "="); if (i) { k = substr($0, 1, i-1); v = substr($0, i+1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", k); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); if (k == key) { print v; exit } } }
  ' "$CRED_FILE"
}

cred_perm_ok() {
  local mode; mode="$(stat -c '%a' "$CRED_FILE" 2>/dev/null || stat -f '%Lp' "$CRED_FILE")"
  [[ "$mode" =~ ^[0-7]?[0-7]00$ ]]
}

load_creds() {
  local v
  if [[ -n "${SOCIAL_HUB_API_TOKEN:-}" ]]; then TOKEN="$SOCIAL_HUB_API_TOKEN"; TOKEN_SRC="環境変数 SOCIAL_HUB_API_TOKEN"
  elif [[ -n "${SOCIAL_HUB_API_TOKEN_FILE:-}" ]]; then
    [[ -r "$SOCIAL_HUB_API_TOKEN_FILE" ]] || die "SOCIAL_HUB_API_TOKEN_FILE を読めません: $SOCIAL_HUB_API_TOKEN_FILE"
    TOKEN="$(tr -d '\r\n' < "$SOCIAL_HUB_API_TOKEN_FILE")"; TOKEN_SRC="ファイル $SOCIAL_HUB_API_TOKEN_FILE"
  elif v="$(dotenv_get SOCIAL_HUB_API_TOKEN)" && [[ -n "$v" ]]; then TOKEN="$v"; TOKEN_SRC="$(pwd)/.env"
  elif [[ -f "$CRED_FILE" ]]; then
    cred_perm_ok || die "$CRED_FILE の権限が緩すぎます (他人が読める)。chmod 600 '$CRED_FILE' してください"
    v="$(cred_get token)"; [[ -n "$v" ]] && { TOKEN="$v"; TOKEN_SRC="$CRED_FILE [$ACCOUNT]"; }
  fi
  [[ -n "$TOKEN" ]] || die "API トークンが見つかりません。Social Hub の「アカウント」画面でトークンを発行・表示し、
  sh-api.sh login   (貼り付けると $CRED_FILE に保存。以後は設定不要)
で保存してください。一時的に使うだけなら export SOCIAL_HUB_API_TOKEN=... でもよい"

  if [[ -n "${SOCIAL_HUB_API_URL:-}" ]]; then BASE="$SOCIAL_HUB_API_URL"; URL_SRC="環境変数"
  elif v="$(dotenv_get SOCIAL_HUB_API_URL)" && [[ -n "$v" ]]; then BASE="$v"; URL_SRC=".env"
  elif [[ -f "$CRED_FILE" ]] && v="$(cred_get url)" && [[ -n "$v" ]]; then BASE="$v"; URL_SRC="credentials [$ACCOUNT]"
  else BASE="$DEFAULT_URL"; URL_SRC="既定値"; fi
  BASE="${BASE%/}"
}

# credentials の 1 セクションを書き換える (他のセクションは残す)
cred_write() {  # cred_write <token|""> <url|""> ; token が空ならセクションごと消す
  local tok="$1" url="$2" dir tmp
  dir="$(dirname "$CRED_FILE")"; umask 077; mkdir -p "$dir"; chmod 700 "$dir"
  tmp="$(mktemp "$dir/.credentials.XXXXXX")"
  if [[ -f "$CRED_FILE" ]]; then
    awk -v sec="$ACCOUNT" '/^[[:space:]]*\[/ { s = $0; gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", s); skip = (s == sec) } !skip' "$CRED_FILE" > "$tmp"
  else
    printf '# Social Hub API の認証情報 (sh-api.sh login が書く)。権限 600 のまま保つこと\n' > "$tmp"
  fi
  if [[ -n "$tok" ]]; then
    { printf '\n[%s]\n' "$ACCOUNT"; printf 'token = %s\n' "$tok"; [[ -n "$url" ]] && printf 'url = %s\n' "$url"; } >> "$tmp"
  fi
  chmod 600 "$tmp"; mv "$tmp" "$CRED_FILE"
}

cmd_login() {
  local url="" tok
  while [[ $# -gt 0 ]]; do case "$1" in
    --account) ACCOUNT="$2"; shift 2 ;;
    --url) url="${2%/}"; shift 2 ;;
    *) die "login [--account NAME] [--url URL]" ;;
  esac; done
  if [[ -t 0 ]]; then printf 'API トークンを貼り付けて Enter (表示されません): ' >&2; IFS= read -rs tok; echo >&2
  else IFS= read -r tok || true; fi
  tok="$(printf '%s' "$tok" | tr -d '\r\n[:space:]')"
  [[ -n "$tok" ]] || die "トークンが空です"
  # 保存前に使えるか確かめる
  local code; code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 -H "authorization: Bearer $tok" "${url:-$DEFAULT_URL}/capabilities")" || die "接続できません"
  [[ "$code" == 2?? ]] || die "このトークンは使えません (HTTP $code)。保存していません"
  cred_write "$tok" "$url"
  echo "保存しました: $CRED_FILE [$ACCOUNT] (トークン 長さ ${#tok} / 先頭 ${tok:0:3}、権限 600)"
}

cmd_logout() {
  [[ "${1:-}" == "--account" ]] && ACCOUNT="$2"
  [[ -f "$CRED_FILE" ]] || { echo "保存されたトークンはありません"; return; }
  cred_write "" ""; echo "削除しました: $CRED_FILE [$ACCOUNT]"
}

selector() {
  if [[ -n "${SOCIAL_HUB_PROFILE:-}" ]]; then printf 'profiles=%s' "$(jq -rn --arg v "$SOCIAL_HUB_PROFILE" '$v|@uri')"; else printf 'all=true'; fi
}

# GET <path> [query] → 本文を stdout。HTTP エラーは理由つきで終了
api() {
  local path="$1" q="${2:-}" url out code body
  url="$BASE$path"
  [[ -n "$q" ]] && url="$url$([[ "$path" == *\?* ]] && echo '&' || echo '?')$q"
  out="$(curl -sS --max-time 60 -w '\n%{http_code}' -H "authorization: Bearer $TOKEN" -H 'accept: application/json' "$url")" || die "接続できません: $url"
  code="${out##*$'\n'}"; body="${out%$'\n'*}"
  case "$code" in
    2??) printf '%s' "$body" ;;
    401) die "401: トークンが無効・失効済み・期限切れ (GET $path)" ;;
    402|403) die "$code: プランが無効か、このトークンでは使えません (GET $path): $(printf '%s' "$body" | head -c 200)" ;;
    *) die "$code (GET $path): $(printf '%s' "$body" | head -c 300)" ;;
  esac
}

# envelope {"results":[{profile,platform,status,message?,data}]} を profile ごとに扱う jq 定義
JQ_DEFS='
def jst: (tostring|tonumber) as $t | (if $t > 100000000000 then $t/1000 else $t end) + 32400 | strftime("%Y-%m-%d %H:%M");
def short($n): (. // "") | gsub("[\r\n\t]+"; " ") | if length > $n then .[0:$n] + "…" else . end;
def body: if (.text // "") == "" then (if ((.media // [])|length) > 0 then "(添付 \((.media|length)) 件)" else "(本文なし)" end) else (.text|short(60)) end;
'

cmd_profiles() {
  api /capabilities | jq -r "$JQ_DEFS"'
    "| profile | platform | 状態 | 使える機能 |", "|---|---|---|---|",
    ( . as $c | .profile_states[] | . as $s
      | ($c.profiles[]? | select(.profile == $s.name) | [.capabilities[] | select(.status == "available") | .id]) as $av
      | "| \($s.name) | \($s.platform) | \($s.state) | \(($av // []) | length) 件: \(($av // []) | map(select(test("^(conversations|users|posts|auth)\\."))) | join(", ") | short(160)) |" )'
}

cmd_verify() {
  api /auth/verify "$(selector)" | jq -r '"| profile | platform | 結果 |", "|---|---|---|",
    (.results[] | "| \(.profile) | \(.platform) | \(if .status == "ok" then (if .data == true then "ok (ログイン済み)" else "ok: \(.data|tostring)" end) else "\(.status): \(.message // "")" end) |")'
}

cmd_me() {
  api /users/me "$(selector)" | jq -r '"| profile | 表示名 | ID (先頭 8 文字) | 結果 |", "|---|---|---|---|",
    (.results[] | "| \(.profile) | \(.data.display_name // .data.displayName // .data.name // "-") | \((.data.id // "-")|tostring|.[0:8]) | \(.status)\(if .message then ": " + .message else "" end) |")'
}

cmd_conversations() {
  local n="${1:-10}"
  api /conversations "$(selector)" | jq -r --argjson n "$n" "$JQ_DEFS"'
    .results[] | "### \(.profile) (\(.platform)): \(if .status == "ok" then "トーク \(.data.items|length) 件" else "\(.status): \(.message // "")" end)",
    ( select(.status == "ok") | "| 種類 | 名前 | ID |", "|---|---|---|",
      (.data.items[:$n][] | "| \(.kind) | \(.title // "-" | short(40)) | \(.id) |") )'
}

cmd_recent() {
  local n="${1:-10}" days="${2:-7}"
  api /conversations/unreplied "$(selector)&since_days=$days&limit=$n" | jq -r --argjson n "$n" "$JQ_DEFS"'
    .results[] | "### \(.profile) (\(.platform)): \(if .status == "ok" then "直近に受け取ったメッセージ \(.data.items|length) 件 (相手が最後に発言したトークのみ)" else "\(.status): \(.message // "")" end)",
    ( select(.status == "ok") | "| 日時 (JST) | 種類 | 相手 | 本文 |", "|---|---|---|---|",
      (.data.items | sort_by(.last_inbound_message.sent_at|tostring|tonumber) | reverse | .[:$n][]
        | "| \(.last_inbound_message.sent_at|jst) | \(if .conversation.kind == "dm" then "1対1" elif .conversation.kind == "group" then "グループ" else .conversation.kind end) | \(.conversation.title // "-" | short(30)) | \(.last_inbound_message|body) |") )'
}

# title または id → conversation id (最初に一致した profile のもの)
resolve_conv() {
  local key="$1" id
  if [[ "$key" =~ ^[A-Za-z0-9_:-]{16,}$ ]]; then echo "$key"; return; fi
  id="$(api /conversations/unreplied "$(selector)&since_days=30&limit=100" | jq -r --arg k "$key" '[.results[] | select(.status=="ok") | .data.items[] | select(.conversation.title == $k) | .conversation.id][0] // empty')"
  [[ -z "$id" ]] && id="$(api /conversations "$(selector)" | jq -r --arg k "$key" '[.results[] | select(.status=="ok") | .data.items[] | select(.title == $k)][0].id // empty')"
  [[ -z "$id" ]] && id="$(api /conversations "$(selector)" | jq -r --arg k "$key" '[.results[] | select(.status=="ok") | .data.items[] | select((.title // "") | contains($k))][0].id // empty')"
  [[ -n "$id" ]] || die "トーク「$key」が見つかりません (conversations で名前を確認してください)"
  echo "$id"
}

cmd_messages() {
  [[ $# -ge 1 ]] || die "messages <title|id> [N]"
  local id n="${2:-10}"; id="$(resolve_conv "$1")"
  api "/conversations/$(jq -rn --arg v "$id" '$v|@uri')/messages" "$(selector)&limit=$n" | jq -r --argjson n "$n" "$JQ_DEFS"'
    .results[] | "### \(.profile) (\(.platform)): \(if .status == "ok" then "メッセージ \(.data.items|length) 件" else "\(.status): \(.message // "")" end)",
    ( select(.status == "ok") | "| 日時 (JST) | 向き | 送信者 | 本文 |", "|---|---|---|---|",
      (.data.items | sort_by(.sent_at|tostring|tonumber) | reverse | .[:$n][]
        | "| \(.sent_at|jst) | \(if .direction == "received" then "受信" elif .direction == "sent" then "送信" else (.direction // "-") end) | \(.sender.display_name // "" | if . == "" then "-" else short(20) end) | \(body) |") )'
}

cmd_check() {
  echo "- URL: $BASE ($URL_SRC)"
  echo "- トークン: 長さ ${#TOKEN} / 先頭 ${TOKEN:0:3} (読んだ場所: $TOKEN_SRC)"
  echo; echo "#### profile"; cmd_profiles
  echo; echo "#### ログイン確認"; cmd_verify
  echo; echo "#### アカウント"; cmd_me
  echo; echo "#### トーク件数"
  api /conversations "$(selector)" | jq -r '"| profile | トーク件数 |", "|---|---|", (.results[] | "| \(.profile) | \(if .status == "ok" then (.data.items|length|tostring) else "\(.status): \(.message // "")" end) |")'
}

cmd="${1:-check}"; shift || true
case "$cmd" in
  login) cmd_login "$@"; exit ;;
  logout) cmd_logout "$@"; exit ;;
  -h|--help|help) sed -n '2,36p' "$0"; exit ;;
esac
load_creds
case "$cmd" in
  where) echo "- トークン: 長さ ${#TOKEN} / 先頭 ${TOKEN:0:3} (読んだ場所: $TOKEN_SRC)"; echo "- URL: $BASE ($URL_SRC)" ;;
  check) cmd_check ;;
  profiles) cmd_profiles ;;
  verify) cmd_verify ;;
  me) cmd_me ;;
  conversations) cmd_conversations "$@" ;;
  recent) cmd_recent "$@" ;;
  messages) cmd_messages "$@" ;;
  get) [[ $# -ge 1 ]] || die "get <path>"; p="$1"; [[ "$p" == /* ]] || p="/$p"; [[ "$p" == *profiles=* || "$p" == *all=* || "$p" == /capabilities* ]] || p="$p$([[ "$p" == *\?* ]] && echo '&' || echo '?')$(selector)"; api "$p" | jq . ;;
  *) die "不明なコマンド: $cmd (help で一覧)" ;;
esac
