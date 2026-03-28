#!/usr/bin/env bash
# Upgrade helper for the LewisMD remote share API deployment.
#
# This script rebuilds the share-api image from the current repo checkout,
# refreshes the Caddy image, restarts the compose stack, and verifies that the
# deployment is healthy before returning.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
ENV_FILE="$RUNTIME_DIR/.env"
COMPOSE_FILE="$RUNTIME_DIR/compose.yml"
QUIET="false"
AUTO_CONFIRM="false"
SKIP_BACKUP="false"
SKIP_MONITOR_CHECK="false"
SHARE_API_UID="10001"
SHARE_API_GID="10001"

SUDO=""
BACKUP_OUTPUT=""
EDGE_MODE="managed_caddy"
STORAGE_HOST_PATH=""

usage() {
  cat <<'EOF'
Usage: deploy/share_api/upgrade_share_api.sh [--runtime-dir PATH] [--env-file PATH] [--compose-file PATH] [--yes] [--skip-backup] [--skip-monitor-check] [--quiet]

Performs an in-place upgrade of the LewisMD remote share API deployment.
EOF
}

log() {
  [[ "$QUIET" == "true" ]] || printf '[share-api upgrade] %s\n' "$*"
}

warn() {
  printf '[share-api upgrade] Warning: %s\n' "$*" >&2
}

die() {
  printf '[share-api upgrade] Error: %s\n' "$*" >&2
  exit 1
}

run_root() {
  if [[ -n "$SUDO" ]]; then
    "$SUDO" "$@"
  else
    "$@"
  fi
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
      --yes)
        AUTO_CONFIRM="true"
        ;;
      --skip-backup)
        SKIP_BACKUP="true"
        ;;
      --skip-monitor-check)
        SKIP_MONITOR_CHECK="true"
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
}

detect_privilege_mode() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    return
  fi

  die "This upgrade command needs root privileges or sudo to manage Docker on the VPS."
}

ensure_runtime_files() {
  [[ -f "$ENV_FILE" ]] || die "Environment file not found at $ENV_FILE"
  [[ -f "$COMPOSE_FILE" ]] || die "Compose file not found at $COMPOSE_FILE"
}

load_env_file() {
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|\#*)
        continue
        ;;
    esac

    local key="${line%%=*}"
    local value="${line#*=}"

    case "$key" in
      LEWISMD_SHARE_EDGE_MODE)
        EDGE_MODE="$value"
        ;;
      LEWISMD_SHARE_STORAGE_HOST_PATH)
        STORAGE_HOST_PATH="$value"
        ;;
    esac
  done <"$ENV_FILE"
}

prompt_yes_no() {
  local label="$1"
  local default_value="${2:-y}"
  local normalized_default="Y/n"

  if [[ "$default_value" =~ ^[Nn]$ ]]; then
    normalized_default="y/N"
  fi

  while true; do
    local answer
    read -r -p "$label [$normalized_default]: " answer
    answer="${answer:-$default_value}"

    case "$answer" in
      y|Y|yes|YES)
        return 0
        ;;
      n|N|no|NO)
        return 1
        ;;
      *)
        warn "Please answer yes or no."
        ;;
    esac
  done
}

notify_event() {
  local event_name="$1"
  local status="$2"
  local message="$3"

  if [[ -f "$SCRIPT_DIR/send_share_api_alert.sh" ]]; then
    bash "$SCRIPT_DIR/send_share_api_alert.sh" \
      --env-file "$ENV_FILE" \
      --event "$event_name" \
      --status "$status" \
      --message "$message" >/dev/null 2>&1 || true
  fi
}

wait_for_api_health() {
  local attempt

  for attempt in $(seq 1 30); do
    if run_root docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T share-api curl -fsS http://127.0.0.1:9292/up >/dev/null 2>&1; then
      return 0
    fi

    sleep 2
  done

  return 1
}

verify_share_storage_write_access() {
  run_root docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T share-api bundle exec ruby bin/verify_storage_write.rb >/dev/null
}

prepare_storage_permissions() {
  [[ -n "$STORAGE_HOST_PATH" ]] || return 0

  log "Ensuring the persisted share storage path is writable by the share-api container..."
  run_root mkdir -p "$STORAGE_HOST_PATH"
  run_root chown -R "${SHARE_API_UID}:${SHARE_API_GID}" "$STORAGE_HOST_PATH"
}

run_monitor_check() {
  [[ "$SKIP_MONITOR_CHECK" == "true" ]] && return 0
  bash "$SCRIPT_DIR/monitor_share_api.sh" --runtime-dir "$RUNTIME_DIR" --env-file "$ENV_FILE" --compose-file "$COMPOSE_FILE" --quiet
}

perform_backup_if_requested() {
  [[ "$SKIP_BACKUP" == "true" ]] && return 0

  if [[ "$AUTO_CONFIRM" != "true" ]]; then
    if ! prompt_yes_no "Create a pre-upgrade backup before restarting the stack?" "y"; then
      return 0
    fi
  fi

  BACKUP_OUTPUT="$(bash "$SCRIPT_DIR/backup_share_api.sh" --runtime-dir "$RUNTIME_DIR" --env-file "$ENV_FILE" --quiet)"
}

handle_failure() {
  local exit_code=$?
  notify_event "deploy_failed" "failed" "The remote share API upgrade did not complete successfully."
  exit "$exit_code"
}

main() {
  trap handle_failure ERR

  parse_args "$@"
  detect_privilege_mode
  ensure_runtime_files
  load_env_file

  if [[ "$AUTO_CONFIRM" != "true" ]]; then
    if [[ "$EDGE_MODE" == "managed_caddy" ]]; then
      echo "This will rebuild the share-api image, refresh the Caddy image, and restart the remote share stack."
    else
      echo "This will rebuild the share-api image and restart the remote share stack behind the existing reverse proxy."
    fi
    prompt_yes_no "Proceed with the upgrade?" "y" || die "Upgrade cancelled."
  fi

  perform_backup_if_requested
  notify_event "deploy_started" "starting" "The remote share API upgrade has started."

  prepare_storage_permissions

  log "Refreshing container images..."
  if [[ "$EDGE_MODE" == "managed_caddy" ]]; then
    run_root docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull caddy
  fi
  run_root docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" build --pull share-api
  run_root docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

  log "Waiting for the upgraded stack to become healthy..."
  wait_for_api_health || die "The share-api container did not become healthy after the upgrade."
  verify_share_storage_write_access || die "The share-api became healthy, but it could not write to the persisted share storage path."
  run_monitor_check || die "The host-level monitor reported an unhealthy deployment after the upgrade."

  trap - ERR
  notify_event "deploy_succeeded" "ok" "The remote share API upgrade completed successfully."

  log "Upgrade complete."
  if [[ -n "$BACKUP_OUTPUT" ]]; then
    printf '%s\n' "$BACKUP_OUTPUT"
  fi
  log "Cloudflare checklist: keep the share hostname orange-cloud proxied, use Full (strict), and apply the documented rate limits before treating the edge as hardened."
  log "If this VPS was installed before the security-hardening release, rerun the installer or manually merge the new runtime compose/Caddy files so the container and edge hardening settings take effect."
}

main "$@"
