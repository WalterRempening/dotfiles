#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# GitLab CI runner host — Ubuntu
#
# Turns this machine into a self-hosted runner for the iosefin group, honouring
# the docker contract documented in iosefin/ci-templates:
#
#   volumes = ["/certs/client", "/cache", "/var/run/docker.sock:/var/run/host-docker.sock"]
#
# The host socket goes at the NON-default /var/run/host-docker.sock because
# runner volumes are mounted into SERVICE containers too: a mount at the default
# path stops docker:dind creating its own socket ("device or resource busy") and
# breaks every .docker-dind job. Binding elsewhere lets .docker-host and
# .docker-dind share one runner. Do not "tidy" this path.
#
# Both Docker and gitlab-runner come from their upstream SIGNED apt repos.
#
# This script does NOT register runners — registration needs a token and is done
# separately, so re-running this is always safe.
# ──────────────────────────────────────────────

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*"; exit 1; }

[ "$(id -u)" -ne 0 ] || error "run as your normal user; the script calls sudo where needed"
ARCH="$(dpkg --print-architecture)"

# ── 1. Docker CE (upstream signed apt repo) ──
if ! command -v docker &>/dev/null; then
  info "Adding Docker's apt repository..."
  sudo install -dm 755 /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod 644 /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ok "Docker installed: $(docker --version)"
else
  ok "Docker already installed: $(docker --version)"
fi

# Ubuntu 26.04's codename may not have a Docker repo yet; fall back to the
# previous LTS pocket rather than failing, since Docker lags new releases.
if ! apt-cache policy docker-ce 2>/dev/null | grep -q Candidate; then
  warn "no docker-ce candidate for this release; check /etc/apt/sources.list.d/docker.list"
fi

sudo systemctl enable --now docker
ok "docker service: $(systemctl is-active docker)"

# Let the login user run docker without sudo (takes effect on next login).
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  sudo usermod -aG docker "$USER"
  warn "added $USER to the docker group — log out and back in for it to apply"
fi

# ── 2. gitlab-runner (upstream signed apt repo) ──
if ! command -v gitlab-runner &>/dev/null; then
  info "Adding the gitlab-runner apt repository..."
  curl -fsSL "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" \
    | sudo bash
  sudo apt-get install -y gitlab-runner
  ok "gitlab-runner installed: $(gitlab-runner --version | head -1)"
else
  ok "gitlab-runner already installed: $(gitlab-runner --version | head -1)"
fi

# ── 3. Global runner settings ────────────────
# concurrent is set from core count. The Mac runs 10 on 8 cores; this box has
# more, but Docker builds are IO- and RAM-hungry, so cap at cores/2 to leave
# headroom rather than maximising parallel jobs.
CORES="$(nproc)"
CONCURRENT=$(( CORES / 2 ))
[ "$CONCURRENT" -lt 4 ] && CONCURRENT=4

info "Setting concurrent=$CONCURRENT (host has $CORES cores)"
sudo gitlab-runner stop >/dev/null 2>&1 || true

CFG=/etc/gitlab-runner/config.toml
sudo mkdir -p /etc/gitlab-runner
if [ ! -f "$CFG" ]; then
  sudo tee "$CFG" >/dev/null <<TOML
# Managed by install-ci-runner.sh. Runner blocks are appended by
# \`gitlab-runner register\`; the settings above them are ours.
#
# CANONICAL DOCKER CONTRACT — every [runners.docker] must carry, verbatim:
#
#   volumes = ["/certs/client", "/cache", "/var/run/docker.sock:/var/run/host-docker.sock"]
#
# See iosefin/ci-templates/docker.yml for why the path is non-default.
#
# Unlike the M1 fleet there is deliberately NO DOCKER_DEFAULT_PLATFORM here:
# this host is x86_64, so linux/amd64 images run natively instead of under
# QEMU emulation. That is the whole point of moving the fleet here.

concurrent = $CONCURRENT
check_interval = 3
connection_max_age = "15m0s"
shutdown_timeout = 0

[session_server]
  session_timeout = 1800
TOML
  ok "wrote $CFG"
else
  sudo sed -i -E "s/^concurrent = .*/concurrent = $CONCURRENT/" "$CFG"
  ok "updated concurrent in the existing $CFG"
fi

sudo gitlab-runner start >/dev/null 2>&1 || true

# ── 4. Cache directory ───────────────────────
sudo mkdir -p /cache
sudo chmod 777 /cache
ok "/cache ready ($(df -h /cache | awk 'NR==2{print $4}') free)"

# ── 5. bun + omp, system-wide ────────────────
# The omp-review jobs run on the SHELL executor, which executes as the
# `gitlab-runner` user — not as you. /home/wrd is mode 750, so anything under
# ~/.bun is unreachable from a job: omp's `#!/usr/bin/env bun` shebang fails
# with "env: 'bun': No such file or directory", which looks like a PATH problem
# but is really a permissions one.
#
# Installing both under /usr/local keeps them readable by every user without
# opening up a home directory, and avoids running CI jobs as a human account
# that holds SSH keys and a glab token.
if [ -x "$HOME/.bun/bin/bun" ]; then
  if [ ! -x /usr/local/bin/bun ]; then
    info "Installing bun system-wide..."
    sudo install -m 755 "$HOME/.bun/bin/bun" /usr/local/bin/bun
    ok "bun -> /usr/local/bin/bun ($(/usr/local/bin/bun --version))"
  else
    ok "system bun already present ($(/usr/local/bin/bun --version))"
  fi

  # BUN_INSTALL controls where `bun install -g` puts things: binaries land in
  # $BUN_INSTALL/bin, packages in $BUN_INSTALL/install/global.
  if [ ! -x /usr/local/bin/omp ]; then
    info "Installing omp system-wide (this pulls a large dependency tree)..."
    sudo env BUN_INSTALL=/usr/local /usr/local/bin/bun install -g @oh-my-pi/pi-coding-agent
    sudo chmod -R a+rX /usr/local/install/global 2>/dev/null || true
    if [ -x /usr/local/bin/omp ]; then
      ok "omp -> /usr/local/bin/omp"
    else
      warn "omp did not land in /usr/local/bin — check the bun output above"
    fi
  else
    ok "system omp already present"
  fi

  # Prove it works as the runner user, which is the only test that matters.
  if sudo -u gitlab-runner env PATH=/usr/local/bin:/usr/bin:/bin omp --version >/dev/null 2>&1; then
    ok "omp runs as the gitlab-runner user"
  else
    warn "omp is NOT runnable as gitlab-runner — omp-review jobs would fail"
  fi
else
  warn "no ~/.bun/bin/bun found; skipping the bun/omp step"
fi

# ── Done ─────────────────────────────────────
echo ""
ok "Runner host ready."
echo ""
info "Next: register runners (done from the laptop, needs a token)."
info "Every registration MUST pass:"
info '  --docker-volumes "/certs/client"'
info '  --docker-volumes "/cache"'
info '  --docker-volumes "/var/run/docker.sock:/var/run/host-docker.sock"'
