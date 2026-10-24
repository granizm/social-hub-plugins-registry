# social-hub-plugins-registry

Social Hub (https://social-hub.granizm.net) を Claude Code から使うための plugin registry。

## Marketplace Installation

```bash
/plugin marketplace add granizm/social-hub-plugins-registry
/plugin install social-hub-api@social-hub-plugins-registry
```

private repo のため、GitHub 認証 (`gh auth login` 等) が必要です。

## Available Plugins

| Plugin | Version | Description |
|--------|---------|-------------|
| [social-hub-api](./plugins/social-hub-api/) | 0.1.0 | API トークンで profile 状態・LINE などの直近メッセージを読む (読み取り専用) |

## 使い方 (social-hub-api)

1. Social Hub の「アカウント」画面で API トークンを発行する
2. `export SOCIAL_HUB_API_TOKEN=<トークン>` (または `SOCIAL_HUB_API_TOKEN_FILE=<パス>`)
3. Claude Code で「Social Hub の API で LINE の直近メッセージを見せて」

## License

MIT
