#!/usr/bin/env bash
# iosefin-workspace.sh — Recreate the Iosefin tmux workspace
# Usage: ./iosefin-workspace.sh [-p|--project NAME]
#
# - Creates project sessions with their Main window layout
# - Auto-detects git worktrees and creates a window per worktree
# - Copies env files from main worktree to all worktrees
# - For dual-component projects (Sbs, Unecre), pairs worktrees sharing
#   the same parent directory into a 3-pane window (left: UI/API, right: parent)

set -euo pipefail
trap 'echo "ERROR at line $LINENO (exit $?)" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/iosefin-lib.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

SELECTED_PROJECT=""

usage() {
  cat <<EOF
Usage: iosefin up [options]
  -p, --project NAME   Start only the named project (case-insensitive).
                       Bypasses the default-exclusion list.
  -h, --help           Show this help.

Known projects:    Buakfieren, Hopninj, Sbs, Senova, Unecre, Kassa, Infra, Chopin, Tjikett
Default-excluded:  Buakfieren, Unecre, Chopin, Tjikett  (run with -p to start them)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)
      SELECTED_PROJECT="${2:-}"
      [ -z "$SELECTED_PROJECT" ] && { usage >&2; exit 1; }
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

ALL_PROJECTS=(Buakfieren Hopninj Sbs Senova Unecre Kassa Infra Chopin Tjikett)
DEFAULT_EXCLUDED=(Buakfieren Unecre Chopin Tjikett)

# ---------------------------------------------------------------------------
# tmux helpers
# ---------------------------------------------------------------------------

new_session() {
  local name="$1" dir="$2"
  if tmux has-session -t "$name" 2>/dev/null; then
    echo "  Session '$name' already exists — skipping."
    return 1
  fi
  tmux new-session -d -s "$name" -n Main -c "$dir"
  if $_init_created; then
    tmux kill-session -t _init 2>/dev/null || true
    _init_created=false
  fi
}

# Bootstrap the server so we can read config (need at least one session)
_init_created=false
if ! tmux has-session 2>/dev/null; then
  tmux new-session -d -s _init
  _init_created=true
fi

# Respect tmux base-index settings
P0=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 0)
P1=$((P0 + 1))
P2=$((P0 + 2))

# Create a window with 2 vertical panes, both in the same directory
add_worktree_window() {
  local session="$1" wt_path="$2" wt_name="${3:-$(basename "$2")}"
  echo "    + window '$wt_name' (2 panes) → $wt_path"
  tmux new-window -t "$session" -n "$wt_name" -c "$wt_path"
  tmux split-window -h -t "$session:$wt_name" -c "$wt_path"
  tmux select-pane -t "$session:$wt_name.$P1"
}

# Create a window with 3 panes: left split (API top, UI bottom) + right full (parent, active)
add_paired_worktree_window() {
  local session="$1" ui_path="$2" api_path="$3" wt_name="$4"
  local parent_dir
  parent_dir=$(dirname "$ui_path")
  echo "    + window '$wt_name' (3 panes, paired) → api: $api_path / ui: $ui_path"
  tmux new-window -t "$session" -n "$wt_name" -c "$api_path"
  tmux split-window -h -t "$session:$wt_name.$P0" -c "$parent_dir"
  tmux split-window -v -t "$session:$wt_name.$P0" -c "$ui_path"
  tmux select-pane -t "$session:$wt_name.$P2"
}

