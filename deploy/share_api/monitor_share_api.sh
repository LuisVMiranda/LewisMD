#!/usr/bin/env bash
# Host-side monitor for the LewisMD remote share API deployment.
#
# This script runs outside Docker so it can detect failures in the full stack:
# - the public edge exposed by Caddy
# - the local edge as seen from the VPS host
# - the compose-managed service state
#
# Alerts are transition-based to avoid spam. Healthchecks heartbeats are still
# sent on every healthy run because heartbeat services depend on regular pings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
ENV_FILE="$RUNTIME_DIR/.env"
COMPOSE_FILE="$RUNTIME_DIR/compose.yml"
STATE_DIR="$RUNTIME_DIR/monitor"
STATE_FILE="$STATE_DIR/state.env"
QUIET="false"

usage() {
  cat <<'EOF'
Usage: deploy/share_api/monitor_share_api.sh [--runtime-dir PATH] [--env-file PATH] [--compose-file PATH] [--quiet]

Runs one host-side monitoring pass against the LewisMD remote share stack.
EOF
}

log() {
  [[ "$QUIET" == "true" ]] || printf '[share-api monitor] %s\n' "$*"
}

warn() {
  printf '[share-api monitor] Warning: %s\n' "$*" >&2
}

die() {
  printf '[share-api monitor] Error: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --runtime-dir)
        shift
        [[ $# -gt 0 ]] || die "--runtime-dir requires a path"
        RUNTIME_DIR="$1"
        ;;
      --env-file)
        shift
        [[ $# -gt 0 ]] || die "--env-file requires a path"
        ENV_FILE="$1"
        ;;
      --compose-file)
        shift
        [[ $# -gt 0 ]] || die "--compose-file requires a path"
        COMPOSE_FILE="$1"
        ;;
      --quiet)
        QUIET="true"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done

  STATE_DIR="$RUNTIME_DIR/monitor"
  STATE_FILE="$STATE_DIR/state.env"
}

load_env_file() {
  [[ -f "$ENV_FILE" ]] || die "Environment file not found at $ENV_FILE"

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|\#*)
        continue
        ;;
    esac

    local key="${line%%=*}"
    local value="${line#*=}"
    export "$key=$value"
  done <"$ENV_FILE"
}

load_previous_state() {
  mkdir -p "$STATE_DIR"
  PREVIOUS_HEALTH_STATUS=""
  PREVIOUS_DISK_STATUS=""
  PREVIOUS_DISK_PERCENT=""

  [[ -f "$STATE_FILE" ]] || return

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|\#*)
        continue
        ;;
    esac

    local key="${line%%=*}"
    local value="${line#*=}"

    case "$key" in
      LAST_HEALTH_STATUS)
        PREVIOUS_HEALTH_STATUS="$value"
        ;;
      LAST_DISK_STATUS)
        PREVIOUS_DISK_STATUS="$value"
        ;;
      LAST_DISK_PERCENT)
        PREVIOUS_DISK_PERCENT="$value"
        ;;
    esac
  done <"$STATE_FILE"
}

write_state() {
  local current_health="$1"
  local current_disk_status="$2"
  local current_disk_percent="$3"
  local checked_at="$4"
  local temp_file

  temp_file="$(mktemp)"
  cat >"$temp_file" <<EOF
LAST_HEALTH_STATUS=$current_health
LAST_DISK_STATUS=$current_disk_status
LAST_DISK_PERCENT=$current_disk_percent
LAST_CHECKED_AT=$checked_at
EOF

  mv "$temp_file" "$STATE_FILE"
}

public_up_url() {
  printf '%s/up' "${LEWISMD_SHARE_PUBLIC_BASE%/}"
}

