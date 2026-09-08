#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Ubuntu Bootstrap Script (WSL + headless servers)
# Installs tools and stows dotfiles packages
#
# Sourcing policy, in order of preference:
#   1. The Ubuntu archive          — signed by Ubuntu, verified by apt.
#   2. An upstream signed apt repo — gh, mise. Key pinned in /etc/apt/keyrings.
#   3. A checksum-verified release — only for tools that exist in neither.
# Nothing is installed by piping a URL into a shell, and nothing is dpkg -i'd
# without verification.
#
# Headless-aware: skips the Nerd Font when there is no display, since fonts
# are rendered by the *client* terminal, not the box you SSH into.
# ──────────────────────────────────────────────

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*"; exit 1; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Download a release asset and check it against the project's published
# SHA-256 before installing.
#
# This is weaker than an apt signature: the checksum is served by the same host
# as the artifact, so it proves integrity, not provenance. It is the strongest
# option available for tools that ship no apt repository, and it does catch a
# truncated download or a swapped artifact. Used for exactly four tools below.
fetch_verified() {
  local url=$1 sums_url=$2
  local name; name="$(basename "$url")"
  info "  downloading $name"
  curl -fsSL "$url"      -o "$WORKDIR/$name"
  curl -fsSL "$sums_url" -o "$WORKDIR/sums.txt"
  ( cd "$WORKDIR" && awk -v n="$name" '$2 == n' sums.txt | sha256sum -c - ) >/dev/null 2>&1 \
    || error "SHA-256 verification FAILED for $name — refusing to install it"
  ok "  verified $name"
}

ARCH="$(dpkg --print-architecture)"
[ "$ARCH" = "amd64" ] || warn "arch is $ARCH; the checksum-verified downloads below assume amd64"

# ── 1. apt packages (Ubuntu-signed) ──────────
info "Installing apt packages..."
sudo apt-get update
sudo apt-get install -y \
  stow zsh xclip direnv ripgrep tmux mosh \
  zsh-autosuggestions zsh-syntax-highlighting \
  build-essential curl wget unzip git fontconfig \
  jq git-lfs bat fd-find zoxide postgresql-client \
  ca-certificates gnupg gettext software-properties-common \
  neovim lazygit fzf starship eza glab
# Ubuntu 26.04 carries all of these. On an older release some may be missing or
# too old — see the neovim version guard below for the one that actually
# matters to the nvim config.
#
# jq                -> gitlab-apply-defaults()
# git-lfs           -> the lfs filter in .gitconfig
# postgresql-client -> pg_restore, used by skolaHopninjDb()
# mosh              -> so this box can also be a mosh client
ok "apt packages installed"

# ── 2. Set zsh as default shell ──────────────
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]; then
  info "Setting zsh as default shell..."
  # sudo form: plain `chsh` prompts for a password and would hang a
  # non-interactive run over SSH.
  sudo chsh -s "$(command -v zsh)" "$USER"
  ok "Default shell set to zsh"
else
  ok "zsh is already the default shell"
fi

# ── 3. Neovim version guard ──────────────────
# The nvim config needs 0.11+. Ubuntu 26.04 ships 0.11.6; older releases do
# not. Upstream's GitHub release publishes NO checksums, so rather than pull an
# unverifiable tarball we fall back to the neovim PPA, which apt verifies with
# a GPG key like any other signed repo.
NVIM_MAJMIN="$(nvim --version 2>/dev/null | sed -n '1s/^NVIM v\([0-9]*\.[0-9]*\).*/\1/p')"
if [ -z "$NVIM_MAJMIN" ] || [ "$(printf '%s\n0.11\n' "$NVIM_MAJMIN" | sort -V | head -1)" != "0.11" ]; then
  warn "apt neovim is ${NVIM_MAJMIN:-absent}; the config needs 0.11+. Adding the neovim PPA."
  sudo add-apt-repository -y ppa:neovim-ppa/unstable
  sudo apt-get update
  sudo apt-get install -y neovim
  ok "Neovim $(nvim --version | head -1) installed from the PPA"
else
  ok "Neovim $(nvim --version | head -1) from the Ubuntu archive"
fi

