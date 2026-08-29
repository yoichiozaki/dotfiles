# dotfiles

Windows 開発環境の設定一式。**シンボリックリンク方式**なので、
いつもの場所でファイルを編集すればそのままリポジトリが更新され、
`git status` で「どこが素の状態から変わったか」が一目でわかります。

```powershell
git clone <this-repo> ~/dotfiles
cd ~/dotfiles
.\install.ps1 -WhatIfOnly   # 何が起きるか確認
.\install.ps1               # 実行
```

新しいマシンではツールの復元もできます:

```powershell
.\packages\restore.ps1      # 管理者 PowerShell 推奨
```

---

## 構成

```
dotfiles/
├── install.ps1                  # 設定ファイルをシンボリックリンクで配置
├── config/
│   ├── powershell/              # PowerShell プロファイル
│   ├── git/                     # 共有 gitconfig（個人情報は含まない）
│   ├── copilot/                 # GitHub Copilot CLI 設定・指示書
│   ├── oh-my-posh/              # プロンプトテーマ
│   └── nushell/                 # Nushell 設定
├── scripts/
│   ├── modernize-dev-env.ps1    # ツールチェーンの一括更新（冪等・要管理者）
│   └── run-elevated.ps1         # 上記を昇格して実行しログを残すラッパ
└── packages/
    ├── export.ps1               # 現在のマシン状態を manifest に書き出す
    ├── restore.ps1              # manifest からツールを復元する
    ├── winget.json
    ├── psmodules.txt
    ├── npm-global.txt
    └── uv-python.txt
```

### ツールチェーンの更新

```powershell
# 管理者 PowerShell で
.\scripts\modernize-dev-env.ps1              # 開発系のみ（既定）
.\scripts\modernize-dev-env.ps1 -WhatIfOnly  # 変更せず確認だけ
```

冪等なので何度実行しても安全です。オプションで
`-IncludeEditors` / `-IncludeApps` / `-IncludeOhMyPosh` /
`-RemoveDuplicateDotnet6Sdks` を追加できます。

このスクリプトが解決している落とし穴:

- **Windows Installer はマシン全体で排他**なので、winget を連続実行すると
  後続が `1618` で落ちます。`Global\_MSIExecute` ミューテックスを監視して直列化しています。
- **自分自身が動いている PowerShell はアンインストールしません。**
  やると `pwsh.exe` が消えてスクリプトごと死にます（実際に踏みました）。
- **ユーザースコープのパッケージは昇格すると触れません。**
  検出して「非昇格で実行してください」と案内します。
- **`GitHub.Copilot` は winget 対象外。** blocking pin を張って事故を防ぎます。

### リンク対象

| リポジトリ内 | 配置先 |
|---|---|
| `config/powershell/Microsoft.PowerShell_profile.ps1` | `$PROFILE.CurrentUserCurrentHost` |
| `config/git/gitconfig` | `~/.gitconfig` |
| `config/copilot/settings.json` | `~/.copilot/settings.json` |
| `config/copilot/copilot-instructions.md` | `~/.copilot/copilot-instructions.md` |
| `config/oh-my-posh/night-owl-ccusage.omp.json` | `~/.config/oh-my-posh/` |
| `config/nushell/config.nu`, `env.nu` | `%APPDATA%/nushell/` |

プロファイルの配置先は `$PROFILE` から取得します。
このマシンでは `Documents` が OneDrive にリダイレクトされているため、
パスを決め打ちすると壊れるためです。

---

## 設計方針

**個人情報はリポジトリに入れない**
`~/.gitconfig` は共有設定のみを持ち、末尾で `~/.gitconfig.local` を
`[include]` します。氏名とメールはそちらに置くので、リポジトリは公開しても安全です。
`install.ps1` は初回に既存の `user.name` / `user.email` を読み取って
`~/.gitconfig.local` を自動生成するため、手作業は不要です。

**破壊しない**
既存の実ファイルはリンクに置き換える前に `.backup/<timestamp>/` へ退避します。

**冪等**
すでに正しくリンクされていればスキップします。別の場所を指している場合は
`-Force` を付けない限り触りません。

**壊れないシェル**
PowerShell プロファイルは全ブロックがツール存在チェックで保護されているため、
ツールが未インストールでもシェルは正常に起動します。

---

## PowerShell プロファイルでできること

| キー / コマンド | 機能 |
|---|---|
| `Ctrl+R` | fzf で履歴検索 |
| `Ctrl+T` | fzf でファイルを選んで挿入 |
| `Alt+C` | fzf でディレクトリ移動 |
| `Tab` | メニュー補完 |
| `↑` / `↓` | 入力中の文字列で履歴を前方一致検索 |
| `z` / `zi` | zoxide によるジャンプ |
| `ll` / `la` / `lt` | eza（アイコン・git 状態・ツリー） |
| `b` / `bhelp` | bat（`bhelp git` で `--help` に色付け） |
| `lg` | lazygit |

ビルトインの `ls` / `cat` / `cd` は**あえて上書きしていません**。
PowerShell オブジェクトを期待するスクリプトが壊れるためです。

### 前提ツール

`winget install` で入るもの（`packages/restore.ps1` が面倒を見ます）:
`ripgrep` `fd` `bat` `eza` `zoxide` `fzf` `jq` `delta` `lazygit` `oh-my-posh`

PowerShell モジュール: `PSFzf` `CompletionPredictor`

---

## 運用

ツールを入れ替えたら manifest を更新します:

```powershell
.\packages\export.ps1
git add -A && git commit -m "chore: update package manifests"
```

設定を変えたときは、いつもの場所を編集するだけでリポジトリに反映されます
（シンボリックリンクなので）。あとはコミットするだけです。

---

## 注意点

- **シンボリックリンクには Developer Mode か管理者権限が必要**です。
  `install.ps1` は最初に判定して、足りない場合は何もせず案内を出します。
  （設定 → システム → 開発者向け → 開発者モード）

- **PowerShell のモジュールとプロファイルが OneDrive 配下にあります。**
  ファイルオンデマンドで実体が退避されるとシェル起動が遅くなったり
  失敗する可能性があります。気になる場合は `Documents` を OneDrive 管理から
  外すか、`PSModulePath` にローカルディレクトリを追加してください。

- **`GitHub.Copilot` は winget で更新しないでください。**
  Copilot CLI は自己更新するため、winget のマニフェストが遅れており
  `winget upgrade` するとダウングレードになります。更新は `copilot /update` を使います。
