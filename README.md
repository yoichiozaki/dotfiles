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
│   ├── daily-update.ps1         # 日次自動更新（ユーザースコープ・無人実行）
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

### 日々の更新（自動）

ユーザースコープの更新は**スケジューラで自動化済み**です。UAC が出ないものだけを対象にしているので、無人で完走します。

```powershell
.\scripts\daily-update.ps1                # 手動で今すぐ実行
.\scripts\daily-update.ps1 -WhatIfOnly
.\scripts\daily-update.ps1 -PinToolchains # 言語は更新せず報告のみ
.\scripts\daily-update.ps1 -Install       # タスク登録（実施済み）
.\scripts\daily-update.ps1 -Uninstall     # 解除
```

タスク名 `dotfiles-daily-update`、毎日 12:30（±5 分のゆらぎ）＋
PC が止まっていた場合に備えてログオン 10 分後にも実行。
ログは `scripts/logs/daily-YYYY-MM-DD.log`（30 世代で自動削除）。

自動更新の対象:

| 対象 | 内容 |
|---|---|
| winget | **user スコープのみ**（machine スコープは UAC が必要なので除外） |
| rustup | stable |
| fnm | 最新 LTS を取得し default に設定 |
| uv | 本体 + `uv tool`（poetry 等） |
| npm | グローバルパッケージ |
| cargo | `cargo-binstall` で導入した CLI |
| **Nim** | `choosenim update stable` |
| **Zig** | `zvm` で最新安定版へ（**zls も同じ版に同期**） |
| **MoonBit** | `moonup update` |
| user PATH | 重複除去 |
| `packages/` | manifest を再生成（差分は `git diff` で見える） |

**旧バージョンは削除されません**。問題があれば即座に戻せます:

```powershell
choosenim 2.2.8         # Nim
zvm use 0.15.2          # Zig
moonup default <ver>    # MoonBit
```

特定のコンパイラ版に固定したいプロジェクトを抱えている間は、
言語ツールチェーンだけ更新対象から外せます:

```powershell
.\scripts\daily-update.ps1 -PinToolchains   # 報告のみ、更新しない
```

machine スコープの更新（.NET SDK、VS Build Tools 等）は
`scripts\modernize-dev-env.ps1` を管理者 PowerShell で手動実行してください。

実装上の注意:

- スケジューラは `-NoProfile` で起動するため、**プロファイル経由の fnm 初期化が効きません。**
  そのままだと `node` / `npm` が見えず Node が更新されないので、
  スクリプト内で `fnm env` を明示的に適用しています。
- ログオントリガーは **`-User` の指定が必須**です。省略すると全ユーザー対象とみなされ、
  管理者権限が無いと「アクセスが拒否されました」で登録に失敗します。
- `winget upgrade --all` の終了コード `-1978335188`（ピン留めあり）は**失敗扱いしません**。
  `GitHub.Copilot` を意図的にピンしているため、これが正常状態です。
- **`zvm` に自己更新コマンドはありません。** `zvm ls-remote` は降順で
  末尾に `master`（開発版）が混じるため、`x.y.z` 形式だけを抜き出して
  最新安定版を判定しています。
- **`choosenim` 内蔵の unzip は現行アーカイブを展開できません**
  （`Attempted to read past end of file`）。このエラーを検出したら
  公式 zip を取得して `Expand-Archive` で展開し直すフォールバックが働きます。

### ツールチェーンの更新（手動・要管理者）

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
- **ユーザー PATH の重複を毎回掃除します。**
  .NET SDK などのインストーラは実行のたびに自分の bin を追記するため、
  放っておくと重複が増え続けます。順序（＝優先度）は保ったまま重複だけ除去し、
  変更前は `scripts/user-path.backup.txt` に退避します。
  存在しないディレクトリは消しません（`~\.dotnet\tools` のように
  必要になった時点で作られる既知のパスがあるため）。

### WSL Containers

WSL に同梱される **`wslc.exe`**（別名 **`container.exe`**）で Linux コンテナを実行します。
必要な WSL は **2.9.3 以降**、GA リリースは **3.0.1** です。
別のコンテナエンジンをインストールする必要はありません。
WSL 自体は `packages\winget.json` の `Microsoft.WSL` で復元対象になっています。

```powershell
# 管理者 PowerShell で更新（初回に WSL 自体がない場合は wsl --install --no-distribution）
wsl --update
wsl --version

# 通常の PowerShell から利用
wslc version
wslc run --rm hello-world
wslc system info
wslc container list --all
```

