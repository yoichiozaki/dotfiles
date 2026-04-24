#!/bin/bash
set -e

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

link() {
  local src="$DOTFILES/$1"
  local dst="$HOME/$1"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "  backup: $dst → $dst.bak"
    mv "$dst" "$dst.bak"
  fi
  ln -sf "$src" "$dst"
  echo "  linked: $dst"
}

echo "==> Linking dotfiles..."
link .zshrc
link .gitconfig
link .gitignore_global
link .config/ghostty/config
link .config/starship.toml
link .config/nvim/init.lua
link .config/tmux/tmux.conf

echo ""
echo "==> Installing packages (Homebrew)..."
if ! command -v brew &>/dev/null; then
  echo "  Homebrew not found. Install from https://brew.sh"
  exit 1
fi

brew install \
  starship zsh-autosuggestions zsh-syntax-highlighting zsh-completions \
  eza bat fd ripgrep fzf zoxide delta btop \
  lazygit gh jq xh tldr mise direnv \
  go node zig nim neovim tmux \
  --quiet 2>/dev/null

brew install --cask font-hack-nerd-font --quiet 2>/dev/null

echo ""
echo "==> Installing Rust..."
if ! command -v rustc &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi

echo ""
echo "Done! Open a new shell to apply changes."
