#!/usr/bin/env bash
# iosefin-sync-worktrees.sh — Create tmux windows for new worktrees + sync env files
# Usage: Run from inside a tmux session (or bind to a key)
#
# Detects new git worktrees, creates windows, copies env files from main worktree.
# For dual-component sessions (Sbs, Unecre), pairs ui-*/api-* worktrees.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/iosefin-lib.sh"

# Must be inside tmux
if [ -z "${TMUX:-}" ]; then
  echo "Error: not inside a tmux session." >&2
  exit 1
fi

SESSION=$(tmux display-message -p '#{session_name}')

# Respect tmux base-index settings
P0=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 0)
P1=$((P0 + 1))
P2=$((P0 + 2))

# ---------------------------------------------------------------------------
# Session → repo mapping
# ---------------------------------------------------------------------------
declare_repos() {
  case "$SESSION" in
    Buakfieren) MODE=single; REPOS=("$BASE/menoserv/buakfieren-app") ;;
    Hopninj)    MODE=single; REPOS=("$BASE/hopninj/skola-hopninj-app") ;;
    Sbs)        MODE=dual;   REPOS=("$BASE/sbs/skola-ui" "$BASE/sbs/skola-api") ;;
    Senova)     MODE=single; REPOS=("$BASE/senova/senova-pos") ;;
    Unecre)     MODE=dual;   REPOS=("$BASE/unecre/web_point_of_sale" "$BASE/unecre/api_point_of_sale") ;;
    *)
      echo "Unknown session '$SESSION' — no repo mapping configured." >&2
      exit 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# tmux helpers
# ---------------------------------------------------------------------------

window_exists() {
  tmux list-windows -t "$SESSION" -F '#{window_name}' | grep -qxF "$1"
}

add_worktree_window() {
  local wt_path="$1" wt_name="${2:-$(basename "$1")}"
  if window_exists "$wt_name"; then
    echo "  Window '$wt_name' already exists — skipping."
    return
  fi
  echo "  + window '$wt_name' (2 panes) → $wt_path"
  tmux new-window -t "$SESSION" -n "$wt_name" -c "$wt_path"
  tmux split-window -h -t "$SESSION:$wt_name" -c "$wt_path"
  tmux select-pane -t "$SESSION:$wt_name.$P1"
}

add_paired_worktree_window() {
  local ui_path="$1" api_path="$2" wt_name="$3"
  if window_exists "$wt_name"; then
    echo "  Window '$wt_name' already exists — skipping."
    return
  fi
  local parent_dir
  parent_dir=$(dirname "$ui_path")
  echo "  + window '$wt_name' (3 panes, paired) → ui: $ui_path / api: $api_path"
  tmux new-window -t "$SESSION" -n "$wt_name" -c "$ui_path"
  tmux split-window -h -t "$SESSION:$wt_name.$P0" -c "$parent_dir"
  tmux split-window -v -t "$SESSION:$wt_name.$P0" -c "$api_path"
  tmux select-pane -t "$SESSION:$wt_name.$P2"
}

# ---------------------------------------------------------------------------
# Sync logic
# ---------------------------------------------------------------------------

sync_single() {
  local repo="$1"
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
        [ "$(basename "$candidate")" = "api-$stripped" ] && { api_match="$candidate"; break; }
      done <<< "$all_wts"

      if [ -n "$api_match" ]; then
        add_paired_worktree_window "$wt_path" "$api_match" "$stripped"
        processed="$processed|$wt_path|$api_match"
      else
        add_worktree_window "$wt_path" "$stripped"
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
      add_worktree_window "$wt_path" "${name#api-}"
    else
      add_worktree_window "$wt_path"
    fi
    processed="$processed|$wt_path"
  done <<< "$all_wts"
}

sync_dual() {
  local ui_repo="$1" api_repo="$2"
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
            [ "$(basename "$candidate")" = "api-$stripped" ] && { api_path="$candidate"; break; }
          done <<< "$api_wts"
        fi

        if [ -n "$api_path" ]; then
          add_paired_worktree_window "$ui_path" "$api_path" "$stripped"
          processed="$processed|$api_path"
        else
          add_worktree_window "$ui_path" "$stripped"
        fi
      else
        add_worktree_window "$ui_path"
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
        add_worktree_window "$api_path" "${api_name#api-}"
      else
        add_worktree_window "$api_path"
      fi
    done <<< "$api_wts"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

declare_repos
echo "Syncing session '$SESSION' ($MODE)..."

# Create tmux windows
case "$MODE" in
  single)
    for repo in "${REPOS[@]}"; do
      sync_single "$repo"
    done
    ;;
  dual)
    sync_dual "${REPOS[0]}" "${REPOS[1]}"
    ;;
esac

# Sync env files
echo "Syncing env files..."
for repo in "${REPOS[@]}"; do
  sync_env "$repo"
done

echo "Done."