# ── 4. mise (upstream signed apt repo) ───────
if ! command -v mise &>/dev/null; then
  info "Adding the mise apt repository..."
  sudo install -dm 755 /etc/apt/keyrings
  curl -fsSL https://mise.jdx.dev/gpg-key.pub \
    | sudo gpg --dearmor -o /etc/apt/keyrings/mise-archive-keyring.gpg
  sudo chmod 644 /etc/apt/keyrings/mise-archive-keyring.gpg
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg] https://mise.jdx.dev/deb stable main" \
    | sudo tee /etc/apt/sources.list.d/mise.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y mise
  ok "mise installed from its signed apt repo"
else
  ok "mise already installed"
fi

# ── 5. GitHub CLI (upstream signed apt repo) ─
if ! command -v gh &>/dev/null; then
  info "Adding the GitHub CLI apt repository..."
  sudo install -dm 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y gh
  ok "gh installed from its signed apt repo"
else
  ok "gh already installed"
fi

# ── 6. bat / fd shims ────────────────────────
# Debian ships these as batcat/fdfind to avoid name clashes.
mkdir -p "$HOME/.local/bin"
if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
  ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"; ok "bat shim created"
fi
if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"; ok "fd shim created"
fi

# ── 7. Tools with no apt repository ──────────
# These four publish no apt repo anywhere, so each download is checked against
# the project's published SHA-256 before it is installed.

