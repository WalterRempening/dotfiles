#!/usr/bin/env bash
# iosefin-lib.sh — Shared helpers for iosefin workspace scripts

BASE="$HOME/Dev/iosefin"
IOSEFIN_DIR="$HOME/dotfiles/iosefin"
PORTS_CONF="$IOSEFIN_DIR/iosefin-ports.conf"
CADDYFILE="$HOME/.config/caddy/Caddyfile"
HOSTS_MARKER="iosefin-managed"

ENV_PATTERNS=(.env .env.local .env.production .envrc .tool-versions .mise.toml)

# ---------------------------------------------------------------------------
# Core helpers
# ---------------------------------------------------------------------------

# Discover git repositories directly under a directory (one per line)
discover_repos() {
  local parent="$1"
  [ -d "$parent" ] || return 0
  for dir in "$parent"/*/; do
    [ -d "${dir}.git" ] && echo "${dir%/}"
  done
}

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

# Get worktree branch name from its path
get_worktree_branch() {
  local repo="$1" wt_path="$2"
  git -C "$repo" worktree list --porcelain 2>/dev/null | awk -v target="$wt_path" '
    /^worktree / { path = substr($0, 10) }
    /^branch /   { branch = substr($0, 8) }
    /^$/ {
      if (path == target) { print branch; exit }
      path = ""; branch = ""
    }
  '
}

# Convert branch name to domain-safe slug: "refs/heads/epic/tuition" → "tuition"
slugify_branch() {
  local branch="$1"
  branch="${branch#refs/heads/}"       # strip refs/heads/
  branch="${branch##*/}"               # keep only last segment after /
  branch="${branch#epic-}"             # strip epic- prefix
  echo "$branch" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed 's/^-//;s/-$//'
}

# Look up project config from ports.conf: returns "domain:app_port:slot"
get_project_config() {
  local repo="$1"
  local rel="${repo#$BASE/}"
  grep "^${rel}:" "$PORTS_CONF" 2>/dev/null | cut -d: -f2-
}

# Calculate port offset for a worktree: (slot * 3 + wt_index) * 100
port_offset() {
  local slot="$1" wt_index="$2"
  echo $(( (slot * 3 + wt_index) * 100 ))
}

# ---------------------------------------------------------------------------
# Env file sync
# ---------------------------------------------------------------------------

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
        [[ "$f" == ".envrc" ]] && command -v direnv &>/dev/null && direnv allow "$wt" 2>/dev/null && echo "    $wt_name: direnv allow" || true
        [[ "$f" == ".tool-versions" || "$f" == ".mise.toml" ]] && command -v mise &>/dev/null && (cd "$wt" && mise trust 2>/dev/null) && echo "    $wt_name: mise trust" || true
      fi
    done
  done <<< "$worktrees"
}

# ---------------------------------------------------------------------------
# Docker compose override for worktrees
# ---------------------------------------------------------------------------