WSL の更新時は、作業を保存し、実行中のコンテナを安全に停止してから
Docker Desktop 等を終了し、`wsl --shutdown` で WSL を停止してください。
起動中の WSL サービスを停止できないと、更新が `1921` / `1603` で失敗する場合があります。
更新後は必要な WSL ディストリビューションと Docker Desktop を起動し直します。

既存の **Docker Desktop / Ubuntu は残したまま併用**します。
`docker` コマンドのエイリアスやコンテキストは変更しません。
WSLc と Docker Desktop のイメージ・コンテナは別管理で、データは dotfiles に含めません。
GA 時点では WSLc の Compose は未対応のため、既存の Compose 環境は引き続き
Docker Desktop の `docker compose` を使用します。

公式手順: [Get started with containers on WSL](https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-containers)

### リンク対象

| リポジトリ内 | 配置先 |
|---|---|
| `config/powershell/Microsoft.PowerShell_profile.ps1` | `$PROFILE.CurrentUserCurrentHost` |
| `config/git/gitconfig` | `~/.gitconfig` |
| `config/copilot/settings.json` | `~/.copilot/settings.json` |
| `config/copilot/copilot-instructions.md` | `~/.copilot/copilot-instructions.md` |
| `config/oh-my-posh/night-owl-ccusage.omp.json` | `~/.config/oh-my-posh/` |
| `config/nushell/config.nu`, `env.nu` | `%APPDATA%/nushell/` |
| `config/windows-terminal/settings.json` | `%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/` |

プロファイルの配置先は `$PROFILE` から取得します。
このマシンでは `Documents` が OneDrive にリダイレクトされているため、
パスを決め打ちすると壊れるためです。

### Copilot CLI の既定モデル

`~\.copilot\settings.json` で、既定モデルを **GPT-6 Astra** (`gpt-6-astra`)、
コンテキストを **1M** (`contextTier: long_context`)、
推論強度を **Max** (`effortLevel: max`) に設定しています。
セッションや起動オプションで個別に指定した設定がある場合は、そちらが優先されます。

### Copilot CLI の computer-use

`~\.copilot\settings.json` の `enabledFeatureFlags.COMPUTER_USE` を `true` に設定し、
同梱の computer-use プラグインを有効化しています。CLI を再起動すると適用されます。
状態確認や有効・無効の切り替えには `/computer` を使います。

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

## 言語ツールチェーン

**すべて専用のバージョンマネージャ経由**で管理し、素の直接インストールは避けています。
プロジェクトごとにバージョンを固定でき、更新も一元化できるためです。

| 言語 | マネージャ | 現在 | プロジェクト固定 |
|---|---|---|---|
| Rust | `rustup` | 1.98.0 | `rust-toolchain.toml` |
| Python | `uv` | 3.13.15 | `uv python pin` / `.python-version` |
| Node.js | `fnm` | 24.20.0 (LTS) | `.nvmrc` / `.node-version`（`cd` で自動切替） |
| Nim | `choosenim` | 2.2.10 | `choosenim <ver>` |
| Zig | `zvm` | 0.16.0 | `zvm use <ver>` |
| MoonBit | `moonup` | 0.10.11 | `moonup pin <ver>` |
| Go | 公式 | 1.27.0 | `go.mod` の `toolchain` 行 |
| .NET | 公式 SDK | 10.0.400 | `global.json` |

### 言語サーバ (LSP)

エディタ補完のために、コンパイラとバージョンを合わせて導入しています。

| | |
|---|---|
| `zls` 0.16.0 | **zvm が zig と同時に管理**（zls は zig とバージョン一致が必須） |
| `nimlangserver` 1.14.0 | 公式ビルド済みバイナリ |
| `moon-lsp` | MoonBit ツールチェーン同梱 |

### パッケージマネージャ

| | |
|---|---|
| Python | `uv`（venv・依存解決・ロック・`uv tool` によるCLI導入まで一括） |
| Node.js | `corepack`（`package.json` の `packageManager` で pnpm/yarn を固定） |
| Rust | `cargo` + `cargo-binstall`（ビルド済みバイナリを取得、コンパイル不要） |

`poetry` は非推奨の `~/.poetry` インストーラ版が壊れていたため、
`uv tool install poetry` で入れ直しています（隔離 venv で管理）。

---

## モダン CLI ツール

従来コマンドの置き換え。**ビルトインの `ls` / `cat` / `ps` / `cd` は上書きしていません**
（PowerShell オブジェクトを期待するスクリプトが壊れるため）。
Windows に存在しない `du` / `df` / `top` のみ関数として定義しています。

