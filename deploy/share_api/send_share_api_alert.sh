#!/usr/bin/env bash
# Host-side alert sender for the LewisMD remote share API deployment.
#
# This script intentionally stays outside Docker so it can still report failures
# when the container stack itself is unavailable. It reads the generated runtime
# .env file written by install_share_api.sh and supports one alert destination
# plus an optional shared-secret signature for generic JSON webhooks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR_DEFAULT="$SCRIPT_DIR/runtime"
ENV_FILE="$RUNTIME_DIR_DEFAULT/.env"
EVENT=""
STATUS=""
MESSAGE=""

usage() {
  cat <<'EOF'
Usage: deploy/share_api/send_share_api_alert.sh --event EVENT --status STATUS --message MESSAGE [--env-file PATH]

Examples:
  deploy/share_api/send_share_api_alert.sh \
    --event service_down \
    --status down \
    --message "Public /up failed"
EOF
}

die() {
  printf '[share-api alert] Error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf '[share-api alert] Warning: %s\n' "$*" >&2
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

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

build_generic_payload() {
  local checked_at="$1"
  printf '{"event":"%s","status":"%s","instance":"%s","public_base":"%s","checked_at":"%s","message":"%s"}' \
    "$(json_escape "$EVENT")" \
    "$(json_escape "$STATUS")" \
    "$(json_escape "${LEWISMD_SHARE_INSTANCE_NAME:-remote-share-vps}")" \
    "$(json_escape "${LEWISMD_SHARE_PUBLIC_BASE:-}")" \
    "$(json_escape "$checked_at")" \
    "$(json_escape "$MESSAGE")"
}

build_text_message() {
  local checked_at="$1"
  printf '[LewisMD remote share][%s] %s (%s)\n%s\nPublic base: %s\nChecked at: %s' \
    "${LEWISMD_SHARE_INSTANCE_NAME:-remote-share-vps}" \
    "$EVENT" \
    "$STATUS" \
    "$MESSAGE" \
    "${LEWISMD_SHARE_PUBLIC_BASE:-unknown}" \
    "$checked_at"
}

send_payload() {
  local webhook_kind="$1"
  local payload="$2"
  local checked_at="$3"
  local curl_args=(
    -fsS
    --max-time 15
    -H "Content-Type: application/json"
    -X POST
    --data "$payload"
    "${LEWISMD_SHARE_ALERT_WEBHOOK_URL:-}"
  )

  case "$webhook_kind" in
    generic)
      if [[ -n "${LEWISMD_SHARE_ALERT_WEBHOOK_SECRET:-}" ]]; then
        local signature
        signature="$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "${LEWISMD_SHARE_ALERT_WEBHOOK_SECRET}" | awk '{print $NF}')"
        curl_args=(
          -fsS
          --max-time 15
          -H "Content-Type: application/json"
          -H "X-LewisMD-Alert-Signature: sha256=$signature"
          -H "X-LewisMD-Alert-Timestamp: $checked_at"
          -X POST
          --data "$payload"
          "${LEWISMD_SHARE_ALERT_WEBHOOK_URL}"
        )
      fi
      ;;
    slack|discord)
      ;;
    *)
      die "Unsupported webhook kind: $webhook_kind"
      ;;
  esac

  curl "${curl_args[@]}" >/dev/null
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env-file)
        shift
        [[ $# -gt 0 ]] || die "--env-file requires a path"
        ENV_FILE="$1"
        ;;
      --event)
        shift
        [[ $# -gt 0 ]] || die "--event requires a value"
        EVENT="$1"
        ;;
      --status)
        shift
        [[ $# -gt 0 ]] || die "--status requires a value"
        STATUS="$1"
        ;;
      --message)
        shift
        [[ $# -gt 0 ]] || die "--message requires a value"
        MESSAGE="$1"
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

  [[ -n "$EVENT" ]] || die "--event is required"
  [[ -n "$STATUS" ]] || die "--status is required"
  [[ -n "$MESSAGE" ]] || die "--message is required"
}

main() {
  parse_args "$@"
  load_env_file

  if [[ -z "${LEWISMD_SHARE_ALERT_WEBHOOK_URL:-}" ]]; then
    warn "No alert webhook URL is configured. Skipping outbound alert."
    exit 0
  fi

  local checked_at
  checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local webhook_kind="${LEWISMD_SHARE_ALERT_WEBHOOK_KIND:-generic}"
  local payload

  case "$webhook_kind" in
    generic)
      payload="$(build_generic_payload "$checked_at")"
      ;;
    slack)
      payload="$(printf '{"text":"%s"}' "$(json_escape "$(build_text_message "$checked_at")")")"
      ;;
    discord)
      payload="$(printf '{"content":"%s"}' "$(json_escape "$(build_text_message "$checked_at")")")"
      ;;
    *)
      die "Unsupported webhook kind in .env: $webhook_kind"
      ;;
  esac

  send_payload "$webhook_kind" "$payload" "$checked_at"
}

main "$@"
