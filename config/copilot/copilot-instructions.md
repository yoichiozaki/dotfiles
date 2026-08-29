# User-level Copilot instructions

## ⚠️ 保留中のタスク（次回セッションで必ず先に伝えること）

**管理者権限が必要な開発環境モダン化が残っています（2026-08-29 時点）。**

セッション開始時、ユーザーに以下を必ずリマインドしてください:

> 開発環境モダン化のうち、**管理者権限が必要な分**が保留中です。
> 実行: 管理者 PowerShell で
> `& "$HOME\.copilot\maintenance\modernize-dev-env.ps1"`
> 詳細: `~\.copilot\pending-maintenance.md`
>
> 残: .NET 10 LTS 追加 / OpenJDK 21 追加 / VC++ Redist / Azure Functions Core Tools /
> 旧 Rust MSI 1.79 の残骸削除。
>
> 完了済み: Rust→rustup (rustc 1.98) / Go 1.27 / **PowerShell 7.6.5** / WSL /
> npm 12 / Nushell / devtunnel / Copilot の winget ピン / dotfiles 化 (`~\dotfiles`)

作業が完了したら、このセクションと `pending-maintenance.md`、
`~\.copilot\maintenance\` を削除してください。
