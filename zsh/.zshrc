export PATH="/usr/local/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
# Added by Antigravity
export PATH="/Users/wrd/.antigravity/antigravity/bin:$PATH"
export PULUMI_CONFIG_PASSPHRASE="w@LT3r@HOME"
export PATH="$HOME/.config/emacs/bin:$PATH"

# OrbStack Docker socket
export DOCKER_HOST="unix:///Users/wrd/.orbstack/run/docker.sock"
alias vim="nvim"
alias vi="nvim"
alias vil="nvim -c Flog"
alias vilu="nvim -c 'Flog -auto-update'"
alias vif="nvim -c DiffviewOpen"
alias dbui="nvim -c DBUI"
alias ls="eza --icons=auto -1"
alias ll="eza --long --all --icons=auto"
alias lt="eza --tree --icons=auto"
alias lgit="lazygit"
alias vemacs="emacs --init-directory=$HOME/.emacs-vanilla"  # vanilla Emacs, leaves Doom untouched
alias ldock="lazydocker"
alias jira="jiratui ui"

eval "$(starship init zsh)"
eval "$(mise activate zsh)"

# history setup
HISTFILE=$HOME/.zhistory
SAVEHIST=1000
HISTSIZE=999

setopt share_history
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_verify

# completion using arrow keys (based on history)
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Set up fzf key bindings and fuzzy completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}'
# Enable interactive menu selection for completions
zstyle ':completion:*' menu select=2
# Enable case-insensitive globbing (e.g., ls *.TXT)
setopt nocaseglob
autoload -U compinit; compinit
source <(fzf --zsh)
source ~/.fzf-tab/fzf-tab.plugin.zsh
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# fzf-tab preview for cd (show directory contents)
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --icons=always -1 --color=always $realpath'

# bun completions
[ -s "/Users/wrd/.bun/_bun" ] && source "/Users/wrd/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
eval "$(direnv hook zsh)"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
export PATH="/Library/TeX/texbin:$PATH"

# WakaTime terminal tracking
# Sends heartbeat on each command, using tmux session as project name
_wakatime_heartbeat() {
  # Only track if wakatime-cli exists
  [[ -x "$HOME/.wakatime/wakatime-cli" ]] || return

  local project="Terminal"
  local entity="zsh"

  # Use tmux session name as project if inside tmux
  if [[ -n "$TMUX" ]]; then
    project=$(tmux display-message -p '#S' 2>/dev/null || echo "Terminal")
  fi

  # Detect current foreground process for better categorization
  local cmd="${1%% *}"  # First word of command
  case "$cmd" in
    claude)   entity="claude-code" ;;
    opencode) entity="opencode" ;;
    nvim|vim) entity="neovim" ;;
    git|lgit) entity="git" ;;
    lazygit)  entity="git" ;;
    docker|lazydocker) entity="docker" ;;
    *)        entity="terminal" ;;
  esac

  # Send heartbeat in background (non-blocking)
  "$HOME/.wakatime/wakatime-cli" --write \
    --plugin "zsh-wakatime/1.0.0" \
    --entity-type app \
    --entity "$entity" \
    --project "$project" \
    --language "Shell" \
    &>/dev/null &!
}

# Hook into preexec (runs before each command)
autoload -Uz add-zsh-hook
add-zsh-hook preexec _wakatime_heartbeat

skolaHopninjDb() {
  local file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file="$2"; shift 2 ;;
      *)      echo "Usage: skolaHopninjDb --file /path/to/dump"; return 1 ;;
    esac
  done
  [[ -z "$file" ]] && { echo "Usage: skolaHopninjDb --file /path/to/dump"; return 1; }
  [[ ! -f "$file" ]] && { echo "Error: file not found: $file"; return 1; }
  PGPASSWORD=skola pg_restore --host=localhost --port=5435 --username=skola --dbname=skola --clean --no-owner --no-privileges "$file"
}

# Iosefin workspace management
iosefin() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    up)   ~/dotfiles/iosefin/iosefin-workspace.sh "$@" ;;
    sync) ~/dotfiles/iosefin/iosefin-sync-worktrees.sh "$@" ;;
    *)    echo "Usage: iosefin {up [-p NAME] | sync}" ;;
  esac
}

# GitLab project defaults: fast-forward merge + squash-on-by-default +
# delete source branch after merge. Apply to a single project
# (`gitlab-apply-defaults iosefin/new-thing`) or every project in a
# group (`gitlab-apply-defaults --group iosefin`).
gitlab-apply-defaults() {
  local apply
  apply() {
    local id=$1 path=$2
    local resp ok
    resp=$(glab api "projects/$id" --method PUT \
      -f merge_method=ff \
      -f squash_option=default_on \
      -f remove_source_branch_after_merge=true 2>&1)
    ok=$(printf '%s' "$resp" | jq -r '
      if (.merge_method=="ff" and .squash_option=="default_on")
      then "OK" else "FAIL: \(.message // .error // .)" end
    ' 2>/dev/null || echo "FAIL: $resp")
    printf "→ %-40s %s\n" "$path" "$ok"
  }
  case "${1:-}" in
    --group)
      [[ -z "${2:-}" ]] && { echo "usage: gitlab-apply-defaults --group <group>"; return 1; }
      glab api "groups/$2/projects?per_page=100&include_subgroups=true&archived=false" \
        | jq -r '.[] | "\(.id)\t\(.path_with_namespace)"' \
        | while IFS=$'\t' read -r id path; do apply "$id" "$path"; done
      ;;
    "")
      echo "usage: gitlab-apply-defaults <namespace/project> | --group <group>"
      return 1
      ;;
    *)
      local id
      id=$(glab api "projects/${1//\//%2F}" | jq -r '.id // empty')
      [[ -z "$id" ]] && { echo "project not found: $1"; return 1; }
      apply "$id" "$1"
      ;;
  esac
}

# pnpm
export PNPM_HOME="/Users/wrd/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end

# Added by Antigravity IDE
export PATH="/Users/wrd/.antigravity-ide/antigravity-ide/bin:$PATH"
