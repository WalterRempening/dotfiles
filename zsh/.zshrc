export PATH="/usr/local/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
# Added by Antigravity
export PATH="/Users/wrd/.antigravity/antigravity/bin:$PATH"
export PULUMI_CONFIG_PASSPHRASE="w@LT3r@HOME"

# OrbStack Docker socket
export DOCKER_HOST="unix:///Users/wrd/.orbstack/run/docker.sock"
alias vim="nvim"
alias vi="nvim"
alias vil="nvim -c Flog"
alias vilu="nvim -c 'Flog -auto-update'"
alias vif="nvim -c DiffviewOpen"
alias dbui="nvim -c DBUI"
alias ls="eza --icons=always -1"
alias ll="eza --long --all --icons=always"
alias lt="eza --tree --icons=always" 
alias lgit="lazygit"
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