local_edge_url() {
  if [[ "${LEWISMD_SHARE_SITE_ADDRESS:-}" == http://* ]]; then
    printf 'http://127.0.0.1:%s/up' "${LEWISMD_SHARE_HTTP_PORT:-80}"
  else
    printf 'https://%s/up' "${LEWISMD_SHARE_SITE_ADDRESS}"
  fi
}

check_public_edge() {
  curl -fsS --max-time 15 "$(public_up_url)" >/dev/null 2>&1
}

check_local_edge() {
  if [[ "${LEWISMD_SHARE_SITE_ADDRESS:-}" == http://* ]]; then
    curl -fsS --max-time 15 "$(local_edge_url)" >/dev/null 2>&1
  else
    curl -kfsS --max-time 15 --resolve "${LEWISMD_SHARE_SITE_ADDRESS}:443:127.0.0.1" "$(local_edge_url)" >/dev/null 2>&1
  fi
}

check_compose_services() {
  local services
  services="$(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps --services --status running 2>/dev/null || true)"

  grep -q '^share-api$' <<<"$services" && grep -q '^caddy$' <<<"$services"
}

storage_disk_percent() {
  local storage_path="${LEWISMD_SHARE_STORAGE_HOST_PATH:-$RUNTIME_DIR}"
  [[ -d "$storage_path" ]] || return 1
  df -P "$storage_path" | awk 'NR == 2 { gsub("%", "", $5); print $5 }'
}

send_transition_alert() {
  local event_name="$1"
  local status="$2"
  local message="$3"

  [[ -n "${LEWISMD_SHARE_ALERT_WEBHOOK_URL:-}" ]] || return 0

  bash "$SCRIPT_DIR/send_share_api_alert.sh" \
    --env-file "$ENV_FILE" \
    --event "$event_name" \
    --status "$status" \
    --message "$message" || warn "Failed to send $event_name alert."
}

send_healthchecks_ping() {
  local ping_url="${LEWISMD_SHARE_HEALTHCHECKS_PING_URL:-}"
  [[ -n "$ping_url" ]] || return 0

  curl -fsS --max-time 15 "$ping_url" >/dev/null || warn "Healthchecks success ping failed."
}

send_healthchecks_fail_ping() {
  local ping_url="${LEWISMD_SHARE_HEALTHCHECKS_PING_URL:-}"
  [[ -n "$ping_url" ]] || return 0

  local fail_url="${ping_url%/}/fail"
  curl -fsS --max-time 15 "$fail_url" >/dev/null || warn "Healthchecks failure ping failed."
}

main() {
  parse_args "$@"
  load_env_file
  load_previous_state

  local current_health_status="down"
  local current_health_message=""
  local public_ok="false"
  local local_ok="false"
  local compose_ok="false"

  if check_public_edge; then
    public_ok="true"
  fi

  if check_local_edge; then
    local_ok="true"
  fi

  if check_compose_services; then
    compose_ok="true"
  fi

  if [[ "$public_ok" == "true" ]]; then
    current_health_status="up"
    current_health_message="Public share endpoint responded successfully."
  else
    current_health_message="Public /up check failed."
    if [[ "$local_ok" == "true" && "$compose_ok" == "true" ]]; then
      current_health_message="$current_health_message The local edge still responds, so DNS, public routing, or external TLS may be misconfigured."
    elif [[ "$local_ok" != "true" && "$compose_ok" == "true" ]]; then
      current_health_message="$current_health_message The containers appear to be running, but the local reverse-proxy path is failing."
    elif [[ "$compose_ok" != "true" ]]; then
      current_health_message="$current_health_message One or more compose services are not running."
    fi
  fi

  local current_disk_percent="unknown"
  local current_disk_status="unknown"
  local disk_threshold="${LEWISMD_SHARE_MONITOR_DISK_THRESHOLD_PERCENT:-90}"

  if [[ "$disk_threshold" =~ ^[0-9]+$ ]]; then
    current_disk_percent="$(storage_disk_percent 2>/dev/null || printf 'unknown')"
    if [[ "$current_disk_percent" =~ ^[0-9]+$ ]]; then
      if (( current_disk_percent >= disk_threshold )); then
        current_disk_status="high"
      else
        current_disk_status="ok"
      fi
    fi
  fi

  local checked_at
  checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if [[ "$current_health_status" == "up" ]]; then
    send_healthchecks_ping

    if [[ "$PREVIOUS_HEALTH_STATUS" != "up" ]]; then
      local health_event="service_up"
      [[ "$PREVIOUS_HEALTH_STATUS" == "down" ]] && health_event="service_recovered"
      send_transition_alert "$health_event" "up" "$current_health_message"
    fi
  else
    if [[ "$PREVIOUS_HEALTH_STATUS" != "down" ]]; then
      send_transition_alert "service_down" "down" "$current_health_message"
      send_healthchecks_fail_ping
    fi
  fi

  if [[ "$current_disk_status" == "high" && "$PREVIOUS_DISK_STATUS" != "high" ]]; then
    send_transition_alert "disk_usage_high" "warning" "Share storage is at ${current_disk_percent}% usage, above the configured ${disk_threshold}% threshold."
  fi

  write_state "$current_health_status" "$current_disk_status" "$current_disk_percent" "$checked_at"

  log "$current_health_message"
  if [[ "$current_disk_percent" =~ ^[0-9]+$ ]]; then
    log "Storage usage: ${current_disk_percent}%"
  fi

  [[ "$current_health_status" == "up" ]]
}

main "$@"
