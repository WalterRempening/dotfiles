#!/usr/bin/env bash
# setup.sh — Bootstrap a fresh macOS machine with all tools and projects
# Usage: curl the dotfiles repo, then run ./setup.sh

set -euo pipefail

DOTFILES_DIR="$HOME/dotfiles"
IOSEFIN_DIR="$HOME/Dev/iosefin"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

step() { echo -e "\n${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}Warning:${NC} $1"; }

# ---------------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------------
step "Installing Homebrew"
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for the rest of this script
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
else
  echo "Homebrew already installed."
fi

# ---------------------------------------------------------------------------
# 2. Git (needed before anything else)
# ---------------------------------------------------------------------------
step "Installing Git"
brew install git

# ---------------------------------------------------------------------------
# 3. Build dependencies for Neovim and tmux from source
# ---------------------------------------------------------------------------
step "Installing build dependencies"
brew install cmake ninja gettext curl libtool automake pkg-config \
  libevent ncurses bison utf8proc

# ---------------------------------------------------------------------------
# 4. Neovim from source (latest)
# ---------------------------------------------------------------------------
step "Building Neovim from source"
NVIM_BUILD_DIR="$HOME/.local/src/neovim"
if [[ -d "$NVIM_BUILD_DIR" ]]; then
  cd "$NVIM_BUILD_DIR"
  git pull
else
  mkdir -p "$(dirname "$NVIM_BUILD_DIR")"
  git clone https://github.com/neovim/neovim.git "$NVIM_BUILD_DIR"
  cd "$NVIM_BUILD_DIR"
fi
make CMAKE_BUILD_TYPE=RelWithDebInfo
sudo make install
cd "$DOTFILES_DIR"

# ---------------------------------------------------------------------------
# 5. tmux from source (latest)
# ---------------------------------------------------------------------------
step "Building tmux from source"
TMUX_BUILD_DIR="$HOME/.local/src/tmux"
if [[ -d "$TMUX_BUILD_DIR" ]]; then
  cd "$TMUX_BUILD_DIR"
  git pull
else
  mkdir -p "$(dirname "$TMUX_BUILD_DIR")"
  git clone https://github.com/tmux/tmux.git "$TMUX_BUILD_DIR"
  cd "$TMUX_BUILD_DIR"
fi
sh autogen.sh
./configure
make
sudo make install
cd "$DOTFILES_DIR"

# ---------------------------------------------------------------------------
# 6. Nerd Fonts
# ---------------------------------------------------------------------------
step "Installing Nerd Fonts"
brew install --cask font-meslo-lg-nerd-font

# ---------------------------------------------------------------------------
# 7. Brew formulae
# ---------------------------------------------------------------------------
step "Installing brew formulae"
FORMULAE=(
  acli
  aerc
  autoconf
  automake
  azure-cli
  bash
  cmake
  curl
  direnv
  eza
  ffmpeg
  fzf
  gemini-cli
  gh
  ghostscript
  gnupg
  jq
  lazydocker
  lazygit
  libmagic
  libpq
  mise
  ninja
  node
  notmuch
  opencode
  pillow
  pipx
  pnpm
  pulumi
  python@3.13
  python@3.14
  readline
  ripgrep
  sox
  starship
  stow
  stripe-cli
  supabase
  tesseract
  texlab
  w3m
  yazi
  zsh-autocomplete
  zsh-autosuggestions
  zsh-syntax-highlighting
)

for formula in "${FORMULAE[@]}"; do
  brew install "$formula" 2>/dev/null || warn "Failed to install $formula"
done

# ---------------------------------------------------------------------------
# 8. Brew casks
# ---------------------------------------------------------------------------
step "Installing brew casks"
CASKS=(
  aerospace
  affinity
  balenaetcher
  brave-browser
  dolphin
  es-de
  flameshot
  ghostty
  keka
  linearmouse
  localsend
  lulu
  mactex
  mullvad-browser
  orbstack
  pcsx2
  pgadmin4
  powershell
  proton-pass
  protonvpn
  qbittorrent
  retroarch
  skim
  spotify
  telegram
  tor-browser
  transmission
  vlc
)

for cask in "${CASKS[@]}"; do
  brew install --cask "$cask" 2>/dev/null || warn "Failed to install $cask"
done

# ---------------------------------------------------------------------------
# 9. Claude Code
# ---------------------------------------------------------------------------
step "Installing Claude Code"
npm install -g @anthropic-ai/claude-code