# Parse docker-compose.yml and generate override with offset ports + unique volumes
generate_compose_override() {
  local wt_path="$1" wt_slug="$2" offset="$3"
  local compose_file="$wt_path/docker-compose.yml"
  [ -f "$compose_file" ] || return 0

  local override_file="$wt_path/docker-compose.override.yml"

  # Parse services, their ports, container_names, and volumes from compose file
  local services_block="" volumes_block=""
  local current_service="" in_services=0 in_volumes_top=0
  local svc_ports=() svc_container="" svc_volumes=()
  local top_volumes=()

  # Collect all info we need in one awk pass
  local parse_result
  parse_result=$(awk '
    /^services:/ { in_services=1; in_vtop=0; next }
    /^volumes:/ { in_services=0; in_vtop=1; next }
    /^[a-z]/ && !/^  / { in_services=0; in_vtop=0; next }

    # Top-level volume names
    in_vtop && /^  [a-zA-Z_-]+:/ {
      name = $1; sub(/:$/, "", name)
      print "VOL:" name
    }

    # Service detection
    in_services && /^  [a-zA-Z_-]+:/ && !/^    / {
      name = $1; sub(/:$/, "", name)
      current_svc = name
      print "SVC:" name
    }

    # Container name
    in_services && /container_name:/ {
      val = $2
      print "CONTAINER:" current_svc ":" val
    }

    # Port mappings (handle "HOST:CONTAINER" format, strip comments)
    in_services && /- "?[0-9]+:[0-9]+"?/ {
      line = $0
      sub(/#.*/, "", line)
      gsub(/[" -]/, "", line)
      gsub(/^ +/, "", line)
      split(line, parts, ":")
      print "PORT:" current_svc ":" parts[1] ":" parts[2]
    }

    # Volume mounts with named volumes (name:/path, not ./path:/path)
    in_services && /- [a-zA-Z_-]+:\/.*/ {
      line = $2
      split(line, parts, ":")
      if (parts[1] !~ /^[.]/ && parts[1] !~ /^\//) {
        print "MOUNT:" current_svc ":" parts[1] ":" parts[2]
      }
    }

    # Environment vars for DB credentials
    in_services && /POSTGRES_USER:/ { print "DBUSER:" current_svc ":" $2 }
    in_services && /POSTGRES_PASSWORD:/ { print "DBPASS:" current_svc ":" $2 }
    in_services && /POSTGRES_DB:/ { print "DBNAME:" current_svc ":" $2 }
  ' "$compose_file")

  # Build override YAML using awk to group by service
  local db_host_port="" db_user="" db_pass="" db_name=""

  # Extract DB info
  while IFS= read -r line; do
    case "$line" in
      DBUSER:*) db_user="${line##*:}" ;;
      DBPASS:*) db_pass="${line##*:}" ;;
      DBNAME:*) db_name="${line##*:}" ;;
      PORT:*:5432)
        # Extract host port from "PORT:svc:host_port:5432"
        local tmp="${line#PORT:*:}"  # "host_port:5432"
        local host_port="${tmp%%:*}"
        db_host_port=$((host_port + offset))
        ;;
    esac
  done <<< "$parse_result"

  # Generate YAML with awk (handles grouping naturally)
  echo "$parse_result" | awk -v slug="$wt_slug" -v offset="$offset" '
    BEGIN {
      print "# Auto-generated by iosefin sync — do not edit"
      print "services:"
      svc_count = 0
      vol_count = 0
    }
    /^SVC:/ {
      svc = substr($0, 5)
      svc_count++
      svcs[svc_count] = svc
      current = svc
    }
    /^PORT:/ {
      split($0, p, ":")
      # p[2]=svc, p[3]=host_port, p[4]=container_port
      svc = p[2]
      new_port = p[3] + offset
      ports[svc] = ports[svc] "      - \"" new_port ":" p[4] "\"\n"
    }
    /^MOUNT:/ {
      split($0, p, ":")
      # p[2]=svc, p[3]=vol_name, p[4]=vol_path
      svc = p[2]
      new_vol = p[3] "_" slug
      mounts[svc] = mounts[svc] "      - " new_vol ":" p[4] "\n"
      vol_count++
      vols[vol_count] = new_vol
    }
    END {
      for (i = 1; i <= svc_count; i++) {
        svc = svcs[i]
        print "  " svc ":"
        print "    container_name: " svc "-" slug
        if (ports[svc] != "") {
          print "    ports: !override"
          printf "%s", ports[svc]
        }
        if (mounts[svc] != "") {
          print "    volumes: !override"
          printf "%s", mounts[svc]
        }
      }
      if (vol_count > 0) {
        print ""
        print "volumes:"
        for (i = 1; i <= vol_count; i++) {
          print "  " vols[i] ":"
        }
      }
    }
  ' > "$override_file"

  echo "    ${wt_slug}: generated docker-compose.override.yml (port offset +${offset})"

  # Store DB info for later use
  if [ -n "$db_host_port" ]; then
    echo "${db_host_port}:${db_user}:${db_pass}:${db_name}" > "$wt_path/.iosefin-db-info"
  fi
}

