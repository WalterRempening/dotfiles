#!/usr/bin/env bash
# =============================================================================
# Plugin: ccmux
# Description: Show AI agent session counts tracked by the ccmux daemon
# Dependencies: curl, jq (ccmux daemon on 127.0.0.1:$CCMUX_PORT)
# =============================================================================
#
# CONTRACT IMPLEMENTATION:
#
# State:
#   - active: daemon reachable and tracking at least one session
#   - inactive: daemon down, or no sessions tracked
#
# Health:
#   - error: at least one session is waiting on you (permission / question)
#   - info: at least one session is working
#   - ok: everything idle
#
# Context:
#   - waiting / working / idle / offline
#
# =============================================================================

POWERKIT_ROOT="${POWERKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "${POWERKIT_ROOT}/src/contract/plugin_contract.sh"

# =============================================================================
# Plugin Contract: Metadata
# =============================================================================

plugin_get_metadata() {
    metadata_set "id" "ccmux"
    metadata_set "name" "ccmux"
    metadata_set "description" "AI agent sessions tracked by ccmux"
}

# =============================================================================
# Plugin Contract: Options
# =============================================================================

plugin_declare_options() {
    # full      -> 1·2·3   (waiting · working · idle)
    # attention -> 1       (waiting only; plugin hides when nothing waits)
    # total     -> 3       (all tracked sessions)
    declare_option "format" "string" "full" "Display format: full, attention, total"
    declare_option "port" "number" "2269" "ccmux daemon port"
    declare_option "separator" "string" "·" "Separator between counts"
    declare_option "hide_when_idle" "bool" "false" "Hide unless a session is working or waiting"

    declare_option "icon" "icon" $'\U000F06A9' "Plugin icon"
    declare_option "icon_waiting" "icon" $'\U000F0A02' "Icon when a session needs you"

    declare_option "cache_ttl" "number" "2" "Cache duration in seconds"
}

# =============================================================================
# Plugin Contract: Collection
# =============================================================================

plugin_collect() {
    require_cmd "curl" || return 1
    require_cmd "jq" || return 1

    local port json counts
    port="${CCMUX_PORT:-$(get_option 'port')}"

    json=$(curl -s --max-time 1 "http://127.0.0.1:${port}/sessions" 2>/dev/null) || return 1
    [[ -z "$json" ]] && return 1

    # Only top-level sessions; subagents carry their own .status and must not
    # be counted here.
    counts=$(printf '%s' "$json" | jq -r '
        (.sessions // [])
        | map(.status)
        | [ (map(select(. == "waiting")) | length),
            (map(select(. == "working")) | length),
            (map(select(. == "idle"))    | length),
            length ]
        | @tsv
    ' 2>/dev/null) || return 1
    [[ -z "$counts" ]] && return 1

    local waiting working idle total
    IFS=$'\t' read -r waiting working idle total <<<"$counts"

    plugin_data_set "waiting" "${waiting:-0}"
    plugin_data_set "working" "${working:-0}"
    plugin_data_set "idle" "${idle:-0}"
    plugin_data_set "total" "${total:-0}"
}

# =============================================================================
# Plugin Contract: State
# =============================================================================

plugin_get_content_type() { printf 'dynamic'; }
plugin_get_presence() { printf 'conditional'; }

plugin_get_state() {
    local total waiting working
    total=$(plugin_data_get "total")
    waiting=$(plugin_data_get "waiting")
    working=$(plugin_data_get "working")

    # No daemon / no sessions -> inactive, and `conditional` presence hides us.
    [[ -z "$total" || "$total" -eq 0 ]] && { printf 'inactive'; return; }

    if [[ "$(get_option 'hide_when_idle')" == "true" ]] \
        && [[ "${waiting:-0}" -eq 0 && "${working:-0}" -eq 0 ]]; then
        printf 'inactive'
        return
    fi

    if [[ "$(get_option 'format')" == "attention" && "${waiting:-0}" -eq 0 ]]; then
        printf 'inactive'
        return
    fi

    printf 'active'
}

plugin_get_health() {
    local waiting working
    waiting=$(plugin_data_get "waiting")
    working=$(plugin_data_get "working")

    if [[ "${waiting:-0}" -gt 0 ]]; then
        printf 'error'
    elif [[ "${working:-0}" -gt 0 ]]; then
        printf 'info'
    else
        printf 'ok'
    fi
}

plugin_get_context() {
    local waiting working total
    waiting=$(plugin_data_get "waiting")
    working=$(plugin_data_get "working")
    total=$(plugin_data_get "total")

    if [[ -z "$total" ]]; then
        printf 'offline'
    elif [[ "${waiting:-0}" -gt 0 ]]; then
        printf 'waiting'
    elif [[ "${working:-0}" -gt 0 ]]; then
        printf 'working'
    else
        printf 'idle'
    fi
}

# =============================================================================
# Plugin Contract: Rendering
# =============================================================================

plugin_render() {
    local waiting working idle total sep
    waiting=$(plugin_data_get "waiting")
    working=$(plugin_data_get "working")
    idle=$(plugin_data_get "idle")
    total=$(plugin_data_get "total")
    sep=$(get_option "separator")

    case "$(get_option 'format')" in
        attention) printf '%s' "${waiting:-0}" ;;
        total)     printf '%s' "${total:-0}" ;;
        *)         printf '%s%s%s%s%s' \
                       "${waiting:-0}" "$sep" "${working:-0}" "$sep" "${idle:-0}" ;;
    esac
}

plugin_get_icon() {
    local waiting
    waiting=$(plugin_data_get "waiting")

    if [[ "${waiting:-0}" -gt 0 ]]; then
        get_option "icon_waiting"
    else
        get_option "icon"
    fi
}
