#!/bin/bash
set -e

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

echo "==> Dotfiles installer"
echo ""

# Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
  echo "==> Installing Xcode Command Line Tools..."
  xcode-select --install
  echo "  Please complete the installation prompt, then re-run this script."
  exit 1
fi
echo "  Xcode CLT: ok"

# Homebrew
if ! command -v brew &>/dev/null; then
  echo ""
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi
echo "  Homebrew: ok"

# Packages via Brewfile
echo ""
echo "==> Installing packages (this may take a while)..."
brew bundle --file="$DOTFILES/Brewfile" 2>&1 | grep -E "^(Installing|Cask|Already|Error)" || true
echo "  packages: ok"

# npm global packages
echo ""
echo "==> Installing npm global packages..."
npm install -g @anthropic-ai/claude-code @openai/codex typescript 2>/dev/null
echo "  Claude Code, Codex, TypeScript: ok"

# Rust (via rustup, not brew)
echo ""
echo "==> Installing Rust..."
if ! command -v rustc &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  echo "  Rust: installed"
else
  echo "  Rust: already installed"
fi

# Symlinks
echo ""
echo "==> Linking dotfiles..."
link() {
  local src="$DOTFILES/$1"
  local dst="$HOME/$1"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "  backup: $dst → $dst.bak"
    mv "$dst" "$dst.bak"
  fi
  ln -sf "$src" "$dst"
  echo "  linked: ~/$1"
}

link .zshrc
link .gitconfig
link .gitignore_global
link .config/ghostty/config
link .config/starship.toml
link .config/nvim/init.lua
link .config/tmux/tmux.conf

# macOS defaults
echo ""
echo "==> Applying macOS defaults..."
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder ShowPathbar -bool true
echo "  macOS defaults: ok"

# Git config
echo ""
echo "==> Git user setup"
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
  printf "  Name: "
  read -r git_name
  git config --global user.name "$git_name"
fi
if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
  printf "  Email: "
  read -r git_email
  git config --global user.email "$git_email"
fi
echo "  git user: $(git config --global user.name) <$(git config --global user.email)>"

# Xcode
echo ""
echo "==> Xcode setup..."
if ! xcodebuild -version &>/dev/null; then
  echo "  Installing Xcode (requires Apple ID)..."
  xcodes install --latest
  # activate: find installed Xcode and set it
  XCODE_PATH=$(ls /Applications/ | grep -E "^Xcode.*\.app$" | head -1)
  if [ -n "$XCODE_PATH" ]; then
    sudo xcode-select -s "/Applications/$XCODE_PATH"
    echo "  Xcode activated: /Applications/$XCODE_PATH"
  fi
else
  echo "  Xcode: $(xcodebuild -version | head -1) already installed"
fi

echo ""
echo "============================================"
echo "  Done! Next steps:"
echo "============================================"
echo "  1. Restart terminal (or open a new tab)"
echo "  2. gh auth login          # GitHub"
echo "  3. nvim                   # installs plugins on first launch"
echo "  4. Open Docker Desktop    # start Docker daemon"
echo "  5. aws configure          # if using AWS"
echo "  6. gcloud init            # if using GCP"
echo "  7. xcodes install --latest # install Xcode (requires Apple ID)"
echo "     → run 'xcodes' to see available versions"
echo "============================================"