# Copy main's database to a worktree's postgres (only on first setup)
copy_db_from_main() {
  local main_wt="$1" wt_path="$2"
  local flag_file="$wt_path/.iosefin-db-copied"

  # Skip if already copied
  [ -f "$flag_file" ] && return 0

  # Read DB info for both main and worktree
  local main_compose="$main_wt/docker-compose.yml"
  [ -f "$main_compose" ] || return 0
  [ -f "$wt_path/.iosefin-db-info" ] || return 0

  # Parse main DB port and credentials
  local main_db_port main_db_user main_db_pass main_db_name
  main_db_port=$(awk '/- "[0-9]+:5432"/ { gsub(/[" -]/, ""); split($0, p, ":"); print p[1]; exit }' "$main_compose")
  main_db_user=$(awk '/POSTGRES_USER:/ { print $2; exit }' "$main_compose")
  main_db_pass=$(awk '/POSTGRES_PASSWORD:/ { print $2; exit }' "$main_compose")
  main_db_name=$(awk '/POSTGRES_DB:/ { print $2; exit }' "$main_compose")

  [ -n "$main_db_port" ] || return 0

  # Parse worktree DB info
  local wt_info wt_db_port wt_db_user wt_db_pass wt_db_name
  wt_info=$(cat "$wt_path/.iosefin-db-info")
  IFS=: read -r wt_db_port wt_db_user wt_db_pass wt_db_name <<< "$wt_info"

  # Start docker compose in worktree
  echo "    Starting docker compose..."
  (cd "$wt_path" && docker compose up -d 2>/dev/null)

  # Wait for both postgres instances to be ready
  echo "    Waiting for postgres..."
  local retries=0
  while ! PGPASSWORD="$main_db_pass" psql -h localhost -p "$main_db_port" -U "$main_db_user" -d "$main_db_name" -c "SELECT 1" &>/dev/null; do
    retries=$((retries + 1))
    [ $retries -ge 30 ] && { echo "    ERROR: main postgres not ready after 30s"; return 1; }
    sleep 1
  done
  retries=0
  while ! PGPASSWORD="$wt_db_pass" psql -h localhost -p "$wt_db_port" -U "$wt_db_user" -d "$wt_db_name" -c "SELECT 1" &>/dev/null; do
    retries=$((retries + 1))
    [ $retries -ge 30 ] && { echo "    ERROR: worktree postgres not ready after 30s"; return 1; }
    sleep 1
  done

  # Dump main and restore to worktree
  echo "    Copying database from main (port $main_db_port → $wt_db_port)..."
  PGPASSWORD="$main_db_pass" pg_dump -h localhost -p "$main_db_port" -U "$main_db_user" "$main_db_name" \
    | PGPASSWORD="$wt_db_pass" psql -h localhost -p "$wt_db_port" -U "$wt_db_user" -d "$wt_db_name" -q 2>/dev/null

  if [ $? -eq 0 ]; then
    touch "$flag_file"
    echo "    Database copied successfully."
  else
    echo "    WARNING: Database copy had errors (may be OK if schema differs)."
    touch "$flag_file"
  fi
}

# Generate .env.worktree with port overrides and ensure .envrc loads it
generate_env_worktree() {
  local wt_path="$1" wt_slug="$2" offset="$3" app_port="$4"
  local env_file="$wt_path/.env.worktree"
  local envrc_file="$wt_path/.envrc"

  # Read DB port from .iosefin-db-info if available
  local db_port=""
  if [ -f "$wt_path/.iosefin-db-info" ]; then
    db_port=$(cut -d: -f1 "$wt_path/.iosefin-db-info")
  fi

  # Calculate worktree app port
  local wt_app_port=""
  if [ "$app_port" -gt 0 ] 2>/dev/null; then
    wt_app_port=$((app_port + offset))
  fi

  # Write .env.worktree
  {
    echo "# Auto-generated by iosefin sync — worktree port overrides"
    [ -n "$db_port" ] && echo "DB_PORT=$db_port"
    [ -n "$wt_app_port" ] && echo "SERVER_PORT=$wt_app_port"
  } > "$env_file"

  # Ensure .envrc loads .env.worktree (after .env)
  if [ -f "$envrc_file" ]; then
    if ! grep -qF ".env.worktree" "$envrc_file"; then
      echo 'dotenv_if_exists .env.worktree' >> "$envrc_file"
      command -v direnv &>/dev/null && direnv allow "$wt_path" 2>/dev/null
      echo "    ${wt_slug}: added .env.worktree to .envrc"
    fi
  fi
}

