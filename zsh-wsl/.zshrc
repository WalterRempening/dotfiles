# ---------------------------------------------------------------------------
# Linux twin of zsh/.zshrc — keep the two in sync when you edit either.
#
# Deliberately absent (macOS-only): Homebrew PATH/shellenv, OrbStack
# DOCKER_HOST, /opt/homebrew plugin paths, libpq, /Library/TeX, Library/pnpm,
# Antigravity, the `vemacs` alias.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# PATH
# ---------------------------------------------------------------------------
# Every line PREPENDS, so the LAST one wins. This order is load-bearing: it is
# the original order, and shuffling it changes which binary resolves first.

export PATH="/usr/local/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
# PULUMI_CONFIG_PASSPHRASE is intentionally NOT set here. Pull it from a secret
# store if this machine ever needs to run Pulumi.

# ---------------------------------------------------------------------------
# Prompt & runtime managers
# ---------------------------------------------------------------------------

eval "$(starship init zsh)"
eval "$(mise activate zsh)"

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------

HISTFILE=$HOME/.zhistory
SAVEHIST=1000
HISTSIZE=999

setopt share_history
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_verify

# ---------------------------------------------------------------------------
# Completion
# ---------------------------------------------------------------------------
# compinit has to run before anything that registers completions.

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' menu select=2      # interactive menu selection
setopt nocaseglob                         # case-insensitive globbing (ls *.TXT)

autoload -U compinit; compinit

# ---------------------------------------------------------------------------
# Plugins
# ---------------------------------------------------------------------------
# zsh-syntax-highlighting wraps every widget bound before it, so it MUST stay
# last in this block.

source <(fzf --zsh)                       # fzf key bindings + fuzzy completion
source ~/.fzf-tab/fzf-tab.plugin.zsh
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# fzf-tab preview for cd (show directory contents)
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --icons=always -1 --color=always $realpath'

# ---------------------------------------------------------------------------
# Keybindings
# ---------------------------------------------------------------------------

# Arrow keys search history by what is already typed
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------

# editors
alias vim="nvim"
alias vi="nvim"
alias vil="nvim -c Flog"
alias vilu="nvim -c 'Flog -auto-update'"
alias vif="nvim -c DiffviewOpen"
# gitlab.nvim without opening nvim first: vmr picks which MR to review, vmrb
# opens the one for the branch you are already on.
alias vmr="nvim -c 'lua require(\"gitlab\").choose_merge_request()'"
alias vmrb="nvim -c 'lua require(\"gitlab\").review()'"
alias dbui="nvim -c DBUI"

# listing
alias ls="eza --icons=auto -1"
alias ll="eza --long --all --icons=auto"
alias lt="eza --tree --icons=auto"

# TUIs
alias lgit="lazygit"
alias ldock="lazydocker"
alias jira="jiratui ui"
alias lgb="glab-tui"

# Remote hosts. mosh resolves the host through ~/.ssh/config (HostName + User),
# and survives sleep/roaming between networks the way plain ssh does not.
alias vps="mosh iosefin-vps -- tmux new -A -s main"

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

# Restore a dump into the local Skola/Hopninj database.
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

# ---------------------------------------------------------------------------
# Late PATH entries
# ---------------------------------------------------------------------------
# These stay AFTER `mise activate` on purpose: they were originally sourced
# later, so they prepend in front of mise's shims. Moving them into the block
# at the top would let mise win instead.

export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"        # bun completions

# On Linux the pnpm standalone install puts binaries directly in PNPM_HOME,
# not in a bin/ subdir the way the macOS install does.
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

eval "$(direnv hook zsh)"
