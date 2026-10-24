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

| `login` / `logout` / `where` | トークンを `~/.config/social-hub/credentials` に保存・削除・読んだ場所の表示 |

トークンの探し順: 環境変数 `SOCIAL_HUB_API_TOKEN` → `SOCIAL_HUB_API_TOKEN_FILE` → `./.env` → `~/.config/social-hub/credentials` (`[${SOCIAL_HUB_ACCOUNT:-default}]`、権限 600)。

読み取り専用。送信・既読・リアクション・authorize は呼ばない。
