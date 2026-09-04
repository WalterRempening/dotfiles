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

Known projects:    Buakfieren, Hopninj, Skola, Sbs, Senova, Unecre, Kassa, Infra,
                   Chopin, TikjetGo, SubastasFroes, CocinasDyck
Default-excluded:  Buakfieren, Unecre  (run with -p to start them)

Project names are matched case-insensitively and ignore -/_, so
"SubastasFroes", "subastas-froes" and "subastas_froes" are equivalent.
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

ALL_PROJECTS=(Buakfieren Hopninj Skola Sbs Senova Unecre Kassa Infra Chopin TikjetGo SubastasFroes CocinasDyck)
DEFAULT_EXCLUDED=(Buakfieren Unecre)

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

start_skola() {
  echo "Skola"
  if new_session "Skola" "$BASE/skola/skola-app"; then
    tmux split-window -h -t "Skola:Main" -c "$BASE/skola/skola-app"
    tmux select-pane  -t "Skola:Main.$P1"
    add_repo_worktrees "Skola" "$BASE/skola/skola-app"
    tmux select-window -t "Skola:Main"
  fi
  sync_env "$BASE/skola/skola-app"
}

start_sbs() {
  echo "Sbs"
  if new_session "Sbs" "$BASE/sbs/sbs-api"; then
    tmux split-window -h -t "Sbs:Main.$P0" -c "$BASE/sbs"
    tmux split-window -v -t "Sbs:Main.$P0" -c "$BASE/sbs/sbs-ui"
    tmux select-pane -t "Sbs:Main.$P2"
    add_dual_repo_worktrees "Sbs" "$BASE/sbs/sbs-ui" "$BASE/sbs/sbs-api"

    # Extra windows, one per satellite repo.
    #
    # sbs-ios and sbs-android are gone: both native apps were replaced by the
    # single Kotlin Multiplatform project, so two windows became one.
    #
    # The WordPress sites live inside sbs-db-wp-env, which is itself a repo.
    # That matters for ibus-wp, which is still an empty reservation — without
    # its own .git, every git command run there resolves to the ENCLOSING
    # sbs-db-wp-env repo, so asking for its worktrees would silently graft that
    # repo's worktrees onto an ibus-wp window. It gets a window and nothing
    # else until something is actually cloned into it.
    local extra_repo extra_name
    for extra_repo in \
      "$BASE/sbs/sbs-mobile-kmp" \
      "$BASE/sbs/sbs-db-wp-env/sbs-wp" \
      "$BASE/sbs/sbs-db-wp-env/ibus-wp"; do
      [ -d "$extra_repo" ] || continue
      extra_name=$(basename "$extra_repo")

      if [ -e "$extra_repo/.git" ]; then
        echo "    + window '$extra_name' (2 panes) → $extra_repo"
        tmux new-window -t "Sbs" -n "$extra_name" -c "$extra_repo"
        tmux split-window -h -t "Sbs:$extra_name" -c "$extra_repo"
        tmux select-pane  -t "Sbs:$extra_name.$P1"
        add_repo_worktrees "Sbs" "$extra_repo"
      else
        echo "    + window '$extra_name' (2 panes, not a repo yet) → $extra_repo"
        tmux new-window -t "Sbs" -n "$extra_name" -c "$extra_repo"
        tmux split-window -h -t "Sbs:$extra_name" -c "$extra_repo"
        tmux select-pane  -t "Sbs:$extra_name.$P1"
      fi
    done
    tmux select-window -t "Sbs:Main"
  fi
  sync_env "$BASE/sbs/sbs-api"
  sync_env "$BASE/sbs/sbs-ui"
  # Only repos with their own .git — sync_env on ibus-wp would copy
  # sbs-db-wp-env's env files into it, for the same enclosing-repo reason.
  [ -e "$BASE/sbs/sbs-mobile-kmp/.git" ] && sync_env "$BASE/sbs/sbs-mobile-kmp"
  [ -e "$BASE/sbs/sbs-db-wp-env/sbs-wp/.git" ] && sync_env "$BASE/sbs/sbs-db-wp-env/sbs-wp"
  return 0
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

start_tikjetgo() {
  echo "TikjetGo"
  if new_session "TikjetGo" "$BASE/tikjetgo/tikjetgo-app"; then
    tmux split-window -h -t "TikjetGo:Main" -c "$BASE/tikjetgo/tikjetgo-app"
    tmux select-pane  -t "TikjetGo:Main.$P1"
    add_repo_worktrees "TikjetGo" "$BASE/tikjetgo/tikjetgo-app"

    # Extra windows, one per satellite repo.
    #
    # tikjetgo-android and tikjetgo-ios never get windows: both native apps
    # were replaced by the single Kotlin Multiplatform project, the same way
    # sbs-ios/sbs-android collapsed into sbs-mobile-kmp. The old checkouts are
    # still on disk, so this is an explicit list rather than a directory scan.
    local extra_repo extra_name
    # shellcheck disable=SC2066  # single entry today; list kept for more later
    for extra_repo in \
      "$BASE/tikjetgo/tikjetgo-mobile-kmp"; do
      [ -d "$extra_repo" ] || continue
      extra_name=$(basename "$extra_repo")
      echo "    + window '$extra_name' (2 panes) → $extra_repo"
      tmux new-window -t "TikjetGo" -n "$extra_name" -c "$extra_repo"
      tmux split-window -h -t "TikjetGo:$extra_name" -c "$extra_repo"
      tmux select-pane  -t "TikjetGo:$extra_name.$P1"
      if [ -e "$extra_repo/.git" ]; then
        add_repo_worktrees "TikjetGo" "$extra_repo"
      fi
    done

    tmux select-window -t "TikjetGo:Main"
  fi
  sync_env "$BASE/tikjetgo/tikjetgo-app"
  if [ -e "$BASE/tikjetgo/tikjetgo-mobile-kmp/.git" ]; then
    sync_env "$BASE/tikjetgo/tikjetgo-mobile-kmp"
  fi
  return 0
}

start_infra() {
  echo "Infra"
  local INFRA_DIR="$BASE/infra"
  local INFRA_REPOS repo local_name
  mapfile -t INFRA_REPOS < <(discover_repos "$INFRA_DIR")

  # The first window is the compose root ($INFRA_DIR) itself, not the first
  # discovered child repo: docker-compose.yml and docker-compose.prod.yml live
  # there, so the stack is always one window away instead of a `cd ..`.
  #
  # $INFRA_DIR is itself a git repo, but discover_repos only walks its
  # children, so it never shows up twice. Everything under it is discovered
  # automatically and gets its own window. kassa-web is gone from this list
  # because it moved to the Kassa project, which discovers it the same way.
  #
  # There is one faktura checkout, infra/faktura — the clone iosefin-ports.conf
  # registers on 8086. The infra/faktura-app duplicate was a second clone of
  # the same GitLab repo and has been deleted.
  if new_session "Infra" "$INFRA_DIR"; then
    tmux rename-window -t "Infra:Main" "infra-compose"
    tmux split-window -h -t "Infra:infra-compose" -c "$INFRA_DIR"
    tmux select-pane  -t "Infra:infra-compose.$P1"
    add_repo_worktrees "Infra" "$INFRA_DIR"

    if [ ${#INFRA_REPOS[@]} -eq 0 ]; then
      echo "  No git repos found under $INFRA_DIR — compose window only."
    fi
    for repo in "${INFRA_REPOS[@]:-}"; do
      [ -n "$repo" ] || continue
      local_name=$(basename "$repo")
      echo "    + window '$local_name' (2 panes) → $repo"
      tmux new-window -t "Infra" -n "$local_name" -c "$repo"
      tmux split-window -h -t "Infra:$local_name" -c "$repo"
      tmux select-pane  -t "Infra:$local_name.$P1"
      add_repo_worktrees "Infra" "$repo"
    done
    tmux select-window -t "Infra:infra-compose"
  fi
  for repo in "${INFRA_REPOS[@]:-}"; do
    [ -n "$repo" ] || continue
    sync_env "$repo"
  done
  return 0
}

# Single-app project: one repo, one Main window, worktree windows if any.
# Tolerates a directory that has been reserved but not cloned into yet, the
# same way the Sbs ibus-wp window does — no .git means no worktree scan and no
# sync_env, both of which would otherwise resolve against an enclosing repo.
start_single_app() {
  local session="$1" app_path="$2"
  echo "$session"
  if [ ! -d "$app_path" ]; then
    echo "  $app_path does not exist yet — skipping."
    return 0
  fi
  if new_session "$session" "$app_path"; then
    tmux split-window -h -t "$session:Main" -c "$app_path"
    tmux select-pane  -t "$session:Main.$P1"
    if [ -e "$app_path/.git" ]; then
      add_repo_worktrees "$session" "$app_path"
    else
      echo "  (not a git repo yet — no worktree windows)"
    fi
    tmux select-window -t "$session:Main"
  fi
  if [ -e "$app_path/.git" ]; then
    sync_env "$app_path"
  fi
  return 0
}

start_subastas_froes() {
  start_single_app "SubastasFroes" "$BASE/subastas-froes/ausruf-app"
}

start_cocinas_dyck() {
  start_single_app "CocinasDyck" "$BASE/cocinas-dyck/erp-app"
}

# ===========================================================================
# Dispatcher
# ===========================================================================

# Fold a project name to its match key: lowercase, no separators. Lets
# "SubastasFroes", "subastas-froes" and "subastas_froes" all resolve.
_norm() {
  local s="${1,,}"
  echo "${s//[-_]/}"
}

in_array() {  # in_array NEEDLE ARRAY...
  local needle; needle=$(_norm "$1"); shift
  local item
  for item in "$@"; do
    [[ "$(_norm "$item")" == "$needle" ]] && return 0
  done
  return 1
}

run_project() {
  case "$(_norm "$1")" in
    buakfieren) start_buakfieren ;;
    hopninj)    start_hopninj ;;
    skola)      start_skola ;;
    sbs)        start_sbs ;;
    senova)     start_senova ;;
    unecre)     start_unecre ;;
    kassa)      start_kassa ;;
    infra)      start_infra ;;
    chopin)     start_chopin ;;
    tikjetgo)   start_tikjetgo ;;
    subastasfroes) start_subastas_froes ;;
    cocinasdyck)   start_cocinas_dyck ;;
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
