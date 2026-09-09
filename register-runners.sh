#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Register this host's runners against the iosefin group.
#
# Runs ON the runner host and uses its own authenticated `glab`, so the runner
# token is created and consumed locally and never travels.
#
# Idempotent: a runner whose description already exists in the group is skipped.
# ──────────────────────────────────────────────

GROUP_ID=133019011
GITLAB_URL="https://gitlab.com"

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*"; exit 1; }

command -v glab >/dev/null || error "glab is not installed"
glab auth status >/dev/null 2>&1 || error "glab is not authenticated — run: glab auth login"
command -v gitlab-runner >/dev/null || error "gitlab-runner is not installed"

existing_ids() {
  glab api "groups/$GROUP_ID/runners?per_page=100" 2>/dev/null \
    | python3 -c "import json,sys; print('\n'.join(r.get('description','') for r in json.load(sys.stdin)))"
}

# create_runner <description> <tag_list csv> <run_untagged true|false>
# Prints the new runner's auth token on stdout. Nothing else goes to stdout.
create_runner() {
  local desc=$1 tags=$2 untagged=$3
  glab api --method POST "user/runners" \
    -f "runner_type=group_type" \
    -f "group_id=$GROUP_ID" \
    -f "description=$desc" \
    -f "tag_list=$tags" \
    -f "run_untagged=$untagged" \
    -f "locked=false" \
    2>/dev/null \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
if 'token' not in d:
    sys.stderr.write('API error: '+json.dumps(d)[:300]+'\n'); sys.exit(1)
print(d['token'])"
}

# ── 1. Docker runner — takes over as the default for untagged jobs ──────────
DOCKER_DESC="t14-docker (iosefin)"
if existing_ids | grep -qxF "$DOCKER_DESC"; then
  ok "already registered: $DOCKER_DESC"
else
  info "Creating group runner: $DOCKER_DESC"
  TOKEN="$(create_runner "$DOCKER_DESC" "t14,linux,docker" "true")"
  [ -n "$TOKEN" ] || error "no token returned"

  # The three volumes are the canonical contract from iosefin/ci-templates.
  # host-docker.sock is deliberately non-default so .docker-dind can still
  # create its own socket in service containers.
  sudo gitlab-runner register \
    --non-interactive \
    --url "$GITLAB_URL" \
    --token "$TOKEN" \
    --name "$DOCKER_DESC" \
    --executor docker \
    --docker-image "docker:24" \
    --docker-privileged \
    --docker-pull-policy "if-not-present" \
    --docker-volumes "/certs/client" \
    --docker-volumes "/cache" \
    --docker-volumes "/var/run/docker.sock:/var/run/host-docker.sock"
  unset TOKEN
  ok "registered $DOCKER_DESC"
fi

# ── 2. Shell runner — omp-review ────────────────────────────────────────────
# Registered WITHOUT the omp-review tag on purpose. Adding it here while the
# Mac's shell runner still carries the same tag would make review jobs race
# between two hosts. Move the tag deliberately, once MINIMAX_API_KEY exists as
# a group variable: add it here, remove it there.
SHELL_DESC="t14-shell (iosefin)"
if existing_ids | grep -qxF "$SHELL_DESC"; then
  ok "already registered: $SHELL_DESC"
else
  info "Creating group runner: $SHELL_DESC"
  TOKEN="$(create_runner "$SHELL_DESC" "t14-shell" "false")"
  [ -n "$TOKEN" ] || error "no token returned"
  sudo gitlab-runner register \
    --non-interactive \
    --url "$GITLAB_URL" \
    --token "$TOKEN" \
    --name "$SHELL_DESC" \
    --executor shell \
    --shell bash
  unset TOKEN
  ok "registered $SHELL_DESC"
fi

sudo gitlab-runner restart >/dev/null 2>&1 || sudo systemctl restart gitlab-runner
ok "gitlab-runner restarted"

echo ""
info "Registered runners in the group:"
glab api "groups/$GROUP_ID/runners?per_page=100" 2>/dev/null | python3 -c "
import json,sys
for r in json.load(sys.stdin):
    print(f\"  {r['id']:>9}  {r.get('description','')!r:44} online={r.get('online')}\")"
