# User-level Copilot instructions

## ⚠️ 保留中のタスク（次回セッションで必ず先に伝えること）

**管理者権限が必要な開発環境モダン化が残っています（2026-08-29 時点）。**

セッション開始時、ユーザーに以下を必ずリマインドしてください:

> 開発環境モダン化のうち、**管理者権限が必要な分**が保留中です。
> 実行: 管理者 PowerShell で
> `& "$HOME\.copilot\maintenance\modernize-dev-env.ps1"`
> 詳細: `~\.copilot\pending-maintenance.md`
>
> 残: Rust の rustup 移行 / .NET 10 LTS 追加 / OpenJDK 21 追加 / winget 開発系 10 件 / npm 本体。
> （非昇格でできる分は 2026-08-29 に完了済み）

作業が完了したら、このセクションと `pending-maintenance.md`、
`~\.copilot\maintenance\` を削除してください。