# Orchestrate docker setup for all worktrees of a repo
sync_docker() {
  local repo="$1"
  [ -d "$repo" ] || return 0
  [ -f "$repo/docker-compose.yml" ] || return 0

  local config
  config=$(get_project_config "$repo")
  [ -n "$config" ] || return 0

  local domain app_port slot
  IFS=: read -r domain app_port slot <<< "$config"

  local main_wt
  main_wt=$(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '/^worktree / { print substr($0, 10); exit }')
  [ -n "$main_wt" ] || return 0

  local worktrees
  worktrees=$(get_worktrees "$repo")
  [ -z "$worktrees" ] && return 0

  local wt_index=0
  while IFS= read -r wt; do
    [ -z "$wt" ] || [ ! -d "$wt" ] && continue
    wt_index=$((wt_index + 1))

    local branch wt_slug offset
    branch=$(get_worktree_branch "$repo" "$wt")
    wt_slug=$(slugify_branch "$branch")
    offset=$(port_offset "$slot" "$wt_index")

    echo "  Worktree: $wt_slug (offset +$offset)"

    # Add docker-compose.override.yml to gitignore if not already there
    if [ -f "$wt/.gitignore" ] && ! grep -qxF "docker-compose.override.yml" "$wt/.gitignore"; then
      echo "docker-compose.override.yml" >> "$wt/.gitignore"
      echo "    ${wt_slug}: added docker-compose.override.yml to .gitignore"
    fi

    # Generate override
    generate_compose_override "$wt" "$wt_slug" "$offset"

    # Generate .env.worktree with port overrides
    generate_env_worktree "$wt" "$wt_slug" "$offset" "$app_port"

    # Copy DB from main
    copy_db_from_main "$main_wt" "$wt"

  done <<< "$worktrees"
}

# ---------------------------------------------------------------------------
# Caddy + /etc/hosts
# ---------------------------------------------------------------------------

# Collect all domain → port mappings (main + worktrees) across all repos
collect_domain_mappings() {
  local repos=("$@")
  # Output format: domain:port (one per line)

  for repo in "${repos[@]}"; do
    [ -d "$repo" ] || continue
    local config
    config=$(get_project_config "$repo")
    [ -n "$config" ] || continue

    local domain app_port slot
    IFS=: read -r domain app_port slot <<< "$config"

    # Main domain
    if [ "$app_port" -gt 0 ] 2>/dev/null; then
      echo "${domain}.test:${app_port}"
    fi

    # Worktree domains
    local worktrees
    worktrees=$(get_worktrees "$repo")
    [ -z "$worktrees" ] && continue

    local wt_index=0
    while IFS= read -r wt; do
      [ -z "$wt" ] || [ ! -d "$wt" ] && continue
      wt_index=$((wt_index + 1))

      if [ "$app_port" -gt 0 ] 2>/dev/null; then
        local branch wt_slug offset wt_app_port
        branch=$(get_worktree_branch "$repo" "$wt")
        wt_slug=$(slugify_branch "$branch")
        offset=$(port_offset "$slot" "$wt_index")
        wt_app_port=$((app_port + offset))
        echo "${domain}-${wt_slug}.test:${wt_app_port}"
      fi
    done <<< "$worktrees"
  done
}