| 用途 | ツール | 旧来 |
|---|---|---|
| 検索 | `rg` (ripgrep) | grep |
| ファイル検索 | `fd` | find |
| 閲覧 | `bat` | cat |
| 一覧 | `eza` (`ll`/`la`/`lt`) | ls |
| ディレクトリ移動 | `zoxide` (`z`/`zi`) | cd |
| 曖昧検索 | `fzf` | — |
| シェル履歴 | `atuin` (Ctrl+R) | — |
| ディスク使用量 | `dust` (`du`) | du |
| ディスク空き | `duf` (`df`) | df |
| プロセス監視 | `bottom` (`top`) | top |
| プロセス一覧 | `procs` | ps |
| 置換 | `sd` | sed |
| 差分 | `delta` / `difft` | diff |
| JSON / YAML | `jq` / `yq` | — |
| HTTP | `xh` | curl |
| Git TUI | `lazygit` (`lg`) | — |
| ファイラ | `yazi` | — |
| Markdown 表示 | `glow` | — |
| コード統計 | `tokei` | cloc |
| ベンチマーク | `hyperfine` | time |
| タスクランナー | `just` | make |
| ファイル監視 | `watchexec` | — |

---

## 注意点

- **Windows Terminal の PowerShell プロファイルはパスを明示しています。**
  winget が `Microsoft.PowerShell` を **MSI から MSIX（Store 形式）に変更**したため、
  従来の `C:\Program Files\PowerShell\7\pwsh.exe` は**存在しません**。
  WT の動的プロファイル（`Windows.Terminal.PowershellCore`）が旧パスを掴んだままだと
  `エラー 2147942402 (0x80070002) 指定されたファイルが見つかりません` になります。

  そこで `commandline` に**アプリ実行エイリアス**を明示しています:

  ```
  %LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe
  ```

  MSIX の実体パスはバージョン番号を含む
  (`...\Microsoft.PowerShell_7.6.5.0_x64__8wekyb3d8bbwe\pwsh.exe`) ため、
  直接指定すると更新のたびに壊れます。エイリアスはバージョン非依存です。

  なお Windows Terminal は設定保存時にファイルを置き換えることがあり、
  その際シンボリックリンクが実ファイルに戻る可能性があります。
  そうなったら `.\install.ps1` を再実行すれば復旧します（冪等）。

- **Git 自身の自動更新は無効化してあります。**
  Git for Windows は「Git for Windows Updater」というタスクを作り、
  毎日 `git update-git-for-windows --gui` を**ログインユーザー権限で**実行します。
  昇格していないため `C:\Program Files\Git\etc\gitconfig` を書けず、
  インストーラのポップアップを出したうえで
  **「system config をセットできない」と毎日失敗**します。
  `Git.Git` は `scripts\modernize-dev-env.ps1` が昇格して更新するので、
  同スクリプトがこのタスクを無効化します。

- **`npm` は昇格スクリプトでは更新しません。**
  Node は fnm（ユーザー単位）管理なので、昇格 + `-NoProfile` のシェルからは
  `npm` が見えません。npm の更新は `scripts\daily-update.ps1` の担当です。

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
  事故防止のため winget に **blocking pin** を設定済みです
  （解除する場合は `winget pin remove --id GitHub.Copilot`）。

- **pyenv-win の更新機能が壊れています。**
  `pyenv update` が `htmlfile: This command is not supported` で失敗します
  （VBS の ActiveX が最近の Windows でブロックされるため）。
  さらに `versions\3.13.2` の中身は実際には **3.13.15**、`versions\3.10.4` は
  **3.10.11** で、ディレクトリ名が実態と食い違っています。
  → 導入済みの **uv への移行を推奨**します:
  ```powershell
  uv python install 3.14
  uv venv / uv sync / uv run
  ```
  既存プロジェクトの依存があるため pyenv 自体は残してあります。
  同様に poetry も旧 `~\.poetry` インストーラ方式（現在は非推奨）なので、
  `uv` か `pipx` への移行が望ましいです。

- **Hugo / FFmpeg は winget が個別に特定できません。**
  `winget list` には出るのに `winget upgrade --id <ID>` は
  「インストール済みのパッケージが見つかりません」を返します（winget の相関バグ）。
  更新するにはアンインストール → 再インストールが必要です。
  また FFmpeg は winget 版と yt-dlp 版の 2 系統が PATH にあります。

- **.NET 6 SDK が 3 本（6.0.202 / 6.0.203 / 6.0.428）残っています。**
  既定は .NET 10 ですが、`global.json` で固定しているプロジェクトが
  ありうるため自動削除はしていません。整理する場合は
  `.\scripts\modernize-dev-env.ps1 -RemoveDuplicateDotnet6Sdks`。
