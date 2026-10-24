# social-hub-api

Social Hub (https://social-hub.granizm.net) の公開 API (`/api/v1`) を API トークンで読む skill。

```
API トークン ─▶ /api/v1/* (web の中継: トークン検証 → 発行者のアカウント) ─▶ social-hub-rs ─▶ LINE など
```

| コマンド (`skills/social-hub-api/scripts/sh-api.sh`) | 内容 |
|---|---|
| `check` | URL・トークン長・profile 状態・verify・表示名・トーク件数 |
| `recent [N] [days]` | 直近に受け取ったメッセージ (JST・新しい順) |
| `messages <名前|ID> [N]` | 1 つのトークのメッセージ |
| `conversations [N]` | トーク件数と一覧 |
| `get <path>` | 任意の GET |

環境変数: `SOCIAL_HUB_API_TOKEN` (または `SOCIAL_HUB_API_TOKEN_FILE`)、`SOCIAL_HUB_API_URL`、`SOCIAL_HUB_PROFILE`。

読み取り専用。送信・既読・リアクション・authorize は呼ばない。
