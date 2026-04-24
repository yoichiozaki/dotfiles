#!/bin/bash
set -e

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

echo "==> Dotfiles installer"
echo ""

# Homebrew
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Apple Silicon
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi
echo "  Homebrew: ok"

# Packages
echo ""
echo "==> Installing packages..."
brew install \
  starship \
  zsh-autosuggestions zsh-syntax-highlighting zsh-completions \
  eza bat fd ripgrep fzf zoxide delta btop \
  lazygit gh jq xh tldr mise direnv \
  go node zig nim \
  neovim tmux \
  --quiet 2>/dev/null
echo "  packages: ok"

echo ""
echo "==> Installing fonts..."
brew install --cask font-hack-nerd-font --quiet 2>/dev/null
echo "  Hack Nerd Font: ok"

# Rust
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
if [ -z "$(git config --global user.name)" ]; then
  printf "  Name: "
  read -r git_name
  git config --global user.name "$git_name"
fi
if [ -z "$(git config --global user.email)" ]; then
  printf "  Email: "
  read -r git_email
  git config --global user.email "$git_email"
fi
echo "  git user: $(git config --global user.name) <$(git config --global user.email)>"

echo ""
echo "Done!"
echo ""
echo "Next steps:"
echo "  1. Restart your terminal (or open a new tab)"
echo "  2. Run: gh auth login"
echo "  3. Run: nvim  (first launch installs plugins)"
