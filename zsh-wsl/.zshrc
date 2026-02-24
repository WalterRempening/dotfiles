export PATH="/usr/local/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

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
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# fzf-tab preview for cd (show directory contents)
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --icons=always -1 --color=always $realpath'

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
eval "$(direnv hook zsh)"
