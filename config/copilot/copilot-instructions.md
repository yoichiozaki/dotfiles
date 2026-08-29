# User-level Copilot instructions

## 環境メモ

- Windows の設定は **`~\dotfiles`** で Git 管理されています（シンボリックリンク方式）。
  `~/.gitconfig`、PowerShell プロファイル、`~/.copilot/settings.json` などは
  すべてこのリポジトリへのリンクなので、**いつもの場所を編集すればリポジトリが更新されます**。
  変更したら `~\dotfiles` でコミットしてください。

- ツールチェーンの更新は **管理者 PowerShell** で:
  `& "$HOME\dotfiles\scripts\modernize-dev-env.ps1"`（冪等）

- **`GitHub.Copilot` を winget で更新しないでください。** CLI は自己更新するため
  winget では**ダウングレード**になります。更新は `copilot /update`。
  （winget には blocking pin を設定済み）

- 既知の注意点（pyenv-win の更新機能故障 → uv 移行推奨、Hugo/FFmpeg の winget
  相関バグ、PowerShell モジュールが OneDrive 配下にあるリスク）は
  `~\dotfiles\README.md` に記載しています。