# Process worktrees for a single repo.
add_repo_worktrees() {
  local session="$1" repo="$2"
  local all_wts processed=""

  all_wts=$(get_worktrees "$repo")
  [ -z "$all_wts" ] && return 0

  while IFS= read -r wt_path; do
    [ -z "$wt_path" ] && continue
    local name
    name=$(basename "$wt_path")

    if [[ "$name" == ui-* ]]; then
      local stripped="${name#ui-}"
      local api_match=""
      while IFS= read -r candidate; do
        [ -z "$candidate" ] && continue
        if [ "$(basename "$candidate")" = "api-$stripped" ]; then
          api_match="$candidate"
          break
        fi
      done <<< "$all_wts"

      if [ -n "$api_match" ]; then
        add_paired_worktree_window "$session" "$wt_path" "$api_match" "$stripped"
        processed="$processed|$wt_path|$api_match"
      else
        add_worktree_window "$session" "$wt_path" "$stripped"
        processed="$processed|$wt_path"
      fi
    fi
  done <<< "$all_wts"

  while IFS= read -r wt_path; do
    [ -z "$wt_path" ] && continue
    [[ "$processed" == *"|$wt_path"* ]] && continue
    local name
    name=$(basename "$wt_path")
    if [[ "$name" == api-* ]]; then
      add_worktree_window "$session" "$wt_path" "${name#api-}"
    else
      add_worktree_window "$session" "$wt_path"
    fi
    processed="$processed|$wt_path"
  done <<< "$all_wts"
}

# Process worktrees for a dual-component project (separate UI + API repos).
# Pairs worktrees that share the same parent directory into a 3-pane window.
add_dual_repo_worktrees() {
  local session="$1" ui_repo="$2" api_repo="$3"
  local ui_wts api_wts

  ui_wts=$(get_worktrees "$ui_repo")
  api_wts=$(get_worktrees "$api_repo")
  [ -z "$ui_wts" ] && [ -z "$api_wts" ] && return 0

  # Index API worktrees by parent directory
  declare -A api_by_parent
  if [ -n "$api_wts" ]; then
    while IFS= read -r api_path; do
      [ -z "$api_path" ] && continue
      api_by_parent["$(dirname "$api_path")"]="$api_path"
    done <<< "$api_wts"
  fi

  local paired_api=""

  # Match UI worktrees with API worktrees in the same parent directory
  if [ -n "$ui_wts" ]; then
    while IFS= read -r ui_path; do
      [ -z "$ui_path" ] && continue
      local parent_dir wt_name
      parent_dir=$(dirname "$ui_path")
      wt_name=$(basename "$parent_dir")

      if [ -n "${api_by_parent[$parent_dir]+x}" ]; then
        add_paired_worktree_window "$session" "$ui_path" "${api_by_parent[$parent_dir]}" "$wt_name"
        paired_api="$paired_api|${api_by_parent[$parent_dir]}"
      else
        add_worktree_window "$session" "$ui_path" "$wt_name"
      fi
    done <<< "$ui_wts"
  fi

  # Add remaining unpaired API worktrees
  if [ -n "$api_wts" ]; then
    while IFS= read -r api_path; do
      [ -z "$api_path" ] && continue
      [[ "$paired_api" == *"|$api_path"* ]] && continue
      local wt_name
      wt_name=$(basename "$(dirname "$api_path")")
      add_worktree_window "$session" "$api_path" "$wt_name"
    done <<< "$api_wts"
  fi
}

# ===========================================================================
# Project session functions
# ===========================================================================

start_buakfieren() {
  echo "Buakfieren"
  if new_session "Buakfieren" "$BASE/menoserv/buakfieren-app"; then
    tmux split-window -h -t "Buakfieren:Main" -c "$BASE/menoserv/buakfieren-app"
    tmux select-pane  -t "Buakfieren:Main.$P1"
    add_repo_worktrees "Buakfieren" "$BASE/menoserv/buakfieren-app"
    tmux select-window -t "Buakfieren:Main"
  fi
  sync_env "$BASE/menoserv/buakfieren-app"
}

start_hopninj() {
  echo "Hopninj"
  if new_session "Hopninj" "$BASE/hopninj/skola-hopninj-app"; then
    tmux split-window -h -t "Hopninj:Main" -c "$BASE/hopninj/skola-hopninj-app"
    tmux select-pane  -t "Hopninj:Main.$P1"
    add_repo_worktrees "Hopninj" "$BASE/hopninj/skola-hopninj-app"
    tmux select-window -t "Hopninj:Main"
  fi
  sync_env "$BASE/hopninj/skola-hopninj-app"
}

