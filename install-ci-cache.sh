#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# CI cache layer for the runner host.
#
# Two pieces, both local, both aimed at the same problem: this box has a
# fixed-quality uplink, so anything fetched once should never be fetched again.
#
#   1. Registry pull-through cache  — Docker Hub images served from local disk.
#   2. MinIO distributed cache      — ONE shared runner cache instead of a
#                                     separate local volume per project per
#                                     concurrent slot.
#
# On (2): GitLab's docs are explicit that the Docker executor's local cache is
# not supported for concurrent access. With concurrent=8 across 14 projects a
# pipeline often lands on a slot whose cache is cold. An S3-compatible backend
# on localhost fixes that with no network cost.
#
# Changes nothing in any project's .gitlab-ci.yml.
# ──────────────────────────────────────────────

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*"; exit 1; }

[ "$(id -u)" -ne 0 ] || error "run as your normal user; the script calls sudo where needed"
command -v docker >/dev/null || error "docker is not installed — run install-ci-runner.sh first"

BRIDGE_IP="$(ip -4 addr show docker0 | grep -oE 'inet [0-9.]+' | awk '{print $2}')"
[ -n "$BRIDGE_IP" ] || error "could not determine the docker0 bridge IP"
info "docker bridge: $BRIDGE_IP"

# ── 1. Registry pull-through cache ───────────
# NOTE: dockerd's registry-mirrors applies to Docker Hub ONLY. Images from
# registry.gitlab.com are unaffected (they come from GitLab anyway). Images
# pulled *inside* a dind service also bypass this, because that daemon has its
# own config — another reason to move Testcontainers onto the host daemon.
if ! docker ps --format '{{.Names}}' | grep -qx registry-mirror; then
  info "Starting the Docker Hub pull-through cache..."
  docker rm -f registry-mirror >/dev/null 2>&1 || true
  docker volume create registry-mirror-data >/dev/null
  docker run -d --restart always --name registry-mirror \
    -p 127.0.0.1:5000:5000 \
    -v registry-mirror-data:/var/lib/registry \
    -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
    -e REGISTRY_STORAGE_DELETE_ENABLED=true \
    registry:2 >/dev/null
  ok "registry-mirror running on 127.0.0.1:5000"
else
  ok "registry-mirror already running"
fi

# Point the host daemon at it.
DAEMON=/etc/docker/daemon.json
if ! sudo test -f "$DAEMON" || ! sudo grep -q "registry-mirrors" "$DAEMON" 2>/dev/null; then
  info "Configuring dockerd to use the mirror..."
  sudo mkdir -p /etc/docker
  if sudo test -f "$DAEMON"; then
    sudo cp "$DAEMON" "${DAEMON}.bak"
    warn "existing daemon.json backed up to ${DAEMON}.bak"
  fi
  sudo tee "$DAEMON" >/dev/null <<JSON
{
  "registry-mirrors": ["http://127.0.0.1:5000"]
}
JSON
  sudo systemctl restart docker
  ok "dockerd restarted with the mirror configured"
else
  ok "dockerd already points at a registry mirror"
fi

# ── 2. MinIO — shared runner cache ───────────
CREDS=/etc/gitlab-runner/minio.env
if ! sudo test -f "$CREDS"; then
  info "Generating MinIO credentials..."
  sudo mkdir -p /etc/gitlab-runner
  # Generated on this host and never leaves it.
  sudo tee "$CREDS" >/dev/null <<ENV
MINIO_ROOT_USER=ci-cache
MINIO_ROOT_PASSWORD=$(openssl rand -base64 30 | tr -d '/+=' | head -c 32)
ENV
  sudo chmod 600 "$CREDS"
  ok "credentials written to $CREDS (root-only)"
else
  ok "reusing existing MinIO credentials"
fi

MINIO_USER="$(sudo grep '^MINIO_ROOT_USER=' "$CREDS" | cut -d= -f2)"
MINIO_PASS="$(sudo grep '^MINIO_ROOT_PASSWORD=' "$CREDS" | cut -d= -f2)"

if ! docker ps --format '{{.Names}}' | grep -qx minio-cache; then
  info "Starting MinIO..."
  docker rm -f minio-cache >/dev/null 2>&1 || true
  docker volume create minio-cache-data >/dev/null
  docker run -d --restart always --name minio-cache \
    -p 9000:9000 -p 127.0.0.1:9001:9001 \
    -v minio-cache-data:/data \
    -e "MINIO_ROOT_USER=$MINIO_USER" \
    -e "MINIO_ROOT_PASSWORD=$MINIO_PASS" \
    minio/minio server /data --console-address ":9001" >/dev/null
  ok "minio-cache running on :9000 (console 127.0.0.1:9001)"
else
  ok "minio-cache already running"
fi

info "Waiting for MinIO to be ready..."
for _ in $(seq 1 30); do
  curl -sf "http://127.0.0.1:9000/minio/health/ready" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "http://127.0.0.1:9000/minio/health/ready" >/dev/null 2>&1 \
  || error "MinIO did not become ready"
ok "MinIO ready"

info "Ensuring the runner-cache bucket exists..."
docker run --rm --network host -e MC_HOST_local="http://${MINIO_USER}:${MINIO_PASS}@127.0.0.1:9000" \
  minio/mc mb --ignore-existing local/runner-cache >/dev/null 2>&1 \
  && ok "bucket runner-cache present" \
  || warn "could not create the bucket — check MinIO logs"

# ── 3. Point the runner at the shared cache ──
# BucketLocation must be us-east-1: MinIO reports that region regardless.
# ServerAddress is the bridge IP, not 127.0.0.1 — the cache archiver runs in a
# helper CONTAINER, where localhost is the container itself.
CFG=/etc/gitlab-runner/config.toml
if sudo grep -q 'Type = "s3"' "$CFG" 2>/dev/null; then
  ok "runner cache already configured for s3"
else
  info "Adding the shared cache to the docker runner..."
  sudo cp "$CFG" "${CFG}.bak"
  sudo python3 - "$CFG" "$BRIDGE_IP" "$MINIO_USER" "$MINIO_PASS" <<'PY'
import sys, re
cfg, bridge, user, pw = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
src = open(cfg).read()

block = f'''  [runners.cache]
    Type = "s3"
    Shared = true
    [runners.cache.s3]
      ServerAddress = "{bridge}:9000"
      AccessKey = "{user}"
      SecretKey = "{pw}"
      BucketName = "runner-cache"
      BucketLocation = "us-east-1"
      Insecure = true
'''

lines = src.splitlines(keepends=True)
out, in_docker_runner, done = [], False, False
for line in lines:
    if line.startswith('[[runners]]'):
        in_docker_runner = False
    if re.match(r'\s*name = ".*t14-docker.*"', line):
        in_docker_runner = True
    # Insert immediately before this runner's [runners.docker] sub-table.
    if in_docker_runner and not done and line.strip() == '[runners.docker]':
        out.append(block)
        done = True
    out.append(line)

if not done:
    sys.stderr.write("could not find the t14-docker [runners.docker] section\n")
    sys.exit(1)
open(cfg, 'w').write(''.join(out))
print("inserted [runners.cache]")
PY
  sudo gitlab-runner restart >/dev/null 2>&1 || sudo systemctl restart gitlab-runner
  ok "runner restarted with the shared cache"
fi

# ── Done ─────────────────────────────────────
echo ""
ok "Cache layer ready."
echo ""
info "Verify the mirror is actually being used:"
info "  curl -s http://127.0.0.1:5000/v2/_catalog"
info "MinIO console (localhost only): http://127.0.0.1:9001"
