#!/usr/bin/env bash
# iosefin-lib.sh — Shared helpers for iosefin workspace scripts

BASE="$HOME/Dev/iosefin"

ENV_PATTERNS=(.env .env.local .env.production .envrc .tool-versions .mise.toml)

# List non-main, non-prunable worktree paths (one per line)
get_worktrees() {
  local repo_path="$1"
  [ -d "$repo_path" ] || return 0
  git -C "$repo_path" worktree list --porcelain 2>/dev/null | awk -v main="$repo_path" '
    /^worktree / { path = substr($0, 10) }
    /^prunable/  { prunable = 1 }
    /^$/ {
      if (path != "" && path != main && !prunable) print path
      path = ""; prunable = 0
    }
  '
}

# Copy env files from main worktree to all other worktrees for a repo
sync_env() {
  local repo="$1"
  [ -d "$repo" ] || return 0

  local main_wt
  main_wt=$(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '/^worktree / { print substr($0, 10); exit }')
  [ -n "$main_wt" ] || return 0

  local files_to_copy=()
  for pattern in "${ENV_PATTERNS[@]}"; do
    [ -f "$main_wt/$pattern" ] && files_to_copy+=("$pattern")
  done
  [ ${#files_to_copy[@]} -eq 0 ] && return 0

  local worktrees
  worktrees=$(get_worktrees "$repo")
  [ -z "$worktrees" ] && return 0

  while IFS= read -r wt; do
    [ -z "$wt" ] || [ ! -d "$wt" ] && continue
    local wt_name
    wt_name=$(basename "$wt")

    for f in "${files_to_copy[@]}"; do
      if [ ! -f "$wt/$f" ]; then
        cp "$main_wt/$f" "$wt/$f"
        echo "    $wt_name: copied $f"
        [[ "$f" == ".envrc" ]] && command -v direnv &>/dev/null && direnv allow "$wt" 2>/dev/null && echo "    $wt_name: direnv allow"
        [[ "$f" == ".tool-versions" || "$f" == ".mise.toml" ]] && command -v mise &>/dev/null && (cd "$wt" && mise trust 2>/dev/null) && echo "    $wt_name: mise trust"
      fi
    done
  done <<< "$worktrees"
}
