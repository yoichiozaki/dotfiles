# dotfiles

Yoichi Ozaki's dotfiles for macOS.

## Setup

```bash
xcode-select --install  # if not already installed
git clone https://github.com/yoichiozaki/dotfiles ~/dotfiles
~/dotfiles/install.sh
```

After installation:

```bash
gh auth login    # GitHub
nvim             # installs plugins on first launch
az login         # Azure
aws configure    # AWS
gcloud init      # GCP
```

## What's included

### Shell
- **zsh** — autosuggestions, syntax highlighting, tab completion
- **Starship** — prompt with git status, command duration, system info
- **fzf** — fuzzy finder (`Ctrl+R` history, `Ctrl+T` file search)
- **zoxide** — smart `cd` (`z <keyword>`)

### Editor & Terminal
- **Neovim** — LSP, Catppuccin theme, Telescope, Neo-tree
- **Ghostty** — Catppuccin Mocha, Hack Nerd Font, transparency
- **tmux** — Catppuccin statusbar, vim keybindings

### Languages
| Language | Version Manager |
|----------|----------------|
| Go | homebrew |
| Node.js | mise |
| TypeScript | npm global |
| Python | mise |
| Rust | rustup |
| Zig | homebrew |
| Nim | homebrew |

### Tools
| Category | Tools |
|----------|-------|
| Git | git, gh, lazygit, git-lfs, delta, gnupg |
| Containers | Docker Desktop, kubectl, k9s, helm, kubectx, stern |
| Cloud | awscli, azure-cli, google-cloud-sdk, terraform, aztfexport |
| CLI | eza, bat, fd, ripgrep, fzf, zoxide, btop, jq, xh, tldr |
| DB | PostgreSQL, Redis (client tools), TablePlus |
| API | grpcurl, mkcert, cloudflared |
| Apps | VS Code, Rectangle, TablePlus |

## Structure

```
dotfiles/
├── install.sh              # setup script
├── Brewfile                # all packages
├── .zshrc
├── .gitconfig
├── .gitignore_global
└── .config/
    ├── ghostty/config
    ├── starship.toml
    ├── nvim/init.lua
    └── tmux/tmux.conf
```

## Manual settings (not automated)

These require manual setup via System Settings after installation.

**Screenshot shortcuts** (System Settings → Keyboard → Keyboard Shortcuts → Screenshots)
| Key | Action |
|-----|--------|
| `Cmd+Shift+S` | Copy selected area to clipboard |

---

## Key bindings

### Shell
| Key | Action |
|-----|--------|
| `→` / `Ctrl+F` | Accept autosuggestion |
| `Ctrl+R` | Fuzzy search history |
| `Ctrl+T` | Fuzzy search files |
| `Alt+C` | Fuzzy cd into directory |

### tmux (prefix: `Ctrl+A`)
| Key | Action |
|-----|--------|
| `prefix + \|` | Split vertical |
| `prefix + -` | Split horizontal |
| `prefix + hjkl` | Navigate panes |
| `prefix + r` | Reload config |

### Neovim (leader: `Space`)
| Key | Action |
|-----|--------|
| `Space + ff` | Find files |
| `Space + fg` | Live grep |
| `Space + e` | File explorer |
| `Space + /` | Toggle comment |
| `gd` | Go to definition |
| `K` | Hover docs |
