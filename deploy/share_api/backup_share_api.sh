#!/usr/bin/env bash
# Create a host-side backup archive for the LewisMD remote share API runtime.
#
# The backup archive is intentionally broader than the public share snapshots
# alone. It captures:
# - persisted share storage
# - generated runtime deployment files
# - Caddy state/config directories
#
# That keeps restore steps straightforward after a VPS rebuild or an accidental
# uninstall.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
ENV_FILE="$RUNTIME_DIR/.env"
OUTPUT_DIR="$RUNTIME_DIR/backups/manual"
QUIET="false"

SUDO=""
STORAGE_HOST_PATH=""
CADDY_DATA_PATH=""
CADDY_CONFIG_PATH=""
INSTANCE_NAME="remote-share-vps"
PUBLIC_BASE=""

usage() {
  cat <<'EOF'
Usage: deploy/share_api/backup_share_api.sh [--runtime-dir PATH] [--env-file PATH] [--output-dir PATH] [--quiet]

Creates a .tar.gz backup containing the generated runtime config plus the VPS
share storage and Caddy state directories referenced by the runtime .env file.
EOF
}

log() {
  [[ "$QUIET" == "true" ]] || printf '[share-api backup] %s\n' "$*"
}

die() {
  printf '[share-api backup] Error: %s\n' "$*" >&2
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
      --output-dir)
        shift
        [[ $# -gt 0 ]] || die "--output-dir requires a path"
        OUTPUT_DIR="$1"
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

  die "This backup command needs root privileges or sudo to read the VPS storage paths."
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

  STORAGE_HOST_PATH="${LEWISMD_SHARE_STORAGE_HOST_PATH:-}"
  CADDY_DATA_PATH="${LEWISMD_SHARE_CADDY_DATA_PATH:-}"
  CADDY_CONFIG_PATH="${LEWISMD_SHARE_CADDY_CONFIG_PATH:-}"
  INSTANCE_NAME="${LEWISMD_SHARE_INSTANCE_NAME:-remote-share-vps}"
  PUBLIC_BASE="${LEWISMD_SHARE_PUBLIC_BASE:-}"

  [[ -n "$STORAGE_HOST_PATH" ]] || die "LEWISMD_SHARE_STORAGE_HOST_PATH is missing from $ENV_FILE"
  [[ -n "$CADDY_DATA_PATH" ]] || die "LEWISMD_SHARE_CADDY_DATA_PATH is missing from $ENV_FILE"
  [[ -n "$CADDY_CONFIG_PATH" ]] || die "LEWISMD_SHARE_CADDY_CONFIG_PATH is missing from $ENV_FILE"
}

copy_if_present() {
  local source="$1"
  local destination="$2"

  [[ -e "$source" ]] || return 0
  run_root mkdir -p "$(dirname "$destination")"
  run_root cp -R "$source" "$destination"
}

main() {
  parse_args "$@"
  detect_privilege_mode
  load_env_file

  local timestamp archive_name archive_path checksum_path temp_dir checked_at
  timestamp="$(date +%Y%m%d-%H%M%S)"
  archive_name="lewismd-share-backup-${timestamp}.tar.gz"
  archive_path="$OUTPUT_DIR/$archive_name"
  checksum_path="${archive_path}.sha256"
  checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  run_root mkdir -p "$OUTPUT_DIR"
  temp_dir="$(mktemp -d)"
  trap 'run_root rm -rf "$temp_dir"' EXIT

  run_root mkdir -p "$temp_dir/runtime"
  run_root mkdir -p "$temp_dir/host-data"

  copy_if_present "$ENV_FILE" "$temp_dir/runtime/.env"
  copy_if_present "$RUNTIME_DIR/compose.yml" "$temp_dir/runtime/compose.yml"
  copy_if_present "$RUNTIME_DIR/Caddyfile" "$temp_dir/runtime/Caddyfile"
  copy_if_present "$RUNTIME_DIR/lewismd_remote_share_config.fed.txt" "$temp_dir/runtime/lewismd_remote_share_config.fed.txt"
  copy_if_present "$RUNTIME_DIR/lewismd-share-monitor.service" "$temp_dir/runtime/lewismd-share-monitor.service"
  copy_if_present "$RUNTIME_DIR/lewismd-share-monitor.timer" "$temp_dir/runtime/lewismd-share-monitor.timer"

  copy_if_present "$STORAGE_HOST_PATH" "$temp_dir/host-data/storage"
  copy_if_present "$CADDY_DATA_PATH" "$temp_dir/host-data/caddy-data"
  copy_if_present "$CADDY_CONFIG_PATH" "$temp_dir/host-data/caddy-config"

  cat >"$temp_dir/backup-metadata.txt" <<EOF
created_at=$checked_at
instance_name=$INSTANCE_NAME
public_base=$PUBLIC_BASE
runtime_dir=$RUNTIME_DIR
storage_host_path=$STORAGE_HOST_PATH
caddy_data_path=$CADDY_DATA_PATH
caddy_config_path=$CADDY_CONFIG_PATH
EOF

  log "Creating backup archive at $archive_path"
  run_root tar -czf "$archive_path" -C "$temp_dir" .
  run_root sh -c "sha256sum \"$archive_path\" > \"$checksum_path\""

  log "Backup archive created."
  echo "Archive:  $archive_path"
  echo "Checksum: $checksum_path"
}

main "$@"
