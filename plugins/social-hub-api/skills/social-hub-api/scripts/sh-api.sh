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
# 環境変数:
#   SOCIAL_HUB_API_TOKEN       API トークン (必須。SOCIAL_HUB_API_TOKEN_FILE でファイルから読んでもよい)
#   SOCIAL_HUB_API_URL         既定 https://social-hub.granizm.net/api/v1
#   SOCIAL_HUB_PROFILE         対象 profile をカンマ区切りで (未指定なら全 profile)
#
# 🔴 読み取り (GET) だけを行う。送信・既読・リアクション・authorize は呼ばない。
# 🔴 トークンの値は出力しない (長さと先頭 3 文字まで)。
set -euo pipefail

BASE="${SOCIAL_HUB_API_URL:-https://social-hub.granizm.net/api/v1}"
BASE="${BASE%/}"
if [[ -z "${SOCIAL_HUB_API_TOKEN:-}" && -n "${SOCIAL_HUB_API_TOKEN_FILE:-}" ]]; then
  SOCIAL_HUB_API_TOKEN="$(tr -d '\r\n' < "$SOCIAL_HUB_API_TOKEN_FILE")"
fi
TOKEN="${SOCIAL_HUB_API_TOKEN:-}"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "$1 が必要です"; }
need curl; need jq

[[ -n "$TOKEN" ]] || die "SOCIAL_HUB_API_TOKEN (または SOCIAL_HUB_API_TOKEN_FILE) を設定してください。トークンは Social Hub の「アカウント」画面で発行・表示できます"

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
  echo "- URL: $BASE"
  echo "- トークン: 長さ ${#TOKEN} / 先頭 ${TOKEN:0:3}"
  echo; echo "#### profile"; cmd_profiles
  echo; echo "#### ログイン確認"; cmd_verify
  echo; echo "#### アカウント"; cmd_me
  echo; echo "#### トーク件数"
  api /conversations "$(selector)" | jq -r '"| profile | トーク件数 |", "|---|---|", (.results[] | "| \(.profile) | \(if .status == "ok" then (.data.items|length|tostring) else "\(.status): \(.message // "")" end) |")'
}

cmd="${1:-check}"; shift || true
case "$cmd" in
  check) cmd_check ;;
  profiles) cmd_profiles ;;
  verify) cmd_verify ;;
  me) cmd_me ;;
  conversations) cmd_conversations "$@" ;;
  recent) cmd_recent "$@" ;;
  messages) cmd_messages "$@" ;;
  get) [[ $# -ge 1 ]] || die "get <path>"; p="$1"; [[ "$p" == /* ]] || p="/$p"; [[ "$p" == *profiles=* || "$p" == *all=* || "$p" == /capabilities* ]] || p="$p$([[ "$p" == *\?* ]] && echo '&' || echo '?')$(selector)"; api "$p" | jq . ;;
  -h|--help|help) sed -n '2,22p' "$0" ;;
  *) die "不明なコマンド: $cmd (help で一覧)" ;;
esac