# Generate Caddyfile from domain mappings
generate_caddyfile() {
  local mappings="$1"
  [ -n "$mappings" ] || return 0

  mkdir -p "$(dirname "$CADDYFILE")"

  local content="# Auto-generated by iosefin sync — do not edit manually
"

  while IFS=: read -r domain port; do
    [ -z "$domain" ] && continue
    content+="
${domain} {
  reverse_proxy localhost:${port}
}
"
  done <<< "$mappings"

  echo "$content" > "$CADDYFILE"
  echo "  Generated Caddyfile with $(echo "$mappings" | wc -l | tr -d ' ') domains"
}

# Update /etc/hosts with .test domains (requires sudo)
update_etc_hosts() {
  local mappings="$1"
  [ -n "$mappings" ] || return 0

  # Collect all domain names
  local domains=""
  while IFS=: read -r domain _port; do
    [ -n "$domain" ] && domains+=" $domain"
  done <<< "$mappings"
  domains="${domains# }"
  [ -n "$domains" ] || return 0

  local hosts_line="127.0.0.1 ${domains}"
  local start_marker="# ${HOSTS_MARKER}-start"
  local end_marker="# ${HOSTS_MARKER}-end"

  # Check if update is needed
  if grep -q "$start_marker" /etc/hosts 2>/dev/null; then
    local current
    current=$(sed -n "/${start_marker}/,/${end_marker}/p" /etc/hosts | grep -v "^#")
    if [ "$current" = "$hosts_line" ]; then
      echo "  /etc/hosts already up to date"
      return 0
    fi
  fi

  # Build new hosts block
  local new_block="${start_marker}
${hosts_line}
${end_marker}"

  if grep -q "$start_marker" /etc/hosts 2>/dev/null; then
    # Replace existing block using temp file (more robust than sed on macOS)
    local tmpfile
    tmpfile=$(mktemp)
    awk -v start="$start_marker" -v end="$end_marker" -v block="$new_block" '
      $0 == start { print block; skip=1; next }
      $0 == end { skip=0; next }
      !skip { print }
    ' /etc/hosts > "$tmpfile"
    sudo cp "$tmpfile" /etc/hosts
    rm -f "$tmpfile"
  else
    # Append new block
    echo "" | sudo tee -a /etc/hosts >/dev/null
    echo "$new_block" | sudo tee -a /etc/hosts >/dev/null
  fi

  echo "  Updated /etc/hosts with: $domains"
}

# Reload Caddy with new config
reload_caddy() {
  if ! command -v caddy &>/dev/null; then
    echo "  WARNING: caddy not found, skipping reload"
    return 0
  fi

  if pgrep -x caddy &>/dev/null; then
    caddy reload --config "$CADDYFILE" 2>/dev/null
    echo "  Caddy reloaded"
  else
    # Start via brew service (auto-starts on login, uses symlinked Caddyfile)
    brew services start caddy 2>/dev/null
    echo "  Caddy started (brew service)"
  fi
}

# Orchestrate Caddy + /etc/hosts for ALL projects (not just current session)
sync_caddy() {
  echo "Syncing domains..."

  # Build list of all repos from ports.conf
  local all_repos=()
  while IFS=: read -r rel_path _rest; do
    [[ "$rel_path" == \#* ]] && continue
    [ -z "$rel_path" ] && continue
    [ -d "$BASE/$rel_path" ] && all_repos+=("$BASE/$rel_path")
  done < "$PORTS_CONF"

  local mappings
  mappings=$(collect_domain_mappings "${all_repos[@]}")

  if [ -z "$mappings" ]; then
    echo "  No domain mappings found"
    return 0
  fi

  generate_caddyfile "$mappings"
  update_etc_hosts "$mappings"
  reload_caddy

  # Print summary table
  echo ""
  echo "  Domain mappings:"
  while IFS=: read -r domain port; do
    [ -z "$domain" ] && continue
    printf "    %-40s → localhost:%s\n" "$domain" "$port"
  done <<< "$mappings"
}