# ---------------------------------------------------------------------------
# 10. SSH key
# ---------------------------------------------------------------------------
step "Setting up SSH key"
SSH_KEY="$HOME/.ssh/id_ed25519"
if [[ ! -f "$SSH_KEY" ]]; then
  read -rp "Enter your email for the SSH key: " ssh_email
  ssh-keygen -t ed25519 -C "$ssh_email" -f "$SSH_KEY"
  eval "$(ssh-agent -s)"
  ssh-add "$SSH_KEY"

  echo ""
  echo "=========================================="
  echo "Your public SSH key (add to GitHub):"
  echo "=========================================="
  cat "${SSH_KEY}.pub"
  echo ""
  echo "Add it at: https://github.com/settings/keys"
  read -rp "Press Enter once you've added the key to GitHub..."
else
  echo "SSH key already exists."
fi

# ---------------------------------------------------------------------------
# 11. Stow dotfiles
# ---------------------------------------------------------------------------
step "Stowing dotfiles"
cd "$DOTFILES_DIR"
for dir in */; do
  dir="${dir%/}"
  [[ "$dir" == "iosefin" ]] && continue
  [[ "$dir" == "setup.sh" ]] && continue
  stow "$dir" 2>/dev/null || warn "Failed to stow $dir"
done

# ---------------------------------------------------------------------------
# 12. Mise runtimes
# ---------------------------------------------------------------------------
step "Installing mise runtimes"
mise install

# ---------------------------------------------------------------------------
# 13. fzf-tab (zsh plugin not in brew)
# ---------------------------------------------------------------------------
step "Installing fzf-tab"
if [[ ! -d "$HOME/.fzf-tab" ]]; then
  git clone https://github.com/Aloxaf/fzf-tab "$HOME/.fzf-tab"
else
  echo "fzf-tab already installed."
fi

# ---------------------------------------------------------------------------
# 14. Clone iosefin projects
# ---------------------------------------------------------------------------
step "Setting up iosefin workspace (~/Dev/iosefin)"
mkdir -p "$IOSEFIN_DIR"

clone_repo() {
  local target="$1" url="$2"
  if [[ -d "$target" ]]; then
    echo "  Already exists: $target"
  else
    mkdir -p "$(dirname "$target")"
    echo "  Cloning: $url -> $target"
    git clone "$url" "$target"
  fi
}

# buchführung
clone_repo "$IOSEFIN_DIR/buchführung/buchführung-app"   "git@github.com:WalterRempening/buchfuehrung-app.git"

# hairlich
clone_repo "$IOSEFIN_DIR/hairlich/hairlich-salon-website" "git@github.com:WalterRempening/hairlich-salon-website.git"

# hopninj
clone_repo "$IOSEFIN_DIR/hopninj/skola-hopninj-app"      "git@github.com:WalterRempening/skola-hopninj-app.git"
clone_repo "$IOSEFIN_DIR/hopninj/skola-attento"           "git@github.com:WalterRempening/skola-attento.git"
clone_repo "$IOSEFIN_DIR/hopninj/skola-infrastructure"    "git@github.com:WalterRempening/skola-infrastructure.git"

# infra
clone_repo "$IOSEFIN_DIR/infra/säkerhetskopia"            "git@github.com:WalterRempening/s-kerhetskopia.git"

# menoserv
clone_repo "$IOSEFIN_DIR/menoserv/buakfieren-app"         "git@github.com:WalterRempening/buakfieren-app.git"

# sbs
clone_repo "$IOSEFIN_DIR/sbs/skola-api"                   "git@github.com:WalterRempening/skola-api.git"
clone_repo "$IOSEFIN_DIR/sbs/skola-ui"                     "git@github.com:WalterRempening/skola-ui.git"

# senova
clone_repo "$IOSEFIN_DIR/senova/senova-pos"                "git@github.com:WalterRempening/senova-pos.git"

# unecre
clone_repo "$IOSEFIN_DIR/unecre/web_point_of_sale"         "git@github.com:Unecre-AC/web_point_of_sale.git"
clone_repo "$IOSEFIN_DIR/unecre/api_point_of_sale"         "git@github.com:Unecre-AC/api_point_of_sale.git"

# Copy iosefin scripts into place
step "Installing iosefin workspace scripts"
cp "$DOTFILES_DIR/iosefin/iosefin-lib.sh"            "$IOSEFIN_DIR/"
cp "$DOTFILES_DIR/iosefin/iosefin-workspace.sh"      "$IOSEFIN_DIR/"
cp "$DOTFILES_DIR/iosefin/iosefin-sync-worktrees.sh" "$IOSEFIN_DIR/"
chmod +x "$IOSEFIN_DIR"/iosefin-*.sh

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal (or run: source ~/.zshrc)"
echo "  2. Run: iosefin up    — to create tmux workspace"
echo "  3. Configure mise runtimes per project as needed"
echo "  4. Set up .env files in each project"
