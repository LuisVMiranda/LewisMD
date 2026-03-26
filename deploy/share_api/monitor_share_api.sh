#!/usr/bin/env bash
# Host-side monitor for the LewisMD remote share API deployment.
#
# This script runs outside Docker so it can detect failures in the full stack:
# - the public edge exposed by Caddy or an external reverse proxy
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
  PREVIOUS_SWEEPER_STATUS=""
  PREVIOUS_STORAGE_BYTES=""
  PREVIOUS_STORAGE_GROWTH_STATUS=""

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
      LAST_SWEEPER_STATUS)
        PREVIOUS_SWEEPER_STATUS="$value"
        ;;
      LAST_STORAGE_BYTES)
        PREVIOUS_STORAGE_BYTES="$value"
        ;;
      LAST_STORAGE_GROWTH_STATUS)
        PREVIOUS_STORAGE_GROWTH_STATUS="$value"
        ;;
    esac
  done <"$STATE_FILE"
}

write_state() {
  local current_health="$1"
  local current_disk_status="$2"
  local current_disk_percent="$3"
  local current_storage_bytes="$4"
  local current_storage_growth_status="$5"
  local current_sweeper_status="$6"
  local checked_at="$7"
  local temp_file

  temp_file="$(mktemp)"
  cat >"$temp_file" <<EOF
LAST_HEALTH_STATUS=$current_health
LAST_DISK_STATUS=$current_disk_status
LAST_DISK_PERCENT=$current_disk_percent
LAST_STORAGE_BYTES=$current_storage_bytes
LAST_STORAGE_GROWTH_STATUS=$current_storage_growth_status
LAST_SWEEPER_STATUS=$current_sweeper_status
LAST_CHECKED_AT=$checked_at
EOF

  mv "$temp_file" "$STATE_FILE"
}

public_up_url() {
  printf '%s/up' "${LEWISMD_SHARE_PUBLIC_BASE%/}"
}

local_edge_url() {
  local scheme="${LEWISMD_SHARE_PUBLIC_SCHEME:-https}"
  local host="${LEWISMD_SHARE_PUBLIC_HOST:-${LEWISMD_SHARE_SITE_ADDRESS:-}}"
  local http_port="${LEWISMD_SHARE_HTTP_PORT:-80}"
  local https_port="${LEWISMD_SHARE_HTTPS_PORT:-443}"
  local mode="${LEWISMD_SHARE_PUBLIC_MODE:-domain}"

  if [[ "$scheme" == "https" ]]; then
    if [[ "$https_port" == "443" ]]; then
      printf 'https://%s/up' "$host"
    else
      printf 'https://%s:%s/up' "$host" "$https_port"
    fi
  elif [[ "$mode" == "domain" ]]; then
    printf 'http://%s:%s/up' "$host" "$http_port"
  else
    printf 'http://127.0.0.1:%s/up' "$http_port"
  fi
}

check_public_edge() {
  curl -fsS --max-time 15 "$(public_up_url)" >/dev/null 2>&1
}

check_local_edge() {
  local scheme="${LEWISMD_SHARE_PUBLIC_SCHEME:-https}"
  local host="${LEWISMD_SHARE_PUBLIC_HOST:-${LEWISMD_SHARE_SITE_ADDRESS:-}}"
  local http_port="${LEWISMD_SHARE_HTTP_PORT:-80}"
  local https_port="${LEWISMD_SHARE_HTTPS_PORT:-443}"
  local mode="${LEWISMD_SHARE_PUBLIC_MODE:-domain}"
  local url
  url="$(local_edge_url)"

  if [[ "$scheme" == "https" ]]; then
    curl -kfsS --max-time 15 --resolve "${host}:${https_port}:127.0.0.1" "$url" >/dev/null 2>&1
  elif [[ "$mode" == "domain" ]]; then
    curl -fsS --max-time 15 --resolve "${host}:${http_port}:127.0.0.1" "$url" >/dev/null 2>&1
  else
    curl -fsS --max-time 15 "$url" >/dev/null 2>&1
  fi
}

check_compose_services() {
  local services
  services="$(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps --services --status running 2>/dev/null || true)"
  grep -q '^share-api$' <<<"$services" || return 1

  if [[ "${LEWISMD_SHARE_EDGE_MODE:-managed_caddy}" == "managed_caddy" ]]; then
    grep -q '^caddy$' <<<"$services"
  else
    return 0
  fi
}

storage_disk_percent() {
  local storage_path="${LEWISMD_SHARE_STORAGE_HOST_PATH:-$RUNTIME_DIR}"
  [[ -d "$storage_path" ]] || return 1
  df -P "$storage_path" | awk 'NR == 2 { gsub("%", "", $5); print $5 }'
}

