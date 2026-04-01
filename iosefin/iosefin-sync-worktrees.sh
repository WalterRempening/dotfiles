#!/usr/bin/env bash
# iosefin-sync-worktrees.sh — Sync all tmux sessions, worktrees, env, docker, and domains
# Usage: Run from inside any tmux session
#
# Iterates ALL known sessions, creates windows for worktrees, copies env files,
# generates docker-compose overrides, copies databases, and updates Caddy + /etc/hosts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/iosefin-lib.sh"

# Must be inside tmux
if [ -z "${TMUX:-}" ]; then
  echo "Error: not inside a tmux session." >&2
  exit 1
fi

# Respect tmux base-index settings
P0=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 0)
P1=$((P0 + 1))
P2=$((P0 + 2))

# Current session (used for active tmux sessions list)
CURRENT_SESSION=$(tmux display-message -p '#{session_name}')

# ---------------------------------------------------------------------------
# Session definitions: session_name → mode + repos
# ---------------------------------------------------------------------------
ALL_SESSIONS=(Buakfieren Hopninj Sbs Senova Unecre Kassa Infra)

get_session_config() {
  local session="$1"
  case "$session" in
    Buakfieren) echo "single:$BASE/menoserv/buakfieren-app" ;;
    Hopninj)    echo "single:$BASE/hopninj/skola-hopninj-app" ;;
    Sbs)        echo "dual:$BASE/sbs/skola-ui:$BASE/sbs/skola-api" ;;
    Senova)     echo "single:$BASE/senova/senova-pos" ;;
    Unecre)     echo "dual:$BASE/unecre/web_point_of_sale:$BASE/unecre/api_point_of_sale" ;;
    Kassa)      echo "auto:$BASE/kassa" ;;
    Infra)      echo "auto:$BASE/infra" ;;
    *)          echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# tmux helpers (operate on $SESSION, set before calling)
# ---------------------------------------------------------------------------
SESSION=""

window_exists() {
  tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qxF "$1"
}

tmux_session_exists() {
  tmux has-session -t "$1" 2>/dev/null
}

add_worktree_window() {
  local wt_path="$1" wt_name="${2:-$(basename "$1")}"
  if window_exists "$wt_name"; then
    echo "    Window '$wt_name' already exists — skipping."
    return
  fi
  echo "    + window '$wt_name' (2 panes) → $wt_path"
  tmux new-window -t "$SESSION" -n "$wt_name" -c "$wt_path"
  tmux split-window -h -t "$SESSION:$wt_name" -c "$wt_path"
  tmux select-pane -t "$SESSION:$wt_name.$P1"
}

add_paired_worktree_window() {
  local ui_path="$1" api_path="$2" wt_name="$3"
  if window_exists "$wt_name"; then
    echo "    Window '$wt_name' already exists — skipping."
    return
  fi
  local parent_dir
  parent_dir=$(dirname "$ui_path")
  echo "    + window '$wt_name' (3 panes, paired) → api: $api_path / ui: $ui_path"
  tmux new-window -t "$SESSION" -n "$wt_name" -c "$api_path"
  tmux split-window -h -t "$SESSION:$wt_name.$P0" -c "$parent_dir"
  tmux split-window -v -t "$SESSION:$wt_name.$P0" -c "$ui_path"
  tmux select-pane -t "$SESSION:$wt_name.$P2"
}

# ---------------------------------------------------------------------------
# Sync logic (tmux windows)
# ---------------------------------------------------------------------------

sync_windows_single() {
  local repo="$1"
  local all_wts

  all_wts=$(get_worktrees "$repo")
  [ -z "$all_wts" ] && return 0

  while IFS= read -r wt_path; do
    [ -z "$wt_path" ] && continue
    add_worktree_window "$wt_path"
  done <<< "$all_wts"
}

# Dual mode: pair UI + API worktrees that share the same parent directory.
# Layout: sbs/i18n/skola-ui + sbs/i18n/skola-api → window "i18n"
#   ┌──────────┬──────────┐
#   │ ui       │          │
#   ├──────────┤ parent   │
#   │ api      │          │
#   └──────────┴──────────┘
sync_windows_dual() {
  local ui_repo="$1" api_repo="$2"

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

  local processed_api=""

  # For each UI worktree, find matching API worktree in same parent dir
  if [ -n "$ui_wts" ]; then
    while IFS= read -r ui_path; do
      [ -z "$ui_path" ] && continue
      local parent wt_name api_path
      parent=$(dirname "$ui_path")
      wt_name=$(basename "$parent")
      api_path="${api_by_parent[$parent]:-}"

      if [ -n "$api_path" ]; then
        add_paired_worktree_window "$ui_path" "$api_path" "$wt_name"
        processed_api="$processed_api|$api_path"
      else
        add_worktree_window "$ui_path" "$wt_name"
      fi
    done <<< "$ui_wts"
  fi

  # Handle orphan API worktrees (no matching UI in same parent)
  if [ -n "$api_wts" ]; then
    while IFS= read -r api_path; do
      [ -z "$api_path" ] && continue
      [[ "$processed_api" == *"|$api_path"* ]] && continue
      local parent wt_name
      parent=$(dirname "$api_path")
      wt_name=$(basename "$parent")
      add_worktree_window "$api_path" "$wt_name"
    done <<< "$api_wts"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "Syncing all sessions..."

ALL_REPOS=()

for session_name in "${ALL_SESSIONS[@]}"; do
  config=$(get_session_config "$session_name")
  [ -z "$config" ] && continue

  mode="${config%%:*}"
  repos_str="${config#*:}"

  # Parse repos from config string
  IFS=: read -ra REPOS <<< "$repos_str"

  # For auto mode, discover repos
  if [ "$mode" = "auto" ]; then
    mapfile -t REPOS < <(discover_repos "${REPOS[0]}")
    [ ${#REPOS[@]} -eq 0 ] && continue
  fi

  # Collect all repos for env + docker sync
  ALL_REPOS+=("${REPOS[@]}")

  # Create tmux windows (only if the session exists)
  if tmux_session_exists "$session_name"; then
    SESSION="$session_name"
    echo "Session: $session_name ($mode)"

    case "$mode" in
      single|auto)
        for repo in "${REPOS[@]}"; do
          sync_windows_single "$repo"
        done
        ;;
      dual)
        sync_windows_dual "${REPOS[0]}" "${REPOS[1]}"
        ;;
    esac
  else
    echo "Session: $session_name — not running, skipping windows"
  fi

  # Sync env files (regardless of whether session exists)
  for repo in "${REPOS[@]}"; do
    sync_env "$repo"
  done

  # Sync docker (regardless of whether session exists)
  for repo in "${REPOS[@]}"; do
    sync_docker "$repo"
  done
done

# Sync Caddy reverse proxy + /etc/hosts (scans ALL projects)
sync_caddy

echo "Done."
