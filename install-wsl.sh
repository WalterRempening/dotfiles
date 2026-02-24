#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# WSL Ubuntu Bootstrap Script
# Installs tools and stows dotfiles packages
# ──────────────────────────────────────────────

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*"; exit 1; }

# ── 1. apt packages ──────────────────────────
info "Installing apt packages..."
sudo apt-get update
sudo apt-get install -y \
  stow zsh xclip direnv ripgrep tmux \
  zsh-autosuggestions zsh-syntax-highlighting \
  build-essential curl wget unzip git fontconfig

ok "apt packages installed"

# ── 2. Set zsh as default shell ──────────────
if [ "$SHELL" != "$(which zsh)" ]; then
  info "Setting zsh as default shell..."
  chsh -s "$(which zsh)"
  ok "Default shell set to zsh"
else
  ok "zsh is already the default shell"
fi

# ── 3. Neovim 0.11+ (tarball) ────────────────
if ! command -v nvim &>/dev/null || [[ "$(nvim --version | head -1)" < "NVIM v0.11" ]]; then
  info "Installing Neovim 0.11+..."
  NVIM_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
  curl -fsSL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" -o /tmp/nvim.tar.gz
  sudo rm -rf /opt/nvim
  sudo tar -xzf /tmp/nvim.tar.gz -C /opt
  sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
  rm /tmp/nvim.tar.gz
  ok "Neovim $(nvim --version | head -1) installed"
else
  ok "Neovim already up to date: $(nvim --version | head -1)"
fi

# ── 4. fzf (git clone + install) ─────────────
if [ ! -d "$HOME/.fzf" ]; then
  info "Installing fzf..."
  git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
  ok "fzf installed"
else
  ok "fzf already installed"
fi

# ── 5. Starship prompt ───────────────────────
if ! command -v starship &>/dev/null; then
  info "Installing Starship..."
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y
  ok "Starship installed"
else
  ok "Starship already installed"
fi

# ── 6. mise ──────────────────────────────────
if ! command -v mise &>/dev/null; then
  info "Installing mise..."
  curl -fsSL https://mise.run | sh
  ok "mise installed"
else
  ok "mise already installed"
fi

# ── 7. eza (official apt repository) ─────────
if ! command -v eza &>/dev/null; then
  info "Installing eza..."
  sudo mkdir -p /etc/apt/keyrings
  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
  sudo chmod 644 /etc/apt/keyrings/gierens.gpg
  sudo chmod 644 /etc/apt/sources.list.d/gierens.list
  sudo apt-get update
  sudo apt-get install -y eza
  ok "eza installed"
else
  ok "eza already installed"
fi

# ── 8. lazygit (GitHub release) ──────────────
if ! command -v lazygit &>/dev/null; then
  info "Installing lazygit..."
  LAZYGIT_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" -o /tmp/lazygit.tar.gz
  tar -xzf /tmp/lazygit.tar.gz -C /tmp lazygit
  sudo install /tmp/lazygit /usr/local/bin/lazygit
  rm /tmp/lazygit.tar.gz /tmp/lazygit
  ok "lazygit ${LAZYGIT_VERSION} installed"
else
  ok "lazygit already installed"
fi

# ── 9. fzf-tab (zsh plugin) ─────────────────
if [ ! -d "$HOME/.fzf-tab" ]; then
  info "Installing fzf-tab..."
  git clone --depth 1 https://github.com/Aloxaf/fzf-tab "$HOME/.fzf-tab"
  ok "fzf-tab installed"
else
  ok "fzf-tab already installed"
fi

# ── 10. TPM (tmux plugin manager) ────────────
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  info "Installing TPM..."
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  ok "TPM installed"
else
  ok "TPM already installed"
fi

# ── 11. JetBrainsMono Nerd Font ──────────────
if ! fc-list | grep -qi "JetBrainsMono"; then
  info "Installing JetBrainsMono Nerd Font..."
  FONT_VERSION=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${FONT_VERSION}/JetBrainsMono.tar.xz" -o /tmp/JetBrainsMono.tar.xz
  mkdir -p "$HOME/.local/share/fonts"
  tar -xJf /tmp/JetBrainsMono.tar.xz -C "$HOME/.local/share/fonts"
  fc-cache -fv
  rm /tmp/JetBrainsMono.tar.xz
  ok "JetBrainsMono Nerd Font installed"
else
  ok "JetBrainsMono Nerd Font already installed"
fi

# ── 12. Stow dotfiles ───────────────────────
info "Stowing dotfiles..."

STOW_PACKAGES=(zsh-wsl git starship tmux nvim mise)

# Back up any existing non-symlink configs that would conflict
BACKUP_FILES=(.zshrc .zprofile .gitconfig .tmux.conf .config/mise/config.toml .config/starship.toml .config/starship/config.toml)
for f in "${BACKUP_FILES[@]}"; do
  if [ -f "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
    warn "Backing up existing ~/$f to ~/${f}.bak"
    mkdir -p "$(dirname "$HOME/${f}.bak")"
    mv "$HOME/$f" "$HOME/${f}.bak"
  fi
done

cd "$DOTFILES_DIR"
for pkg in "${STOW_PACKAGES[@]}"; do
  info "  stow $pkg"
  # Filter non-fatal BUG warnings caused by WSL /mnt/c symlinks
  stow -d "$DOTFILES_DIR" -t "$HOME" -R "$pkg" 2>&1 | grep -v "^BUG in find_stowed_path" || true
done

ok "All packages stowed"

# ── Done ─────────────────────────────────────
echo ""
ok "WSL dotfiles setup complete!"
echo ""
info "Next steps:"
info "  1. Run 'exec zsh' to reload your shell"
info "  2. Run 'tmux' then press 'C-a I' to install tmux plugins"
info "  3. Run 'nvim' — plugins will auto-install on first launch"
info "  4. Run 'mise install' to install tool versions (node, java, etc.)"