storage_bytes() {
  local storage_path="${LEWISMD_SHARE_STORAGE_HOST_PATH:-$RUNTIME_DIR}"
  [[ -d "$storage_path" ]] || return 1
  du -sk "$storage_path" 2>/dev/null | awk 'NR == 1 { print $1 * 1024 }'
}

sweeper_report_file() {
  local storage_path="${LEWISMD_SHARE_STORAGE_HOST_PATH:-$RUNTIME_DIR}"
  printf '%s/maintenance/sweeper-state.json' "$storage_path"
}

systemd_timer_active() {
  systemctl is-active --quiet lewismd-share-sweeper.timer
}

systemd_service_failed() {
  systemctl is-failed --quiet lewismd-share-sweeper.service
}

load_sweeper_state() {
  local report_file
  report_file="$(sweeper_report_file)"
  [[ -f "$report_file" ]] || return 1

  local report_json
  report_json="$(tr -d '\r\n' <"$report_file")"
  SWEEPER_REPORTED_STATUS="$(printf '%s' "$report_json" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  SWEEPER_REPORTED_CHECKED_AT="$(printf '%s' "$report_json" | sed -n 's/.*"checked_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  SWEEPER_REPORTED_REMOVED_COUNT="$(printf '%s' "$report_json" | sed -n 's/.*"removed_count"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
  SWEEPER_REPORTED_ERROR="$(printf '%s' "$report_json" | sed -n 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

  [[ -n "$SWEEPER_REPORTED_STATUS" && -n "$SWEEPER_REPORTED_CHECKED_AT" ]]
}

sweeper_stale_threshold_minutes() {
  local configured="${LEWISMD_SHARE_MONITOR_SWEEPER_STALE_MINUTES:-}"
  if [[ "$configured" =~ ^[0-9]+$ && "$configured" -gt 0 ]]; then
    printf '%s' "$configured"
    return
  fi

  local sweep_interval="${LEWISMD_SHARE_EXPIRY_SWEEP_MINUTES:-60}"
  if [[ "$sweep_interval" =~ ^[0-9]+$ && "$sweep_interval" -gt 0 ]]; then
    local derived=$(( sweep_interval * 3 ))
    if (( derived < 15 )); then
      derived=15
    fi
    printf '%s' "$derived"
    return
  fi

  printf '180'
}

evaluate_sweeper_status() {
  local threshold_minutes
  threshold_minutes="$(sweeper_stale_threshold_minutes)"

  if ! systemd_timer_active; then
    CURRENT_SWEEPER_STATUS="stopped"
    CURRENT_SWEEPER_MESSAGE="The expiry sweeper timer is not active."
    return
  fi

  if systemd_service_failed; then
    CURRENT_SWEEPER_STATUS="failed"
    CURRENT_SWEEPER_MESSAGE="The expiry sweeper service reported a failed state."
    return
  fi

  if ! load_sweeper_state; then
    CURRENT_SWEEPER_STATUS="stale"
    CURRENT_SWEEPER_MESSAGE="The expiry sweeper has no readable state report yet."
    return
  fi

  if [[ "$SWEEPER_REPORTED_STATUS" == "failed" ]]; then
    CURRENT_SWEEPER_STATUS="failed"
    CURRENT_SWEEPER_MESSAGE="The expiry sweeper reported a failure: ${SWEEPER_REPORTED_ERROR:-unknown error}."
    return
  fi

  local checked_epoch now_epoch age_minutes
  checked_epoch="$(date -u -d "$SWEEPER_REPORTED_CHECKED_AT" +%s 2>/dev/null || true)"
  now_epoch="$(date -u +%s)"
  if [[ ! "$checked_epoch" =~ ^[0-9]+$ ]]; then
    CURRENT_SWEEPER_STATUS="stale"
    CURRENT_SWEEPER_MESSAGE="The expiry sweeper state report could not be parsed."
    return
  fi

  age_minutes=$(( (now_epoch - checked_epoch) / 60 ))
  if (( age_minutes > threshold_minutes )); then
    CURRENT_SWEEPER_STATUS="stale"
    CURRENT_SWEEPER_MESSAGE="The expiry sweeper last reported ${age_minutes} minute(s) ago, above the ${threshold_minutes}-minute stale threshold."
    return
  fi

  CURRENT_SWEEPER_STATUS="ok"
  CURRENT_SWEEPER_MESSAGE="The expiry sweeper last reported successfully ${age_minutes} minute(s) ago and removed ${SWEEPER_REPORTED_REMOVED_COUNT:-0} expired share(s)."
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
  local current_storage_bytes="unknown"
  local current_storage_growth_status="unknown"
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

  current_storage_bytes="$(storage_bytes 2>/dev/null || printf 'unknown')"
  local growth_threshold_mb="${LEWISMD_SHARE_MONITOR_STORAGE_GROWTH_MB:-250}"
  local growth_threshold_bytes=""
  local storage_growth_delta=""
  if [[ "$growth_threshold_mb" =~ ^[0-9]+$ ]]; then
    growth_threshold_bytes=$(( growth_threshold_mb * 1024 * 1024 ))
    if [[ "$current_storage_bytes" =~ ^[0-9]+$ && "$PREVIOUS_STORAGE_BYTES" =~ ^[0-9]+$ ]]; then
      if (( current_storage_bytes >= PREVIOUS_STORAGE_BYTES )); then
        storage_growth_delta=$(( current_storage_bytes - PREVIOUS_STORAGE_BYTES ))
      else
        storage_growth_delta=0
      fi

      if (( storage_growth_delta >= growth_threshold_bytes )); then
        current_storage_growth_status="high"
      else
        current_storage_growth_status="ok"
      fi
    fi
  fi

  local CURRENT_SWEEPER_STATUS="unknown"
  local CURRENT_SWEEPER_MESSAGE=""
  local SWEEPER_REPORTED_STATUS=""
  local SWEEPER_REPORTED_CHECKED_AT=""
  local SWEEPER_REPORTED_REMOVED_COUNT=""
  local SWEEPER_REPORTED_ERROR=""
  evaluate_sweeper_status

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

  if [[ "$CURRENT_SWEEPER_STATUS" == "ok" ]]; then
    if [[ -n "$PREVIOUS_SWEEPER_STATUS" && "$PREVIOUS_SWEEPER_STATUS" != "ok" ]]; then
      send_transition_alert "cleanup_recovered" "ok" "$CURRENT_SWEEPER_MESSAGE"
    fi
  elif [[ "$CURRENT_SWEEPER_STATUS" == "failed" && "$PREVIOUS_SWEEPER_STATUS" != "failed" ]]; then
    send_transition_alert "cleanup_failed" "failed" "$CURRENT_SWEEPER_MESSAGE"
  elif [[ "$CURRENT_SWEEPER_STATUS" == "stale" && "$PREVIOUS_SWEEPER_STATUS" != "stale" ]]; then
    send_transition_alert "cleanup_stale" "warning" "$CURRENT_SWEEPER_MESSAGE"
  elif [[ "$CURRENT_SWEEPER_STATUS" == "stopped" && "$PREVIOUS_SWEEPER_STATUS" != "stopped" ]]; then
    send_transition_alert "cleanup_stopped" "warning" "$CURRENT_SWEEPER_MESSAGE"
  fi

  if [[ "$current_disk_status" == "high" && "$PREVIOUS_DISK_STATUS" != "high" ]]; then
    send_transition_alert "disk_usage_high" "warning" "Share storage is at ${current_disk_percent}% usage, above the configured ${disk_threshold}% threshold."
  fi

  if [[ "$current_storage_growth_status" == "high" && "$PREVIOUS_STORAGE_GROWTH_STATUS" != "high" ]]; then
    local growth_delta_mb=$(( storage_growth_delta / 1024 / 1024 ))
    send_transition_alert "storage_growth_high" "warning" "Share storage grew by ${growth_delta_mb} MB since the previous monitor pass, above the configured ${growth_threshold_mb} MB threshold."
  fi

  write_state "$current_health_status" "$current_disk_status" "$current_disk_percent" "$current_storage_bytes" "$current_storage_growth_status" "$CURRENT_SWEEPER_STATUS" "$checked_at"

  log "$current_health_message"
  log "$CURRENT_SWEEPER_MESSAGE"
  if [[ "$current_disk_percent" =~ ^[0-9]+$ ]]; then
    log "Storage usage: ${current_disk_percent}%"
  fi
  if [[ "$current_storage_bytes" =~ ^[0-9]+$ ]]; then
    local storage_mb=$(( current_storage_bytes / 1024 / 1024 ))
    log "Storage footprint: ${storage_mb} MB"
  fi
  if [[ "$storage_growth_delta" =~ ^[0-9]+$ ]]; then
    local growth_delta_mb=$(( storage_growth_delta / 1024 / 1024 ))
    log "Storage growth since previous check: ${growth_delta_mb} MB"
  fi

  [[ "$current_health_status" == "up" ]]
}

main "$@"
