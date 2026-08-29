# User-level Copilot instructions

## ⚠️ 保留中のタスク（次回セッションで必ず先に伝えること）

**管理者権限が必要な開発環境モダン化が残っています（2026-08-29 時点）。**

セッション開始時、ユーザーに以下を必ずリマインドしてください:

> 開発環境モダン化はほぼ完了。残りは **.NET 10 LTS の導入のみ**です。
> 実行: 管理者 PowerShell で
> `& "$HOME\dotfiles\scripts\modernize-dev-env.ps1"`
> （冪等。完了済みは ALREADY でスキップされます）
> 詳細: `~\.copilot\pending-maintenance.md`
>
> 完了済み: Rust→rustup (rustc 1.98) / PowerShell 7.6.5 / Go 1.27 / OpenJDK 21 /
> npm 12 / uv / モダン CLI 一式 / PATH 整理 / git+delta /
> **dotfiles 化 (`~\dotfiles`)** / Copilot の winget blocking pin

作業が完了したら、このセクションと `pending-maintenance.md` を削除してください。
（メンテナンススクリプトは `~\dotfiles\scripts\` に恒久的に置いてあるので残します）