# ccmux — tmux.conf binds `prefix + a` to `ccmux picker`, and PowerKit shows
# its agent counts in the status line.
if ! command -v ccmux &>/dev/null; then
  info "Installing ccmux..."
  CCMUX_VERSION=$(curl -s https://api.github.com/repos/epilande/ccmux/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
  fetch_verified \
    "https://github.com/epilande/ccmux/releases/download/${CCMUX_VERSION}/ccmux-linux-x64" \
    "https://github.com/epilande/ccmux/releases/download/${CCMUX_VERSION}/checksums.txt"
  install -m 755 "$WORKDIR/ccmux-linux-x64" "$HOME/.local/bin/ccmux"
  ok "ccmux ${CCMUX_VERSION} installed"
else
  ok "ccmux already installed"
fi

# glab-tui — the `lgb` alias. musl build, so it ignores the host glibc.
if ! command -v glab-tui &>/dev/null; then
  info "Installing glab-tui..."
  GT_VERSION=$(curl -s https://api.github.com/repos/rcieri/glab-tui/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
  GT_ASSET="glab-tui-linux-amd64-musl.tar.gz"
  fetch_verified \
    "https://github.com/rcieri/glab-tui/releases/download/${GT_VERSION}/${GT_ASSET}" \
    "https://github.com/rcieri/glab-tui/releases/download/${GT_VERSION}/${GT_ASSET}.sha256"
  tar -xzf "$WORKDIR/${GT_ASSET}" -C "$WORKDIR"
  install -m 755 "$(find "$WORKDIR" -maxdepth 2 -name glab-tui -type f | head -1)" "$HOME/.local/bin/glab-tui"
  ok "glab-tui ${GT_VERSION} installed"
else
  ok "glab-tui already installed"
fi

# lazydocker — the `ldock` alias.
if ! command -v lazydocker &>/dev/null; then
  info "Installing lazydocker..."
  LD_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')
  fetch_verified \
    "https://github.com/jesseduffield/lazydocker/releases/download/v${LD_VERSION}/lazydocker_${LD_VERSION}_Linux_x86_64.tar.gz" \
    "https://github.com/jesseduffield/lazydocker/releases/download/v${LD_VERSION}/checksums.txt"
  tar -xzf "$WORKDIR/lazydocker_${LD_VERSION}_Linux_x86_64.tar.gz" -C "$WORKDIR" lazydocker
  install -m 755 "$WORKDIR/lazydocker" "$HOME/.local/bin/lazydocker"
  ok "lazydocker ${LD_VERSION} installed"
else
  ok "lazydocker already installed"
fi

# bun — referenced by the BUN_INSTALL block in .zshrc.
if [ ! -x "$HOME/.bun/bin/bun" ]; then
  info "Installing bun..."
  BUN_TAG=$(curl -s https://api.github.com/repos/oven-sh/bun/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
  fetch_verified \
    "https://github.com/oven-sh/bun/releases/download/${BUN_TAG}/bun-linux-x64.zip" \
    "https://github.com/oven-sh/bun/releases/download/${BUN_TAG}/SHASUMS256.txt"
  unzip -qo "$WORKDIR/bun-linux-x64.zip" -d "$WORKDIR"
  mkdir -p "$HOME/.bun/bin"
  install -m 755 "$WORKDIR/bun-linux-x64/bun" "$HOME/.bun/bin/bun"
  ok "bun ${BUN_TAG} installed"
else
  ok "bun already installed"
fi

# ── 8. zsh / tmux plugins (source checkouts) ──
# These are plugin sources read by zsh and tmux, not binaries; they are pinned
# by whatever the upstream default branch holds.
if [ ! -d "$HOME/.fzf-tab" ]; then
  info "Installing fzf-tab..."
  git clone --depth 1 https://github.com/Aloxaf/fzf-tab "$HOME/.fzf-tab"
  ok "fzf-tab installed"
else
  ok "fzf-tab already installed"
fi

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  info "Installing TPM..."
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  ok "TPM installed"
else
  ok "TPM already installed"
fi

# PowerKit is pinned so the two machines cannot drift apart again; bump this on
# both at once. v5 -> v7 was a breaking change, and .tmux.conf now uses the v7
# option names.
POWERKIT_VERSION="v7.4.0"
PK_DIR="$HOME/.tmux/plugins/tmux-powerkit"
if [ -d "$PK_DIR/.git" ]; then
  if [ "$(git -C "$PK_DIR" describe --tags 2>/dev/null)" != "$POWERKIT_VERSION" ]; then
    info "Pinning tmux-powerkit to $POWERKIT_VERSION..."
    git -C "$PK_DIR" fetch --tags --quiet origin 2>/dev/null || true
    git -C "$PK_DIR" checkout --quiet "$POWERKIT_VERSION" 2>/dev/null \
      && ok "tmux-powerkit pinned to $POWERKIT_VERSION" \
      || warn "could not pin tmux-powerkit to $POWERKIT_VERSION"
  else
    ok "tmux-powerkit already at $POWERKIT_VERSION"
  fi

  # PowerKit only loads plugins from its own src/plugins directory — there is no
  # custom-plugin-path option — so the ccmux plugin has to be symlinked in.
  # Without this the ccmux segment silently never appears.
  if [ -d "$DOTFILES_DIR/tmux/powerkit-plugins" ]; then
    for plug in "$DOTFILES_DIR"/tmux/powerkit-plugins/*.sh; do
      [ -e "$plug" ] || continue
      ln -sfn "$plug" "$PK_DIR/src/plugins/$(basename "$plug")"
      ok "linked custom powerkit plugin: $(basename "$plug")"
    done
  fi
fi

# ── 9. JetBrainsMono Nerd Font ───────────────
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  ok "Headless machine — skipping Nerd Font (your terminal on the client renders it)"
elif ! fc-list | grep -qi "JetBrainsMono"; then
  info "Installing JetBrainsMono Nerd Font..."
  FONT_VERSION=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${FONT_VERSION}/JetBrainsMono.tar.xz" -o "$WORKDIR/JetBrainsMono.tar.xz"
  mkdir -p "$HOME/.local/share/fonts"
  tar -xJf "$WORKDIR/JetBrainsMono.tar.xz" -C "$HOME/.local/share/fonts"
  fc-cache -f
  ok "JetBrainsMono Nerd Font installed"
else
  ok "JetBrainsMono Nerd Font already installed"
fi

# ── 10. Stow dotfiles ────────────────────────
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

# ── 11. Persistent tmux session (headless) ───
# Keeps session `main` alive across reboots so `mosh <host> -- tmux new -A -s
# main` always lands somewhere. enable-linger is what starts it at boot rather
# than at first login.
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
  info "Setting up persistent tmux session..."
  sudo loginctl enable-linger "$USER" || warn "enable-linger failed; session will not survive reboot"
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/tmux.service" <<UNIT
[Unit]
Description=persistent tmux session
After=default.target

[Service]
Type=forking
ExecStart=$(command -v tmux) new-session -d -s main
ExecStop=$(command -v tmux) kill-session -t main
Restart=on-failure

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload
  systemctl --user enable --now tmux.service || warn "could not start tmux.service"
  ok "Persistent tmux session enabled"
else
  ok "Not a headless systemd machine — skipping persistent tmux service"
fi

# ── Done ─────────────────────────────────────
echo ""
ok "Ubuntu dotfiles setup complete!"
echo ""
info "Next steps:"
info "  1. Run 'exec zsh' to reload your shell"
info "  2. Run 'tmux' then press 'C-a I' to install tmux plugins"
info "  3. Run 'nvim' — plugins will auto-install on first launch"
info "  4. Run 'mise install' to install tool versions (node, java, etc.)"
info "  5. Authenticate the CLIs you use: 'gh auth login', 'glab auth login'"
