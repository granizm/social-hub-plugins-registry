---
name: social-hub-api
description: |
  Social Hub (https://social-hub.granizm.net) の API を API トークンで読み、接続済み SNS (LINE など) の profile 状態・ログイン確認・自分のアカウント・トーク一覧・直近に受け取ったメッセージ・特定トークのメッセージを表にまとめる skill。
  「Social Hub の API で〜」「social-hub のトークンで LINE の直近メッセージを取って」「登録されている profile を確認して」「LINE のトーク一覧」「social-hub-rs の API で確認」「API トークンが使えるか確かめて」「最近来たメッセージを見せて」と言われたら必ず使う。SOCIAL_HUB_API_TOKEN が話題に出たときも使う。
  読み取り専用。送信・既読・リアクション・authorize はユーザーが明示的に頼み、内容を確認したときだけ。
---

# social-hub-api

Social Hub の公開 API を、ユーザーが画面で発行した **API トークン**で叩いて、接続済み SNS の状態とメッセージを読む。

```
API トークン ─▶ https://social-hub.granizm.net/api/v1/*   (web の中継: トークンを検証 → 発行者のアカウントを特定)
                   └▶ そのアカウント専用の social-hub-rs ─▶ LINE / X / Discord …
```

トークンの発行者 (ログインした本人) のアカウントだけが見える。別アカウントは別トークン。

## 準備 (トークンの置き場所)

一度 `login` すれば、以後は設定不要。

```bash
<この skill のディレクトリ>/scripts/sh-api.sh login     # トークンを貼り付け (表示されない) → 使えるか確かめてから保存
```

保存先は `${XDG_CONFIG_HOME:-~/.config}/social-hub/credentials` (INI、権限 600。緩いと読まない)。

```ini
[default]
token = <API トークン>
# url = https://social-hub.granizm.net/api/v1   (別環境のときだけ)

[work]            # 別アカウント。SOCIAL_HUB_ACCOUNT=work で使う / login --account work で保存
token = ...
```

トークンは次の順で探す (先に見つかったものを使う)。`where` でどこから読んだかを確かめられる (値は出ない)。

| 順 | 置き場所 | 向いている場面 |
|---|---|---|
| 1 | 環境変数 `SOCIAL_HUB_API_TOKEN` | 一時的に別トークンで試す |
| 2 | 環境変数 `SOCIAL_HUB_API_TOKEN_FILE` (トークンだけのファイル) | CI・secret のマウント |
| 3 | カレントディレクトリの `.env` の `SOCIAL_HUB_API_TOKEN=` (読むだけ。実行しない) | repo ごとに変える。`.gitignore` 済みか確認すること |
| 4 | `~/.config/social-hub/credentials` の `[${SOCIAL_HUB_ACCOUNT:-default}]` | 普段使い (推奨) |

URL も同じ順 (`SOCIAL_HUB_API_URL` / `.env` / credentials の `url`)。既定は `https://social-hub.granizm.net/api/v1`。`SOCIAL_HUB_PROFILE` で対象 profile を絞れる (未指定なら全 profile)。

トークンが見つからないときは、ユーザーに「Social Hub の /account で API トークンを発行・表示し、ターミナルで `sh-api.sh login` を実行して貼り付けてください」と頼む (トークンをチャットに貼らせない)。**トークンの値を自分で探し回らない** (サーバの DB や秘密情報ストアから取り出さない)。

## 使い方

同梱の CLI を使う (`curl` と `jq` が必要)。パスはこの SKILL.md と同じディレクトリの `scripts/sh-api.sh`。

```bash
S=<この skill のディレクトリ>/scripts/sh-api.sh
$S check                      # 最初に必ず: URL・トークン長・profile 状態・verify・表示名・トーク件数
$S recent 10                  # 直近に受け取ったメッセージ 10 件 (新しい順・JST)
$S messages "<トーク名|ID>" 10 # 1 つのトークの直近メッセージ
$S conversations 20           # トーク件数と先頭 20 件
$S get '/users/search?query=foo'  # その他の GET (JSON)
```

「直近のメッセージ」と言われたら `recent`、特定の相手なら `messages`。`recent` は **相手が最後に発言したトークだけ** を返す (自分が最後に送ったトークは出ない) ので、その旨を添える。

## 報告の形 (必ずこの項目を出す)

1. **経路**: 使った URL とトークンの長さ・先頭 3 文字・読んだ場所 (値は出さない)
2. **profile 表**: profile / platform / 状態 (`ready` など) / verify の結果 / 表示名
3. **件数**: profile ごとのトーク一覧の件数 (`check` の「トーク件数」。省略しない)
4. **メッセージ表**: 日時 (JST) / 種類 (1対1・グループ) / 相手 / 本文 (長文は 60 文字で切る)
5. **注記**: 本文が空の件数とその意味 (下記)、`recent` の範囲、エラーがあればその理由
6. **やっていないこと**: 送信・既読・リアクション・authorize をしていないこと

CLI の出力 (Markdown 表) はそのまま使ってよい。日時は JST、新しい順。

## 結果の読み方

| 見えたもの | 意味 | 伝え方 |
|---|---|---|
| `(本文なし)` (テキスト種別なのに空) | LINE の暗号化 (Letter Sealing) メッセージが復号できていない可能性が高い。グループや公式アカウントは読めることがある | 件数を数えて「本文が取れなかった」と書く。推測で本文を補わない |
| profile の状態が `ready` 以外 (`login_required` / `pending` など) | SNS へのログインがまだ。Social Hub の「接続」画面で設定し直す | authorize を勝手に呼ばない |
| 401 | トークンが無効・失効・期限切れ。失効直後は最大 30 秒キャッシュで通ることがある | 新しいトークンの発行を案内 |
| 402 / 403 | プランが無効、またはこのトークンでは使えない | プランの状態確認を案内 |
| 502 / 503 / 504 | アカウントの AI エージェント (social-hub-rs) が起動中・停止中 | 少し待って再実行 |
| profile ごとに `status: error` | その SNS だけ失敗。`message` に理由 | 理由をそのまま表に書く |

API の詳細 (エンドポイント・クエリ・応答の形) は [references/api.md](references/api.md)。

## 🔴 守ること

- **読み取りだけ。** `POST` / `PUT` / `PATCH` / `DELETE` (送信・既読・リアクション・投稿・削除・authorize・restore) は、ユーザーが明示的に頼み、宛先と本文を確認してからにする。`check` などの確認作業で呼ばない
- トークンの値を表示・ファイル保存・コミットしない。示すのは長さと先頭 3 文字まで
- メッセージ本文はユーザー本人のもの。依頼された範囲 (件数・相手) だけ出す
- 取得できなかったものを推測で埋めない