start_sbs() {
  echo "Sbs"
  if new_session "Sbs" "$BASE/sbs/skola-api"; then
    tmux split-window -h -t "Sbs:Main.$P0" -c "$BASE/sbs"
    tmux split-window -v -t "Sbs:Main.$P0" -c "$BASE/sbs/skola-ui"
    tmux select-pane -t "Sbs:Main.$P2"
    add_dual_repo_worktrees "Sbs" "$BASE/sbs/skola-ui" "$BASE/sbs/skola-api"
    local extra_repo extra_name
    for extra_repo in "$BASE/sbs/sbs-android" "$BASE/sbs/sbs-ios"; do
      [ -d "$extra_repo/.git" ] || continue
      extra_name=$(basename "$extra_repo")
      echo "    + window '$extra_name' (2 panes) → $extra_repo"
      tmux new-window -t "Sbs" -n "$extra_name" -c "$extra_repo"
      tmux split-window -h -t "Sbs:$extra_name" -c "$extra_repo"
      tmux select-pane  -t "Sbs:$extra_name.$P1"
      add_repo_worktrees "Sbs" "$extra_repo"
    done
    tmux select-window -t "Sbs:Main"
  fi
  sync_env "$BASE/sbs/skola-api"
  sync_env "$BASE/sbs/skola-ui"
  [ -d "$BASE/sbs/sbs-android/.git" ] && sync_env "$BASE/sbs/sbs-android"
  [ -d "$BASE/sbs/sbs-ios/.git" ] && sync_env "$BASE/sbs/sbs-ios"
}

start_senova() {
  echo "Senova"
  if new_session "Senova" "$BASE/senova/senova-pos"; then
    tmux split-window -h -t "Senova:Main" -c "$BASE/senova/senova-pos"
    tmux select-pane  -t "Senova:Main.$P1"
    add_repo_worktrees "Senova" "$BASE/senova/senova-pos"
    tmux select-window -t "Senova:Main"
  fi
  sync_env "$BASE/senova/senova-pos"
}

start_unecre() {
  echo "Unecre"
  if new_session "Unecre" "$BASE/unecre/web_point_of_sale"; then
    tmux split-window -h -t "Unecre:Main.$P0" -c "$BASE/unecre"
    tmux split-window -v -t "Unecre:Main.$P0" -c "$BASE/unecre/api_point_of_sale"
    tmux select-pane -t "Unecre:Main.$P2"
    add_dual_repo_worktrees "Unecre" "$BASE/unecre/web_point_of_sale" "$BASE/unecre/api_point_of_sale"
    tmux select-window -t "Unecre:Main"
  fi
  sync_env "$BASE/unecre/web_point_of_sale"
  sync_env "$BASE/unecre/api_point_of_sale"
}

