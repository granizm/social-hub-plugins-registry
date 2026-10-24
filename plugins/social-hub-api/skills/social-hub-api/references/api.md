# Social Hub API リファレンス (social-hub-rs の /api/v1)

公開 URL: `https://social-hub.granizm.net/api/v1/<path>`。認証は `Authorization: Bearer <API トークン>`。
web の中継がトークンを tokengate で検証し、発行者 (`sub = oidc:<アカウント ID>`) のアカウントに割り当てた social-hub-rs (`:8081`) へ転送する。
仕様の正本は social-hub-rs の `GET /spec/openapi.json` (中継の外。クラスタ内からのみ)。

## profile の選び方 (selector)

`capabilities` 以外の全エンドポイントで、次のどれかが必要 (無いと 400)。

| クエリ | 意味 |
|---|---|
| `profiles=a,b` | profile 名で指定 |
| `provider=line` | platform で指定 |
| `all=true` | 全 profile |

## 応答の形 (envelope)

```json
{"results": [
  {"profile": "test-line", "platform": "line", "status": "ok", "data": { ... }},
  {"profile": "x-main", "platform": "x", "status": "error", "message": "理由"}
]}
```

profile ごとに成功・失敗が分かれる。HTTP は 200 のまま。

`GET /capabilities` だけは envelope ではない:

```json
{"providers": [...], "profiles": [{"profile": "...", "platform": "...", "capabilities": [{"id": "conversations.list", "status": "available|not_supported|...", "reason": null}]}],
 "profile_states": [{"name": "test-line", "platform": "line", "state": "ready"}]}
```

## 読み取り (GET)

| パス | クエリ | data の形 |
|---|---|---|
| `/capabilities` | — | 上記 |
| `/auth/verify` | selector | `true` (ログイン済み) |
| `/users/me` | selector | `{id, display_name, ...}` |
| `/users/{id}` | selector | ユーザー |
| `/users/search` | selector, `query` | ユーザー一覧 |
| `/users/resolve` | selector, `identifier` | ユーザー |
| `/conversations` | selector | `{items: [{id, kind: "dm"|"group", title, participants, extra}]}` (並び順は保証なし・時刻なし) |
| `/conversations/unreplied` | selector, `since_days` (既定 7), `limit` (既定 50) | `{items: [{conversation: {...}, last_inbound_message: {...}}]}` 相手が最後に発言したトークだけ |
| `/conversations/{id}/messages` | selector, `limit`, `scope=conversation_history`, `before_cursor` | `{items: [message]}` |
| `/conversations/{id}/members` | selector | メンバー |
| `/conversations/threads` | selector | スレッド (provider による) |
| `/posts` | selector, `query`, `limit`, `cursor` | 投稿 (`query` ありで検索) |
| `/posts/{id}`, `/users/{id}/posts`, `/bookmarks`, `/posts/drafts` | selector | provider による |

message の形:

```json
{"id": "...", "conversation_id": "...", "direction": "received|sent", "sender": {"id": "...", "display_name": "", "platform": "line"},
 "sent_at": "1792807800272", "text": "...", "media": [], "reactions": [], "extra": {"content_type": 0}}
```

- `sent_at` はミリ秒の UNIX 時刻 (文字列)。JST = +9h
- LINE の `content_type` 0 はテキスト。0 なのに `text` が空なら、暗号化 (Letter Sealing) を復号できていない可能性が高い
- `sender.display_name` は LINE では空のことが多い。相手はトークの `title` で示す

## 書き込み (明示の依頼があるときだけ)

| メソッド・パス | 内容 |
|---|---|
| `POST /conversations/{id}/messages` | 送信 |
| `POST /conversations/{id}/messages/{message_id}/reactions` | リアクション |
| `POST /messages/unsend` | 送信取り消し |
| `POST /posts`, `DELETE /posts/{id}`, `POST/DELETE /posts/drafts…` | 投稿 |
| `PUT/DELETE /bookmarks/{post_id}` | ブックマーク |
| `POST /auth/authorize`, `POST /auth/restore` | SNS へのログイン (端末登録で他のログインが切れることがある。呼ばない) |

## 中継の挙動

- トークンの検証結果は 30 秒キャッシュされる。失効直後の数十秒は通ることがある
- プランが無効なアカウントは 402/403
- アカウントの social-hub-rs が無い・起動中は 502/503/504 (中継が起動を促す。少し待って再試行)
