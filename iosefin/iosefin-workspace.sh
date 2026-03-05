#!/usr/bin/env bash
# iosefin-workspace.sh — Recreate the Iosefin tmux workspace
# Usage: ./iosefin-workspace.sh
#
# - Creates all project sessions with their Main window layout
# - Auto-detects git worktrees and creates a window per worktree
# - Copies env files from main worktree to all worktrees
# - For dual-component projects (Unecre), pairs ui-*/api-* worktrees
#   into a 3-pane window (left split: UI top / API bottom + right full)

set -euo pipefail
trap 'echo "ERROR at line $LINENO (exit $?)" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/iosefin-lib.sh"

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

# Create a window with 3 panes: left split (UI top, API bottom) + right full (parent, active)
add_paired_worktree_window() {
  local session="$1" ui_path="$2" api_path="$3" wt_name="$4"
  local parent_dir
  parent_dir=$(dirname "$ui_path")
  echo "    + window '$wt_name' (3 panes, paired) → ui: $ui_path / api: $api_path"
  tmux new-window -t "$session" -n "$wt_name" -c "$ui_path"
  tmux split-window -h -t "$session:$wt_name.$P0" -c "$parent_dir"
  tmux split-window -v -t "$session:$wt_name.$P0" -c "$api_path"
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
add_dual_repo_worktrees() {
  local session="$1" ui_repo="$2" api_repo="$3"
  local ui_wts api_wts processed=""

  ui_wts=$(get_worktrees "$ui_repo")
  api_wts=$(get_worktrees "$api_repo")
  [ -z "$ui_wts" ] && [ -z "$api_wts" ] && return 0

  if [ -n "$ui_wts" ]; then
    while IFS= read -r ui_path; do
      [ -z "$ui_path" ] && continue
      local ui_name
      ui_name=$(basename "$ui_path")

      if [[ "$ui_name" == ui-* ]]; then
        local stripped="${ui_name#ui-}"
        local api_path=""
        if [ -n "$api_wts" ]; then
          while IFS= read -r candidate; do
            [ -z "$candidate" ] && continue
            if [ "$(basename "$candidate")" = "api-$stripped" ]; then
              api_path="$candidate"
              break
            fi
          done <<< "$api_wts"
        fi

        if [ -n "$api_path" ]; then
          add_paired_worktree_window "$session" "$ui_path" "$api_path" "$stripped"
          processed="$processed|$api_path"
        else
          add_worktree_window "$session" "$ui_path" "$stripped"
        fi
      else
        add_worktree_window "$session" "$ui_path"
      fi
    done <<< "$ui_wts"
  fi

  if [ -n "$api_wts" ]; then
    while IFS= read -r api_path; do
      [ -z "$api_path" ] && continue
      [[ "$processed" == *"|$api_path"* ]] && continue
      local api_name
      api_name=$(basename "$api_path")
      if [[ "$api_name" == api-* ]]; then
        add_worktree_window "$session" "$api_path" "${api_name#api-}"
      else
        add_worktree_window "$session" "$api_path"
      fi
    done <<< "$api_wts"
  fi
}

# ===========================================================================
# 1. Buakfieren — 2 panes, vertical split
# ===========================================================================
echo "Buakfieren"
if new_session "Buakfieren" "$BASE/menoserv/buakfieren-app"; then
  if $_init_created; then
    tmux kill-session -t _init 2>/dev/null || true
    _init_created=false
  fi
  tmux split-window -h -t "Buakfieren:Main" -c "$BASE/menoserv/buakfieren-app"
  tmux select-pane  -t "Buakfieren:Main.$P1"
  add_repo_worktrees "Buakfieren" "$BASE/menoserv/buakfieren-app"
  tmux select-window -t "Buakfieren:Main"
fi
sync_env "$BASE/menoserv/buakfieren-app"

# ===========================================================================
# 2. Hopninj — 2 panes, vertical split
# ===========================================================================
echo "Hopninj"
if new_session "Hopninj" "$BASE/hopninj/skola-hopninj-app"; then
  tmux split-window -h -t "Hopninj:Main" -c "$BASE/hopninj/skola-hopninj-app"
  tmux select-pane  -t "Hopninj:Main.$P1"
  add_repo_worktrees "Hopninj" "$BASE/hopninj/skola-hopninj-app"
  tmux select-window -t "Hopninj:Main"
fi
sync_env "$BASE/hopninj/skola-hopninj-app"

# ===========================================================================
# 3. Sbs — 3 panes (left split: api/ui, right full: parent dir)
# ===========================================================================
echo "Sbs"
if new_session "Sbs" "$BASE/sbs/skola-api"; then
  tmux split-window -h -t "Sbs:Main.$P0" -c "$BASE/sbs"
  tmux split-window -v -t "Sbs:Main.$P0" -c "$BASE/sbs/skola-ui"
  tmux select-pane -t "Sbs:Main.$P2"
  add_dual_repo_worktrees "Sbs" "$BASE/sbs/skola-ui" "$BASE/sbs/skola-api"
  tmux select-window -t "Sbs:Main"
fi
sync_env "$BASE/sbs/skola-api"
sync_env "$BASE/sbs/skola-ui"

# ===========================================================================
# 4. Senova — 2 panes, vertical split
# ===========================================================================
echo "Senova"
if new_session "Senova" "$BASE/senova/senova-pos"; then
  tmux split-window -h -t "Senova:Main" -c "$BASE/senova/senova-pos"
  tmux select-pane  -t "Senova:Main.$P1"
  add_repo_worktrees "Senova" "$BASE/senova/senova-pos"
  tmux select-window -t "Senova:Main"
fi
sync_env "$BASE/senova/senova-pos"

# ===========================================================================
# 5. Unecre — 3 panes (left split: web/api, right full: parent dir)
# ===========================================================================
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

# ===========================================================================
echo ""
echo "Workspace ready!"
tmux list-sessions
echo ""
echo "Attach with:  tmux attach -t Hopninj"
