#!/usr/bin/env bash
# Uninstall helper for the LewisMD remote share API deployment.
#
# The default behavior is intentionally conservative:
# - stop and remove the compose stack
# - remove the monitoring timer/service
# - keep share storage, Caddy state, and generated runtime config unless the
#   operator explicitly asks to delete them

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
ENV_FILE="$RUNTIME_DIR/.env"
COMPOSE_FILE="$RUNTIME_DIR/compose.yml"
AUTO_CONFIRM="false"
SKIP_BACKUP="false"
DELETE_RUNTIME="false"
DELETE_STORAGE="false"
DELETE_CADDY_STATE="false"
REMOVE_MONITORING="true"
REMOVE_STACK="true"

SUDO=""
STORAGE_HOST_PATH=""
CADDY_DATA_PATH=""
CADDY_CONFIG_PATH=""

usage() {
  cat <<'EOF'
Usage: deploy/share_api/uninstall_share_api.sh [--runtime-dir PATH] [--env-file PATH] [--compose-file PATH] [--yes] [--skip-backup] [--delete-runtime] [--delete-storage] [--delete-caddy-state]

Stops and removes the VPS share stack while preserving data unless you
explicitly opt into deleting it.
EOF
}

warn() {
  printf '[share-api uninstall] Warning: %s\n' "$*" >&2
}

die() {
  printf '[share-api uninstall] Error: %s\n' "$*" >&2
  exit 1
}

run_root() {
  if [[ -n "$SUDO" ]]; then
    "$SUDO" "$@"
  else
    "$@"
  fi
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
      --delete-runtime)
        DELETE_RUNTIME="true"
        ;;
      --delete-storage)
        DELETE_STORAGE="true"
        ;;
      --delete-caddy-state)
        DELETE_CADDY_STATE="true"
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

  die "This uninstall command needs root privileges or sudo to manage Docker and VPS files."
}

load_env_file_if_present() {
  [[ -f "$ENV_FILE" ]] || return 0

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

  STORAGE_HOST_PATH="${LEWISMD_SHARE_STORAGE_HOST_PATH:-}"
  CADDY_DATA_PATH="${LEWISMD_SHARE_CADDY_DATA_PATH:-}"
  CADDY_CONFIG_PATH="${LEWISMD_SHARE_CADDY_CONFIG_PATH:-}"
}

collect_interactive_choices() {
  [[ "$AUTO_CONFIRM" != "true" ]] || return 0

  echo "This will remove the LewisMD remote share VPS deployment."
  prompt_yes_no "Stop and remove the Docker stack?" "y" || REMOVE_STACK="false"
  prompt_yes_no "Remove the monitoring timer and systemd unit files?" "y" || REMOVE_MONITORING="false"

  if prompt_yes_no "Create a final backup before uninstalling anything?" "y"; then
    SKIP_BACKUP="false"
  else
    SKIP_BACKUP="true"
  fi

  if prompt_yes_no "Delete the generated runtime files under deploy/share_api/runtime?" "n"; then
    DELETE_RUNTIME="true"
  fi

  if [[ -n "$STORAGE_HOST_PATH" ]]; then
    if prompt_yes_no "Delete the persisted share storage at $STORAGE_HOST_PATH?" "n"; then
      DELETE_STORAGE="true"
    fi
  fi

  if [[ -n "$CADDY_DATA_PATH" || -n "$CADDY_CONFIG_PATH" ]]; then
    if prompt_yes_no "Delete the persisted Caddy state directories?" "n"; then
      DELETE_CADDY_STATE="true"
    fi
  fi
}

run_backup_if_requested() {
  [[ "$SKIP_BACKUP" == "true" ]] && return 0
  if [[ ! -f "$ENV_FILE" ]]; then
    warn "Skipping uninstall backup because the runtime environment file is missing at $ENV_FILE."
    return 0
  fi
  [[ -f "$SCRIPT_DIR/backup_share_api.sh" ]] || die "backup_share_api.sh was not found in $SCRIPT_DIR"
  bash "$SCRIPT_DIR/backup_share_api.sh" --runtime-dir "$RUNTIME_DIR" --env-file "$ENV_FILE"
}

remove_monitoring_units_if_requested() {
  [[ "$REMOVE_MONITORING" == "true" ]] || return 0

  if command -v systemctl >/dev/null 2>&1; then
    run_root systemctl disable --now lewismd-share-monitor.timer >/dev/null 2>&1 || true
    run_root systemctl stop lewismd-share-monitor.service >/dev/null 2>&1 || true
  fi

  run_root rm -f /etc/systemd/system/lewismd-share-monitor.timer
  run_root rm -f /etc/systemd/system/lewismd-share-monitor.service

  if command -v systemctl >/dev/null 2>&1; then
    run_root systemctl daemon-reload >/dev/null 2>&1 || true
  fi
}

remove_stack_if_requested() {
  [[ "$REMOVE_STACK" == "true" ]] || return 0
  [[ -f "$COMPOSE_FILE" ]] || return 0
  run_root docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down --remove-orphans || true
}

delete_paths_if_requested() {
  if [[ "$DELETE_RUNTIME" == "true" && -d "$RUNTIME_DIR" ]]; then
    run_root rm -rf "$RUNTIME_DIR"
  fi

  if [[ "$DELETE_STORAGE" == "true" && -n "$STORAGE_HOST_PATH" && -e "$STORAGE_HOST_PATH" ]]; then
    run_root rm -rf "$STORAGE_HOST_PATH"
  fi

  if [[ "$DELETE_CADDY_STATE" == "true" ]]; then
    [[ -n "$CADDY_DATA_PATH" && -e "$CADDY_DATA_PATH" ]] && run_root rm -rf "$CADDY_DATA_PATH"
    [[ -n "$CADDY_CONFIG_PATH" && -e "$CADDY_CONFIG_PATH" ]] && run_root rm -rf "$CADDY_CONFIG_PATH"
  fi
}

main() {
  parse_args "$@"
  detect_privilege_mode
  load_env_file_if_present
  collect_interactive_choices

  if [[ "$AUTO_CONFIRM" == "true" && "$SKIP_BACKUP" != "true" && ( "$DELETE_STORAGE" == "true" || "$DELETE_CADDY_STATE" == "true" ) ]]; then
    warn "Automatic uninstall is deleting persisted data. A backup will be created first."
  fi

  run_backup_if_requested
  remove_stack_if_requested
  remove_monitoring_units_if_requested
  delete_paths_if_requested

  echo "LewisMD remote share API uninstall complete."
  if [[ "$DELETE_STORAGE" != "true" ]]; then
    echo "Share storage was preserved."
  fi
  if [[ "$DELETE_CADDY_STATE" != "true" ]]; then
    echo "Caddy state was preserved."
  fi
  if [[ "$DELETE_RUNTIME" != "true" ]]; then
    echo "Generated runtime files were preserved under $RUNTIME_DIR."
  fi
}

main "$@"
