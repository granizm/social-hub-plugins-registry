# Repository Guide

This repository hosts Claude Code plugins distributed via the
`social-hub-plugins-registry` marketplace. Each plugin lives under
`plugins/<plugin-name>/` and follows the standard Claude Code plugin layout.

## Plugins

- **social-hub-api** (`plugins/social-hub-api/`) — Social Hub の公開 API (`/api/v1`、social-hub-rs への中継) を
  API トークンで読み、profile 状態・LINE などの直近メッセージを表にまとめる skill。読み取り専用。

## Plugin Version Management

When modifying any file under `plugins/<plugin-name>/`, you **must** bump the
`version` field in `.claude-plugin/plugin.json` before committing.

Claude Code caches plugins by version. Without a bump, changes will not be
picked up by users who already have the plugin installed.

- Use semver: patch for fixes, minor for new features, major for breaking changes.

## Secrets

API トークンの値をこの repo (コード・例・テスト・コミット) に書かない。