start_kassa() {
  echo "Kassa"
  local KASSA_DIR="$BASE/kassa"
  local KASSA_REPOS
  mapfile -t KASSA_REPOS < <(discover_repos "$KASSA_DIR")
  if [ ${#KASSA_REPOS[@]} -eq 0 ]; then
    echo "  No git repos found under $KASSA_DIR — skipping."
    return 0
  fi
  if new_session "Kassa" "${KASSA_REPOS[0]}"; then
    tmux rename-window -t "Kassa:Main" "$(basename "${KASSA_REPOS[0]}")"
    tmux split-window -h -t "Kassa" -c "${KASSA_REPOS[0]}"
    tmux select-pane  -t "Kassa.$P1"
    add_repo_worktrees "Kassa" "${KASSA_REPOS[0]}"
    local repo local_name
    for repo in "${KASSA_REPOS[@]:1}"; do
      local_name=$(basename "$repo")
      echo "    + window '$local_name' (2 panes) → $repo"
      tmux new-window -t "Kassa" -n "$local_name" -c "$repo"
      tmux split-window -h -t "Kassa:$local_name" -c "$repo"
      tmux select-pane  -t "Kassa:$local_name.$P1"
      add_repo_worktrees "Kassa" "$repo"
    done
    tmux select-window -t "Kassa:$(basename "${KASSA_REPOS[0]}")"
  fi
  local repo
  for repo in "${KASSA_REPOS[@]}"; do
    sync_env "$repo"
  done
}

start_chopin() {
  echo "Chopin"
  if new_session "Chopin" "$BASE/chopin/chopin-app"; then
    tmux split-window -h -t "Chopin:Main" -c "$BASE/chopin/chopin-app"
    tmux select-pane  -t "Chopin:Main.$P1"
    add_repo_worktrees "Chopin" "$BASE/chopin/chopin-app"
    tmux select-window -t "Chopin:Main"
  fi
  sync_env "$BASE/chopin/chopin-app"
}

start_tjikett() {
  echo "Tjikett"
  if new_session "Tjikett" "$BASE/tjikett/tjikett-app"; then
    tmux split-window -h -t "Tjikett:Main" -c "$BASE/tjikett/tjikett-app"
    tmux select-pane  -t "Tjikett:Main.$P1"
    add_repo_worktrees "Tjikett" "$BASE/tjikett/tjikett-app"
    tmux select-window -t "Tjikett:Main"
  fi
  sync_env "$BASE/tjikett/tjikett-app"
}

start_infra() {
  echo "Infra"
  local INFRA_DIR="$BASE/infra"
  local INFRA_REPOS
  mapfile -t INFRA_REPOS < <(discover_repos "$INFRA_DIR")
  if [ ${#INFRA_REPOS[@]} -eq 0 ]; then
    echo "  No git repos found under $INFRA_DIR — skipping."
    return 0
  fi
  if new_session "Infra" "${INFRA_REPOS[0]}"; then
    tmux rename-window -t "Infra:Main" "$(basename "${INFRA_REPOS[0]}")"
    tmux split-window -h -t "Infra" -c "${INFRA_REPOS[0]}"
    tmux select-pane  -t "Infra.$P1"
    add_repo_worktrees "Infra" "${INFRA_REPOS[0]}"
    local repo local_name
    for repo in "${INFRA_REPOS[@]:1}"; do
      local_name=$(basename "$repo")
      echo "    + window '$local_name' (2 panes) → $repo"
      tmux new-window -t "Infra" -n "$local_name" -c "$repo"
      tmux split-window -h -t "Infra:$local_name" -c "$repo"
      tmux select-pane  -t "Infra:$local_name.$P1"
      add_repo_worktrees "Infra" "$repo"
    done
    tmux select-window -t "Infra:$(basename "${INFRA_REPOS[0]}")"
  fi
  local repo
  for repo in "${INFRA_REPOS[@]}"; do
    sync_env "$repo"
  done
}

# ===========================================================================
# Dispatcher
# ===========================================================================

in_array() {  # in_array NEEDLE ARRAY...
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [[ "${item,,}" == "${needle,,}" ]] && return 0
  done
  return 1
}

run_project() {
  case "${1,,}" in
    buakfieren) start_buakfieren ;;
    hopninj)    start_hopninj ;;
    sbs)        start_sbs ;;
    senova)     start_senova ;;
    unecre)     start_unecre ;;
    kassa)      start_kassa ;;
    infra)      start_infra ;;
    chopin)     start_chopin ;;
    tjikett)    start_tjikett ;;
    *) echo "Unknown project: $1" >&2; echo "Known: ${ALL_PROJECTS[*]}" >&2; exit 1 ;;
  esac
}

if [ -n "$SELECTED_PROJECT" ]; then
  if ! in_array "$SELECTED_PROJECT" "${ALL_PROJECTS[@]}"; then
    echo "Unknown project: $SELECTED_PROJECT" >&2
    echo "Known: ${ALL_PROJECTS[*]}" >&2
    exit 1
  fi
  run_project "$SELECTED_PROJECT"
else
  for proj in "${ALL_PROJECTS[@]}"; do
    if in_array "$proj" "${DEFAULT_EXCLUDED[@]}"; then
      echo "(skipping $proj — default-excluded; run with -p $proj to start)"
      continue
    fi
    run_project "$proj"
  done
fi

# Safety net: if we created _init and nothing ever called new_session
# successfully (e.g. every project's session already existed), tear it down.
if $_init_created; then
  tmux kill-session -t _init 2>/dev/null || true
  _init_created=false
fi

echo ""
echo "Workspace ready!"
tmux list-sessions
echo ""
echo "Attach with:  tmux attach -t Hopninj"
