#!/usr/bin/env bash
# iosefin-lib.sh — Shared helpers for iosefin workspace scripts

BASE="$HOME/Dev/iosefin"
IOSEFIN_DIR="$HOME/dotfiles/iosefin"
PORTS_CONF="$IOSEFIN_DIR/iosefin-ports.conf"
CADDYFILE="/opt/homebrew/etc/Caddyfile"
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
  # A registered path that is not a repo yet — a reservation like
  # cocinas-dyck/erp-app, which holds only docs and has no enclosing repo
  # either — makes git exit 128. Under the callers' `set -o pipefail` that
  # status survives the awk pipe and aborts the whole sync, so check first and
  # report no worktrees instead. (ibus-wp does not hit this: git there resolves
  # to the enclosing sbs-db-wp-env repo, which is why it only ever produced a
  # stale route rather than a failure.)
  git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1 || return 0
  git -C "$repo_path" worktree list --porcelain 2>/dev/null | awk -v main="$repo_path" '
    /^worktree / { path = substr($0, 10) }
    /^prunable/  { prunable = 1 }
    /^$/ {
      if (path != "" && path != main && !prunable) print path
      path = ""; prunable = 0
    }
  '
}

# The repo's primary checkout — the first entry `worktree list` prints. Callers
# use it as the source to copy env files from and as the ports.conf lookup key.
#
# Guarded like get_worktrees: for a registered path that is not a repo, git
# exits 128, and under the callers' `set -o pipefail` a bare `$(git ... | awk)`
# assignment propagates that and aborts the sync. Empty output already means
# "nothing to do" at every call site, so failure collapses into that.
git_main_worktree() {
  local repo="$1"
  [ -d "$repo" ] || return 0
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 0
  git -C "$repo" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / { print substr($0, 10); exit }'
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

# Convert a worktree path to a stable slug derived from its directory basename.
# Used for Docker resources (container_name, volume names, COMPOSE_PROJECT_NAME)
# so a branch swap inside a worktree doesn't orphan its DB volume. Domains and
# .env.local URLs intentionally still use slugify_branch — those should track
# the branch under test so OAuth redirect URIs and bookmarks match the work.
#
# Strips the main repo's basename + "-" prefix when present so a worktree at
# "$BASE/hopninj/skola-hopninj-app-feat-closing" with main at
# "$BASE/hopninj/skola-hopninj-app" yields "feat-closing" rather than the full
# "skola-hopninj-app-feat-closing". Worktrees whose dir doesn't share the main
# repo's prefix (e.g. "$BASE/hopninj/modularization") use the basename as-is.
slugify_worktree() {
  local wt_path="$1" main_wt_path="$2"
  local wt_base main_base slug
  wt_base=$(basename "$wt_path")
  main_base=$(basename "$main_wt_path")
  if [ -n "$main_base" ] && [[ "$wt_base" == "${main_base}-"* ]]; then
    slug="${wt_base#${main_base}-}"
  else
    slug="$wt_base"
  fi
  echo "$slug" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed 's/^-//;s/-$//'
}

# Host for a worktree of a project: "<slug>.<domain>.test".
#
# The slug is the SUBDOMAIN, not the other way round (the scheme used to be
# "<domain>.<slug>.test"). That ordering is what makes a single wildcard cover
# every worktree: one "https://*.hopninj.test" entry in an Entra app manifest
# stands in for every branch, present and future, instead of a fresh redirect
# URI registered by hand each time a worktree appears. dnsmasq already resolves
# all of *.test to 127.0.0.1, so the extra label costs nothing there.
#
# Keycloak can't take the same wildcard — it only honours a trailing "*" and
# ignores the hostname entirely — so its clients are kept in step by
# sync_keycloak below instead.
worktree_domain() {
  local domain="$1" wt_slug="$2"
  echo "${wt_slug}.${domain}.test"
}

# Look up project config from ports.conf: returns "domain:app_port:slot"
get_project_config() {
  local repo="$1"
  # Resolve symlinks so kassa/faktura → infra/faktura matches ports.conf
  local resolved
  resolved=$(cd "$repo" 2>/dev/null && pwd -P)
  local rel="${resolved#$BASE/}"
  grep "^${rel}:" "$PORTS_CONF" 2>/dev/null | cut -d: -f2- || true
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
  main_wt=$(git_main_worktree "$repo")
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
  [ -f "$compose_file" ] || compose_file="$wt_path/compose.yml"
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

    # Port mappings (handle "HOST:CONTAINER" format, strip comments).
    #
    # A published port may be a literal (5432:5432) or parameterised
    # (${MINIO_API_PORT:-9020}:9000). Matching only literals made the minio
    # and mailhog services of sbs-api invisible here, so no offset was written
    # for them and the worktree mail container came up on the shared base
    # port while the app was pointed somewhere else.
    in_services && !/^[[:space:]]*#/ && \
      /- *"?(\$\{[A-Za-z_][A-Za-z0-9_]*:-[0-9]+\}|[0-9]+):[0-9]+/ {
      line = $0
      sub(/#.*/, "", line)
      # Resolve ${VAR:-9020} down to the default it declares, before the
      # punctuation is stripped, so the host port survives as a plain number.
      while (match(line, /\$\{[A-Za-z_][A-Za-z0-9_]*:-[0-9]+\}/)) {
        num = substr(line, RSTART, RLENGTH)
        sub(/^\$\{[A-Za-z_][A-Za-z0-9_]*:-/, "", num)
        sub(/\}$/, "", num)
        line = substr(line, 1, RSTART - 1) num substr(line, RSTART + RLENGTH)
      }
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

  # Set unique project name so worktree containers don't conflict with main
  local base_project
  base_project=$(basename "$wt_path")
  local env_compose="$wt_path/.env"
  if [ -f "$env_compose" ]; then
    if grep -q "^COMPOSE_PROJECT_NAME=" "$env_compose"; then
      sed -i '' "s/^COMPOSE_PROJECT_NAME=.*/COMPOSE_PROJECT_NAME=${base_project}-${wt_slug}/" "$env_compose"
    else
      echo "COMPOSE_PROJECT_NAME=${base_project}-${wt_slug}" >> "$env_compose"
    fi
  else
    echo "COMPOSE_PROJECT_NAME=${base_project}-${wt_slug}" > "$env_compose"
  fi

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
  [ -f "$main_compose" ] || main_compose="$main_wt/compose.yml"
  [ -f "$main_compose" ] || return 0
  [ -f "$wt_path/.iosefin-db-info" ] || return 0

  # Parse main DB port and credentials
  local main_db_port main_db_user main_db_pass main_db_name
  main_db_port=$(awk '/- "[0-9]+:5432"/ { gsub(/[" -]/, ""); split($0, p, ":"); print p[1]; exit }' "$main_compose")
  main_db_user=$(awk '/POSTGRES_USER:/ { print $2; exit }' "$main_compose")
  main_db_pass=$(awk '/POSTGRES_PASSWORD:/ { print $2; exit }' "$main_compose")
  main_db_name=$(awk '/POSTGRES_DB:/ { print $2; exit }' "$main_compose")

  [ -n "$main_db_port" ] || return 0

  # Check if main postgres is reachable before attempting copy
  if ! PGPASSWORD="$main_db_pass" psql -h localhost -p "$main_db_port" -U "$main_db_user" -d "$main_db_name" -c "SELECT 1" &>/dev/null; then
    echo "    Skipping DB copy — main postgres (port $main_db_port) not running"
    return 0
  fi

  # Parse worktree DB info
  local wt_info wt_db_port wt_db_user wt_db_pass wt_db_name
  wt_info=$(cat "$wt_path/.iosefin-db-info")
  IFS=: read -r wt_db_port wt_db_user wt_db_pass wt_db_name <<< "$wt_info"

  # Start docker compose in worktree.
  #
  # Unset COMPOSE_* env vars first: if the user ran `iosefin sync` from
  # *inside* another worktree's direnv, that worktree's
  # COMPOSE_PROJECT_NAME leaks here via the subshell and beats the
  # COMPOSE_PROJECT_NAME we wrote into this worktree's .env
  # (shell env > .env in compose's precedence). Symptom: volumes/
  # containers for worktree B get the project prefix of worktree A,
  # and container_names collide with an earlier bring-up done from the
  # correct shell. Unsetting here makes the per-worktree .env file the
  # single source of truth for project naming.
  (
    cd "$wt_path"
    unset COMPOSE_PROJECT_NAME COMPOSE_FILE COMPOSE_PROFILES COMPOSE_ENV_FILES
    docker compose up -d 2>&1
  ) || { echo "    WARNING: docker compose up failed — skipping DB copy"; return 0; }

  # Wait for worktree postgres to be ready
  echo "    Waiting for postgres..."
  retries=0
  while ! PGPASSWORD="$wt_db_pass" psql -h localhost -p "$wt_db_port" -U "$wt_db_user" -d "$wt_db_name" -c "SELECT 1" &>/dev/null; do
    retries=$((retries + 1))
    [ $retries -ge 30 ] && { echo "    ERROR: worktree postgres not ready after 30s"; return 1; }
    sleep 1
  done

  # Dump main and restore to worktree
  echo "    Copying database from main (port $main_db_port → $wt_db_port)..."
  if PGPASSWORD="$main_db_pass" pg_dump -h localhost -p "$main_db_port" -U "$main_db_user" "$main_db_name" \
    | PGPASSWORD="$wt_db_pass" psql -h localhost -p "$wt_db_port" -U "$wt_db_user" -d "$wt_db_name" -q 2>/dev/null; then
    touch "$flag_file"
    echo "    Database copied successfully."
  else
    touch "$flag_file"
    echo "    WARNING: Database copy had errors (may be OK if schema differs)."
  fi
}

# Generate .env.worktree with port overrides and ensure .envrc loads it
# Host port a service publishes for a given container port, as the compose
# file of that worktree declares it: a literal, or the default inside
# ${VAR:-default}.
#
# Exists because the offsets below used to be added to hardcoded bases (9010
# MinIO, 1028 mail). Those are the ports skola-app publishes. sbs-api uses
# 9020 and 1025, so a +700 worktree got 9710/1728 written into .env.worktree
# while its containers came up elsewhere — the app then dialled a port nothing
# was listening on and every upload failed with "Connection refused". Reading
# the number from the file keeps the two in step per repo.
_compose_host_port() {
  local file="$1" service="$2" container_port="$3" line
  [ -f "$file" ] || return 1
  line=$(awk -v svc="$service" -v cp="$container_port" '
    $0 ~ "^[[:space:]]+" svc ":[[:space:]]*$" { in_svc = 1; next }
    in_svc && /^[[:space:]]{1,2}[a-zA-Z0-9_-]+:[[:space:]]*$/ { in_svc = 0 }
    in_svc && $0 ~ ":" cp "\"?([[:space:]]|$|#)" { print; exit }
  ' "$file")
  [ -n "$line" ] || return 1
  printf '%s\n' "$line" | sed -E \
    -e 's/.*\$\{[A-Za-z_][A-Za-z0-9_]*:-([0-9]+)\}:.*/\1/' \
    -e 't' \
    -e 's/.*[-"[:space:]]([0-9]+):[0-9]+.*/\1/'
}

generate_env_worktree() {
  local wt_path="$1" wt_slug="$2" offset="$3" app_port="$4" domain="$5"
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
    if [ -n "$wt_app_port" ]; then
      echo "PORT=$wt_app_port"
      echo "SERVER_PORT=$wt_app_port"
      echo "ASPNETCORE_URLS=http://localhost:$wt_app_port"
    fi
    # APP_BASE_URL → this worktree's own host. Spring reads it as the root of
    # every link the app hands out (OTP mails, payment redirects), and the
    # application.yml default is the MAIN domain — so an unset worktree mails
    # out links that quietly land on the main checkout's app and its database.
    # Guarded on the repo actually reading the variable, like the probes below.
    local app_yml
    for app_yml in "$wt_path"/src/main/resources/application*.yml; do
      [ -f "$app_yml" ] || continue
      if grep -q 'APP_BASE_URL' "$app_yml"; then
        echo "APP_BASE_URL=https://$(worktree_domain "$domain" "$wt_slug")"
        break
      fi
    done

    # S3/MinIO + mail: apply the same offset the compose override uses, so the
    # app driver reaches THIS worktree's containers instead of the base ones.
    # Guarded so non-MinIO/non-mail projects stay unaffected.
    #
    # The base HOST port is read from the repo's own compose file rather than
    # assumed: the offset applies to whatever that repo publishes, and the two
    # repos here do not agree (skola-app 9010/1028, sbs-api 9020/1025).
    #
    # Reads whichever compose filename the repo uses. sbs-api renamed its file
    # to compose.yml, so probing only docker-compose.yml silently found no
    # services and wrote neither variable — the app then talked to the BASE
    # MinIO and mail instead of the worktree's, which looks like the worktree
    # working until two of them are up at once. Mirrors the same fallback at
    # generate_compose_override and sync_ports.
    local wt_compose="$wt_path/docker-compose.yml"
    [ -f "$wt_compose" ] || wt_compose="$wt_path/compose.yml"
    local minio_base mail_base mail_svc
    if grep -qE '^[[:space:]]+minio:' "$wt_compose" 2>/dev/null; then
      minio_base=$(_compose_host_port "$wt_compose" minio 9000)
      if [ -n "$minio_base" ]; then
        echo "SKOLA_STORAGE_S3_ENDPOINT=http://localhost:$((minio_base + offset))"
      else
        echo "    ${wt_slug}: could not read the minio host port from $(basename "$wt_compose")" >&2
      fi
    fi
    for mail_svc in mailhog mailpit; do
      grep -qE "^[[:space:]]+${mail_svc}:" "$wt_compose" 2>/dev/null || continue
      mail_base=$(_compose_host_port "$wt_compose" "$mail_svc" 1025)
      if [ -n "$mail_base" ]; then
        echo "MAIL_PORT=$((mail_base + offset))"
      else
        echo "    ${wt_slug}: could not read the ${mail_svc} host port from $(basename "$wt_compose")" >&2
      fi
      break
    done
  } > "$env_file"

  # Ensure .envrc exists and loads .env.worktree
  if [ ! -f "$envrc_file" ]; then
    # Create .envrc for worktrees that don't have one (e.g. Next.js projects)
    {
      echo "dotenv_if_exists .env"
      echo "dotenv_if_exists .env.local"
      echo "dotenv_if_exists .env.worktree"
    } > "$envrc_file"
    command -v direnv &>/dev/null && direnv allow "$wt_path" 2>/dev/null
    echo "    ${wt_slug}: created .envrc"
  elif ! grep -qF ".env.worktree" "$envrc_file"; then
    echo 'dotenv_if_exists .env.worktree' >> "$envrc_file"
    command -v direnv &>/dev/null && direnv allow "$wt_path" 2>/dev/null
    echo "    ${wt_slug}: added .env.worktree to .envrc"
  fi

  # Update worktree-specific URLs in .env.local
  local env_local="$wt_path/.env.local"
  if [ -n "$wt_app_port" ] && [ -f "$env_local" ]; then
    # NEXTAUTH_URL → this UI repo's domain
    if grep -q "^NEXTAUTH_URL=" "$env_local"; then
      sed -i '' "s|^NEXTAUTH_URL=.*|NEXTAUTH_URL=https://$(worktree_domain "$domain" "$wt_slug")|" "$env_local"
    fi

    # NEXT_PUBLIC_BACKEND_API_URL → paired API repo's domain (sibling worktree dir)
    if grep -q "^NEXT_PUBLIC_BACKEND_API_URL=" "$env_local"; then
      local api_domain
      api_domain=$(find_sibling_domain "$wt_path")
      if [ -n "$api_domain" ]; then
        sed -i '' "s|^NEXT_PUBLIC_BACKEND_API_URL=.*|NEXT_PUBLIC_BACKEND_API_URL=\"https://$(worktree_domain "$api_domain" "$wt_slug")\"|" "$env_local"
      fi
    fi
  fi
}

# Find the domain of a paired repo that lives as a sibling directory of $1.
# Used to resolve UI ↔ API pairing for env-var rewrites: a worktree's UI and API
# checkouts share the same parent dir (e.g. sbs/returning-student/{sbs-ui,sbs-api}).
# Returns the first matching sibling's domain from ports.conf (empty if none).
find_sibling_domain() {
  local wt_path="$1"
  local parent
  parent=$(dirname "$wt_path")
  local sibling
  for sibling in "$parent"/*/; do
    sibling="${sibling%/}"
    [ "$sibling" = "$wt_path" ] && continue
    [ -e "$sibling/.git" ] || continue

    # Resolve the sibling worktree to its primary checkout for ports.conf lookup
    local sibling_main
    sibling_main=$(git_main_worktree "$sibling")
    [ -n "$sibling_main" ] || continue

    local config
    config=$(get_project_config "$sibling_main")
    [ -n "$config" ] || continue

    local sibling_domain
    IFS=: read -r sibling_domain _rest <<< "$config"
    if [ -n "$sibling_domain" ]; then
      echo "$sibling_domain"
      return 0
    fi
  done
}

# Sync port overrides for all worktrees of a repo (env files)
sync_ports() {
  local repo="$1"
  [ -d "$repo" ] || return 0

  local config
  config=$(get_project_config "$repo")
  [ -n "$config" ] || return 0

  local domain app_port slot
  IFS=: read -r domain app_port slot <<< "$config"
  [ "$app_port" -gt 0 ] 2>/dev/null || return 0

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

    generate_env_worktree "$wt" "$wt_slug" "$offset" "$app_port" "$domain"
  done <<< "$worktrees"
}

# Orchestrate docker setup for all worktrees of a repo
sync_docker() {
  local repo="$1"
  [ -d "$repo" ] || return 0
  [ -f "$repo/docker-compose.yml" ] || [ -f "$repo/compose.yml" ] || return 0

  local config
  config=$(get_project_config "$repo")
  [ -n "$config" ] || return 0

  local domain app_port slot
  IFS=: read -r domain app_port slot <<< "$config"

  local main_wt
  main_wt=$(git_main_worktree "$repo")
  [ -n "$main_wt" ] || return 0

  local worktrees
  worktrees=$(get_worktrees "$repo")
  [ -z "$worktrees" ] && return 0

  local wt_index=0
  while IFS= read -r wt; do
    [ -z "$wt" ] || [ ! -d "$wt" ] && continue
    wt_index=$((wt_index + 1))

    local wt_slug offset
    wt_slug=$(slugify_worktree "$wt" "$main_wt")
    offset=$(port_offset "$slot" "$wt_index")

    echo "  Worktree: $wt_slug (offset +$offset)"

    # Add docker-compose.override.yml to gitignore if not already there
    if [ -f "$wt/.gitignore" ] && ! grep -qxF "docker-compose.override.yml" "$wt/.gitignore"; then
      echo "docker-compose.override.yml" >> "$wt/.gitignore"
      echo "    ${wt_slug}: added docker-compose.override.yml to .gitignore"
    fi

    # Generate override
    generate_compose_override "$wt" "$wt_slug" "$offset"

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
        echo "$(worktree_domain "$domain" "$wt_slug"):${wt_app_port}"
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

  # Each project gets two Caddy blocks:
  #   1. <domain>.test                  → developer-facing URL (browser bookmarks, /etc/hosts)
  #   2. localhost:<port + 10000>       → HTTPS variant of the app's local port. Some
  #                                       third-party SDKs (Mercado Pago Bricks, certain
  #                                       Stripe flows, Apple Pay) reject .test TLDs in
  #                                       their browser-side CORS allowlist; localhost
  #                                       is the only origin they reliably accept.
  while IFS=: read -r domain port; do
    [ -z "$domain" ] && continue
    local https_port=$((port + 10000))
    content+="
${domain} {
  tls internal
  reverse_proxy localhost:${port}
}

localhost:${https_port} {
  tls internal
  reverse_proxy localhost:${port}
}
"
  done <<< "$mappings"

  echo "$content" > "$CADDYFILE"
  echo "  Generated Caddyfile with $(echo "$mappings" | wc -l | tr -d ' ') domains (each with .test + localhost HTTPS variants)"
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
    # Replace existing block using temp file
    local tmpfile
    tmpfile=$(mktemp)
    local skip=0
    while IFS= read -r line; do
      if [ "$line" = "$start_marker" ]; then
        echo "$new_block" >> "$tmpfile"
        skip=1
      elif [ "$line" = "$end_marker" ]; then
        skip=0
      elif [ "$skip" -eq 0 ]; then
        echo "$line" >> "$tmpfile"
      fi
    done < /etc/hosts
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

  # Stashed for sync_keycloak, which needs the same host list and has no reason
  # to walk every repo's worktrees a second time to rebuild it.
  IOSEFIN_DOMAIN_MAPPINGS="$mappings"

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

  # Every worktree of a project lives under the project's own domain, so one
  # wildcard per project covers all of them. Printed as a reminder of what to
  # register in an external IdP (Entra app manifest) — a one-time step per
  # project rather than one per branch.
  local wildcards
  wildcards=$(while IFS=: read -r host _port; do
    [ -z "$host" ] && continue
    [[ "$host" == *.*.test ]] || continue
    echo "https://*.${host#*.}"
  done <<< "$mappings" | sort -u)
  if [ -n "$wildcards" ]; then
    echo ""
    echo "  IdP wildcards (register once per project, then never again):"
    while IFS= read -r w; do
      [ -n "$w" ] && printf "    %s\n" "$w"
    done <<< "$wildcards"
  fi
}

# ---------------------------------------------------------------------------
# Keycloak
# ---------------------------------------------------------------------------

# Keep the local Keycloak's clients in step with the worktree domains.
#
# Keycloak cannot do what Entra does with "https://*.hopninj.test": it honours
# only a trailing "*", and since 26.6.3 the wildcard is not applied to the
# hostname at all, so no single entry can stand for "every worktree of this
# project". The local Keycloak is ours, though, so instead of registering URIs
# by hand we push them: for every client that already lists a "<domain>.test"
# redirect URI, the same URI is added once per live worktree host, and hosts
# from worktrees that are gone (or from the old "<domain>.<slug>.test" scheme)
# are dropped. Clients with no redirect URIs at all are left untouched.
#
# Writes through the admin REST API, so it lands in the DB and survives
# restarts; realm JSON under infra/keycloak/realms is only read on first import
# and is deliberately not rewritten here.
sync_keycloak() {
  [ "${IOSEFIN_SKIP_KEYCLOAK:-0}" = "1" ] && return 0

  echo ""
  echo "Syncing Keycloak redirect URIs..."

  if ! command -v jq &>/dev/null; then
    echo "  jq not found — skipping"
    return 0
  fi

  local mappings="${IOSEFIN_DOMAIN_MAPPINGS:-}"
  if [ -z "$mappings" ]; then
    echo "  No domain mappings — skipping"
    return 0
  fi

  # domain -> worktree hosts, derived from the mapping list rather than from
  # git: a host is a worktree of <domain> when it ends in ".<domain>.test".
  local domains map_lines=""
  domains=$(awk -F: '!/^[[:space:]]*#/ && NF >= 4 { print $2 }' "$PORTS_CONF")
  local host _port d
  while IFS=: read -r host _port; do
    [ -z "$host" ] && continue
    for d in $domains; do
      [[ "$host" == *".${d}.test" ]] && map_lines+="${d} ${host}"$'\n'
    done
  done <<< "$mappings"

  if [ -z "$map_lines" ]; then
    echo "  No worktree domains — nothing to register"
    return 0
  fi

  local map_json
  map_json=$(printf '%s' "$map_lines" | jq -R -s '
    split("\n") | map(select(length > 0) | split(" "))
    | group_by(.[0]) | map({key: .[0][0], value: map(.[1])}) | from_entries')

  # Reach Keycloak however it is up: the Caddy host it advertises as
  # KC_HOSTNAME first, the container's published port as a fallback.
  local kc_base="" candidate
  for candidate in "${KEYCLOAK_ADMIN_URL:-}" "https://auth.test" "http://localhost:8089"; do
    [ -n "$candidate" ] || continue
    if curl -sf -o /dev/null --max-time 5 "$candidate/realms/master/.well-known/openid-configuration" 2>/dev/null; then
      kc_base="$candidate"
      break
    fi
  done
  if [ -z "$kc_base" ]; then
    echo "  Keycloak not reachable — skipping (start infra's keycloak and re-run)"
    return 0
  fi

  local token
  token=$(curl -sf --max-time 10 -X POST "$kc_base/realms/master/protocol/openid-connect/token" \
    -d grant_type=password -d client_id=admin-cli \
    -d "username=${KEYCLOAK_ADMIN_USER:-admin}" \
    -d "password=${KEYCLOAK_ADMIN_PASSWORD:-admin}" 2>/dev/null | jq -r '.access_token // empty') || true
  if [ -z "$token" ]; then
    echo "  Could not authenticate against $kc_base — skipping"
    return 0
  fi

  # Drops every host this script manages, then re-derives them from the
  # surviving "<domain>.test" entries. Applied to redirectUris and webOrigins
  # alike; entries that aren't URLs (native app schemes, the bare "+") fail to
  # parse, are treated as unmanaged, and pass through untouched.
  local jq_prog='
    def parse: capture("^(?<scheme>[a-z][a-z0-9+.-]*)://(?<host>[^/?#]*)(?<rest>.*)$"; "i");
    def managed($h):
      any($map | keys[]; . as $d
        | ($h | endswith("." + $d + ".test"))
          or (($h | startswith($d + ".")) and ($h | endswith(".test")) and ($h != $d + ".test")));
    def expand:
      [ .[] | select(managed((((. | parse) | .host) // "")) | not) ] as $keep
      | ($keep + [ $keep[] as $u
                   | ($u | parse) as $p
                   | ($map | to_entries[]) as $e
                   | select($p.host == ($e.key + ".test"))
                   | $e.value[] as $w
                   | $p.scheme + "://" + $w + $p.rest ])
      | unique;
    .redirectUris = ((.redirectUris // []) | expand)
    | .webOrigins = ((.webOrigins // []) | expand)'

  local realms realm clients count i client updated client_id client_name changed=0
  realms=$(curl -sf --max-time 10 -H "Authorization: Bearer $token" "$kc_base/admin/realms" 2>/dev/null \
    | jq -r '.[].realm' 2>/dev/null) || true
  [ -n "$realms" ] || { echo "  Could not list realms — skipping"; return 0; }

  for realm in $realms; do
    clients=$(curl -sf --max-time 10 -H "Authorization: Bearer $token" \
      "$kc_base/admin/realms/$realm/clients" 2>/dev/null) || continue
    [ -n "$clients" ] || continue
    count=$(jq 'length' <<< "$clients" 2>/dev/null) || continue

    for ((i = 0; i < count; i++)); do
      client=$(jq -c ".[$i]" <<< "$clients")
      # Only clients that already declare redirect URIs opt in.
      [ "$(jq -r '(.redirectUris // []) | length' <<< "$client")" -gt 0 ] || continue

      updated=$(jq -c --argjson map "$map_json" "$jq_prog" <<< "$client")
      if [ "$(jq -cS '{redirectUris, webOrigins}' <<< "$client")" = "$(jq -cS '{redirectUris, webOrigins}' <<< "$updated")" ]; then
        continue
      fi

      client_id=$(jq -r '.id' <<< "$client")
      client_name=$(jq -r '.clientId' <<< "$client")
      if curl -sf --max-time 10 -X PUT \
        -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
        -d "$updated" "$kc_base/admin/realms/$realm/clients/$client_id" >/dev/null 2>&1; then
        echo "  ${realm}/${client_name}: $(jq -r '.redirectUris | length' <<< "$updated") redirect URIs"
        changed=$((changed + 1))
      else
        echo "  ${realm}/${client_name}: update FAILED" >&2
      fi
    done
  done

  [ "$changed" -eq 0 ] && echo "  Already up to date"
  return 0
}
