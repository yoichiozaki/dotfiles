export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"

# Go
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

# direnv
eval "$(direnv hook zsh)"

# Completions
FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
autoload -Uz compinit && compinit

# Tab completion styling
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# History
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# Directory navigation
setopt AUTO_CD          # ディレクトリ名だけで cd
setopt AUTO_PUSHD       # cd のたびにスタックに積む
setopt PUSHD_IGNORE_DUPS

# eza (modern ls)
alias ls='eza --icons'
alias ll='eza --icons -l --git'
alias la='eza --icons -la --git'
alias lt='eza --icons --tree --level=2'
alias ltd='eza --icons --tree --level=2 --only-dirs'

# bat (syntax-highlighted cat)
alias cat='bat --paging=never'
alias less='bat'
export BAT_THEME="Catppuccin Mocha"

# ripgrep / fd
alias find='fd'
alias grep='rg'

# git with delta diff
export GIT_PAGER='delta'

# Useful aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -p'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias df='df -h'
alias du='du -sh'
alias ports='lsof -i -P -n | grep LISTEN'
alias path='echo $PATH | tr ":" "\n"'

# Editor
export EDITOR='nvim'
alias vim='nvim'
alias vi='nvim'

# fzf (fuzzy finder: Ctrl+R で履歴検索, Ctrl+T でファイル検索, Alt+C でディレクトリ移動)
eval "$(fzf --zsh)"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc,marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8'

# zoxide (スマートな cd: z <keyword> で移動)
eval "$(zoxide init zsh)"
alias cd='z'

# mise (language version manager: mise use node@20 etc.)
eval "$(mise activate zsh)"

# GitHub CLI completion
eval "$(gh completion -s zsh 2>/dev/null)"

# lazygit alias
alias lg='lazygit'

# tldr
alias help='tldr'

# xh (modern curl)
alias curl='xh'

# Git aliases
alias gs='git st'
alias gco='git co'
alias gbr='git br'
alias glog='git lg'
alias gundo='git undo'

# Functions
mkcd() { mkdir -p "$1" && cd "$1"; }

extract() {
  case "$1" in
    *.tar.gz|*.tgz) tar xzf "$1" ;;
    *.tar.bz2)      tar xjf "$1" ;;
    *.tar.xz)       tar xJf "$1" ;;
    *.tar)          tar xf  "$1" ;;
    *.zip)          unzip   "$1" ;;
    *.gz)           gunzip  "$1" ;;
    *.bz2)          bunzip2 "$1" ;;
    *.7z)           7z x    "$1" ;;
    *)              echo "Unknown format: $1" ;;
  esac
}

serve() { python3 -m http.server "${1:-8000}"; }

# Autosuggestions (accept with → or Ctrl+F)
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#6c7086"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Syntax highlighting (must be last before starship)
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Starship prompt
eval "$(starship init zsh)"
