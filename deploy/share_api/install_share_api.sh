#!/usr/bin/env bash
# Interactive installer for the optional LewisMD remote share API.
#
# This script is meant to run on a Linux VPS after the LewisMD repository has
# been cloned. It keeps the deployment self-contained by:
# - installing Docker and basic host dependencies when missing
# - guiding the operator through the values that must be chosen manually
# - generating the runtime compose/Caddy/.env files under deploy/share_api/runtime
# - opening firewall rules when the operator opts into that automation
# - booting the stack and running smoke checks against the deployed service
#
# Supported host distros:
# - Ubuntu
# - Fedora
# - AlmaLinux
#
# The resulting public share service is intentionally narrow:
# - Caddy is the only public edge
# - the share API container stays on an internal Docker network
# - all write credentials remain for the local LewisMD app to use later

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVICE_SOURCE_DIR="$REPO_ROOT/services/share_api"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
RUNTIME_ENV_FILE="$RUNTIME_DIR/.env"
RUNTIME_COMPOSE_FILE="$RUNTIME_DIR/compose.yml"
RUNTIME_CADDY_FILE="$RUNTIME_DIR/Caddyfile"
RUNTIME_SUMMARY_FILE="$RUNTIME_DIR/lewismd_remote_share_config.fed.txt"
RUNTIME_MONITOR_SERVICE_FILE="$RUNTIME_DIR/lewismd-share-monitor.service"
RUNTIME_MONITOR_TIMER_FILE="$RUNTIME_DIR/lewismd-share-monitor.timer"
COMPOSE_PROJECT_NAME="lewismd-share-api"

SUDO=""
DISTRO_ID=""
DISTRO_FAMILY=""
DISTRO_NAME=""

PUBLIC_MODE=""
PUBLIC_HOST=""
PUBLIC_BASE=""
SITE_ADDRESS=""
HTTP_PORT=""
HTTPS_PORT=""
ACME_EMAIL=""
OPEN_FIREWALL="false"
STORAGE_HOST_PATH=""
CADDY_DATA_PATH=""
CADDY_CONFIG_PATH=""
API_TOKEN=""
SIGNING_SECRET=""
PUMA_MAX_THREADS="5"
WEB_CONCURRENCY="1"
VERIFY_TLS="true"
INSTANCE_NAME=""
ENABLE_MONITORING="true"
MONITOR_INTERVAL_MINUTES="5"
MONITOR_DISK_THRESHOLD_PERCENT="90"
HEALTHCHECKS_PING_URL=""
ALERT_WEBHOOK_KIND=""
ALERT_WEBHOOK_URL=""
ALERT_WEBHOOK_SECRET=""

main() {
  parse_args "$@"
  check_platform
  ensure_repo_layout
  detect_privilege_mode
  detect_distro
  gather_answers
  confirm_plan
  install_host_dependencies
  prepare_runtime_layout
  backup_existing_runtime_if_needed
  write_runtime_env
  write_runtime_caddyfile
  write_runtime_compose
  write_runtime_monitoring_units
  configure_firewall_if_requested
  start_stack
  run_smoke_checks
  install_monitoring_timer_if_requested
  run_initial_monitor_check_if_requested
  write_local_config_summary
  print_success_summary
}

usage() {
  cat <<'EOF'
Usage: deploy/share_api/install_share_api.sh

Runs the interactive VPS installer for the optional LewisMD remote share API.

This installer:
  1. Detects Ubuntu / Fedora / AlmaLinux
  2. Installs Docker and required host tools if missing
  3. Prompts for the public host mode and deployment settings
  4. Generates runtime files under deploy/share_api/runtime
  5. Optionally installs a host-level monitoring timer
  6. Starts the stack and validates /up

Run it on the target VPS from inside the LewisMD repository clone.
EOF
}

log() {
  printf '[share-api installer] %s\n' "$*"
}

warn() {
  printf '[share-api installer] Warning: %s\n' "$*" >&2
}

die() {
  printf '[share-api installer] Error: %s\n' "$*" >&2
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
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  fi
}

check_platform() {
  [[ -f /etc/os-release ]] || die "This installer only supports Linux hosts with /etc/os-release."
}

ensure_repo_layout() {
  [[ -d "$SERVICE_SOURCE_DIR" ]] || die "Could not find services/share_api at $SERVICE_SOURCE_DIR."
  [[ -f "$SCRIPT_DIR/backup_share_api.sh" ]] || die "Could not find deploy/share_api/backup_share_api.sh at $SCRIPT_DIR."
  [[ -f "$SCRIPT_DIR/monitor_share_api.sh" ]] || die "Could not find deploy/share_api/monitor_share_api.sh at $SCRIPT_DIR."
  [[ -f "$SCRIPT_DIR/send_share_api_alert.sh" ]] || die "Could not find deploy/share_api/send_share_api_alert.sh at $SCRIPT_DIR."
  [[ -f "$SCRIPT_DIR/uninstall_share_api.sh" ]] || die "Could not find deploy/share_api/uninstall_share_api.sh at $SCRIPT_DIR."
  [[ -f "$SCRIPT_DIR/upgrade_share_api.sh" ]] || die "Could not find deploy/share_api/upgrade_share_api.sh at $SCRIPT_DIR."
}

detect_privilege_mode() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    return
  fi

  die "This installer needs root privileges or sudo to install packages and configure the firewall."
}

detect_distro() {
  # shellcheck disable=SC1091
  . /etc/os-release

  DISTRO_ID="${ID:-}"
  DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID}"

  case "$DISTRO_ID" in
    ubuntu)
      DISTRO_FAMILY="ubuntu"
      ;;
    fedora)
      DISTRO_FAMILY="fedora"
      ;;
    almalinux)
      DISTRO_FAMILY="almalinux"
      ;;
    *)
      case " ${ID_LIKE:-} " in
        *" ubuntu "*|*" debian "*)
          DISTRO_FAMILY="ubuntu"
          ;;
        *" fedora "*|*" rhel "*|*" centos "*)
          DISTRO_FAMILY="almalinux"
          ;;
        *)
          die "Unsupported distribution: $DISTRO_NAME"
          ;;
      esac
      ;;
  esac
}

prompt() {
  local label="$1"
  local default_value="${2:-}"
  local answer=""

  if [[ -n "$default_value" ]]; then
    read -r -p "$label [$default_value]: " answer
    printf '%s' "${answer:-$default_value}"
  else
    read -r -p "$label: " answer
    printf '%s' "$answer"
  fi
}

prompt_nonempty() {
  local label="$1"
  local default_value="${2:-}"
  local value=""

  while true; do
    value="$(prompt "$label" "$default_value")"
    if [[ -n "${value// /}" ]]; then
      printf '%s' "$value"
      return
    fi

    warn "A value is required here."
  done
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

prompt_mode() {
  while true; do
    echo
    echo "Choose how this VPS should expose the remote share API:"
    echo "  1) Domain with automatic HTTPS through Caddy (recommended)"
    echo "  2) Raw IP / HTTP only"
    read -r -p "Select 1 or 2 [1]: " mode_answer
    mode_answer="${mode_answer:-1}"

    case "$mode_answer" in
      1)
        PUBLIC_MODE="domain"
        return
        ;;
      2)
        PUBLIC_MODE="raw_ip"
        return
        ;;
      *)
        warn "Please choose 1 or 2."
        ;;
    esac
  done
}

validate_host_value() {
  local value="$1"

  case "$PUBLIC_MODE" in
    domain)
      [[ "$value" =~ ^[A-Za-z0-9.-]+$ ]] && [[ "$value" == *.* ]]
      ;;
    raw_ip)
      [[ "$value" =~ ^[0-9.]+$ ]]
      ;;
    *)
      return 1
      ;;
  esac
}

prompt_public_host() {
  while true; do
    if [[ "$PUBLIC_MODE" == "domain" ]]; then
      PUBLIC_HOST="$(prompt_nonempty "Public domain name for the share API" "shares.example.com")"
    else
      PUBLIC_HOST="$(prompt_nonempty "Public IPv4 address for the VPS" "203.0.113.10")"
    fi

    if validate_host_value "$PUBLIC_HOST"; then
      return
    fi

    warn "That value does not look valid for the selected mode."
  done
}

prompt_port() {
  local label="$1"
  local default_value="$2"
  local value=""

  while true; do
    value="$(prompt_nonempty "$label" "$default_value")"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 65535 )); then
      printf '%s' "$value"
      return
    fi

    warn "Ports must be between 1 and 65535."
  done
}

prompt_percentage() {
  local label="$1"
  local default_value="$2"
  local value=""

  while true; do
    value="$(prompt_nonempty "$label" "$default_value")"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 100 )); then
      printf '%s' "$value"
      return
    fi

    warn "Please enter a percentage between 1 and 100."
  done
}

prompt_instance_name() {
  local default_value="$1"
  local value=""

  while true; do
    value="$(prompt_nonempty "Instance label used in alerts and generated local config" "$default_value")"
    if [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
      printf '%s' "$value"
      return
    fi

    warn "Use only letters, numbers, dots, underscores, or dashes for the instance label."
  done
}

prompt_webhook_kind() {
  while true; do
    echo
    echo "Choose the alert webhook style:"
    echo "  1) Generic JSON webhook"
    echo "  2) Slack incoming webhook"
    echo "  3) Discord webhook"
    read -r -p "Select 1, 2, or 3 [1]: " webhook_answer
    webhook_answer="${webhook_answer:-1}"

    case "$webhook_answer" in
      1)
        ALERT_WEBHOOK_KIND="generic"
        return
        ;;
      2)
        ALERT_WEBHOOK_KIND="slack"
        return
        ;;
      3)
        ALERT_WEBHOOK_KIND="discord"
        return
        ;;
      *)
        warn "Please choose 1, 2, or 3."
        ;;
    esac
  done
}

generate_secret() {
  openssl rand -hex 32
}

prompt_secret() {
  local label="$1"
  local generated_value="$2"

  if prompt_yes_no "$label" "y"; then
    printf '%s' "$generated_value"
  else
    prompt_nonempty "Enter a custom value"
  fi
}

gather_answers() {
  log "LewisMD remote share installer"
  log "Detected host distro: $DISTRO_NAME"
  echo

  prompt_mode
  prompt_public_host
  INSTANCE_NAME="$(prompt_instance_name "$(hostname -s 2>/dev/null || echo "remote-share-vps")")"

  if [[ "$PUBLIC_MODE" == "domain" ]]; then
    warn "Domain mode expects DNS to already point at this VPS and requires ports 80/443 to be reachable for automatic TLS."
    ACME_EMAIL="$(prompt "Contact email for TLS certificate registration (optional)" "")"
    HTTP_PORT="80"
    HTTPS_PORT="443"
    SITE_ADDRESS="$PUBLIC_HOST"
    PUBLIC_BASE="https://$PUBLIC_HOST"
    VERIFY_TLS="true"
  else
    warn "Raw IP mode is HTTP-only and should be treated as a fallback or test path."
    if ! prompt_yes_no "Continue with raw IP / HTTP mode?" "n"; then
      die "Installation cancelled."
    fi

    HTTP_PORT="$(prompt_port "Public HTTP port for the raw IP mode" "8080")"
    HTTPS_PORT=""
    SITE_ADDRESS="http://$PUBLIC_HOST"
    if [[ "$HTTP_PORT" == "80" ]]; then
      PUBLIC_BASE="http://$PUBLIC_HOST"
    else
      PUBLIC_BASE="http://$PUBLIC_HOST:$HTTP_PORT"
    fi
    VERIFY_TLS="false"
  fi

  STORAGE_HOST_PATH="$(prompt_nonempty "Host path for persisted share storage" "/var/lib/lewismd-share/storage")"
  CADDY_DATA_PATH="$(prompt_nonempty "Host path for Caddy state" "/var/lib/lewismd-share/caddy-data")"
  CADDY_CONFIG_PATH="$(prompt_nonempty "Host path for Caddy config state" "/var/lib/lewismd-share/caddy-config")"
  OPEN_FIREWALL="false"
  if prompt_yes_no "Open the required firewall ports automatically?" "y"; then
    OPEN_FIREWALL="true"
  fi

  API_TOKEN="$(prompt_secret "Generate the remote API bearer token automatically?" "$(generate_secret)")"
  SIGNING_SECRET="$(prompt_secret "Generate the remote request signing secret automatically?" "$(generate_secret)")"
  PUMA_MAX_THREADS="$(prompt_port "Puma max threads for the share API container" "5")"
  WEB_CONCURRENCY="$(prompt_port "Share API web worker count" "1")"

  ENABLE_MONITORING="false"
  if prompt_yes_no "Install the host-level monitoring timer?" "y"; then
    ENABLE_MONITORING="true"
    MONITOR_INTERVAL_MINUTES="$(prompt_port "Minutes between monitoring runs" "5")"
    MONITOR_DISK_THRESHOLD_PERCENT="$(prompt_percentage "Disk usage threshold percentage for alerts" "90")"

    if prompt_yes_no "Enable Healthchecks.io heartbeat pings?" "n"; then
      HEALTHCHECKS_PING_URL="$(prompt_nonempty "Healthchecks ping URL" "")"
    fi

    if prompt_yes_no "Enable outbound webhook alerts?" "n"; then
      prompt_webhook_kind
      ALERT_WEBHOOK_URL="$(prompt_nonempty "Webhook URL" "")"

      if [[ "$ALERT_WEBHOOK_KIND" == "generic" ]]; then
        if prompt_yes_no "Use an HMAC secret for the generic webhook?" "n"; then
          ALERT_WEBHOOK_SECRET="$(prompt_secret "Generate the generic webhook secret automatically?" "$(generate_secret)")"
        fi
      fi
    fi
  fi
}

confirm_plan() {
  echo
  echo "Installer summary"
  echo "  Mode:                  $PUBLIC_MODE"
  echo "  Public host:           $PUBLIC_HOST"
  echo "  Public base:           $PUBLIC_BASE"
  echo "  Instance label:        $INSTANCE_NAME"
  echo "  HTTP port:             $HTTP_PORT"
  if [[ -n "$HTTPS_PORT" ]]; then
    echo "  HTTPS port:            $HTTPS_PORT"
  fi
  echo "  Runtime dir:           $RUNTIME_DIR"
  echo "  Share storage path:    $STORAGE_HOST_PATH"
  echo "  Caddy data path:       $CADDY_DATA_PATH"
  echo "  Caddy config path:     $CADDY_CONFIG_PATH"
  echo "  Auto firewall config:  $OPEN_FIREWALL"
  echo "  Monitoring timer:      $ENABLE_MONITORING"
  if [[ "$ENABLE_MONITORING" == "true" ]]; then
    echo "  Monitor interval:      ${MONITOR_INTERVAL_MINUTES} minute(s)"
    echo "  Disk threshold:        ${MONITOR_DISK_THRESHOLD_PERCENT}%"
    if [[ -n "$HEALTHCHECKS_PING_URL" ]]; then
      echo "  Healthchecks:          enabled"
    else
      echo "  Healthchecks:          disabled"
    fi
    if [[ -n "$ALERT_WEBHOOK_URL" ]]; then
      echo "  Alert webhook kind:    ${ALERT_WEBHOOK_KIND:-generic}"
    else
      echo "  Alert webhook kind:    disabled"
    fi
  fi
  echo

  prompt_yes_no "Proceed with installation?" "y" || die "Installation cancelled."
}

install_host_dependencies() {
  install_core_packages
  install_docker_if_needed
  ensure_docker_service
  verify_docker_compose
  verify_systemd_if_monitoring_enabled
}

install_core_packages() {
  case "$DISTRO_FAMILY" in
    ubuntu)
      run_root apt-get update -y
      run_root apt-get install -y ca-certificates curl openssl
      ;;
    fedora|almalinux)
      run_root dnf -y install ca-certificates curl openssl
      ;;
  esac
}

install_docker_if_needed() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker and the Compose plugin are already available."
    return
  fi

  log "Installing Docker Engine and the Compose plugin..."

  case "$DISTRO_FAMILY" in
    ubuntu)
      run_root install -m 0755 -d /etc/apt/keyrings
      if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
        run_root curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        run_root chmod a+r /etc/apt/keyrings/docker.asc
      fi

      run_root bash -lc \
        "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" > /etc/apt/sources.list.d/docker.list"
      run_root apt-get update -y
      run_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    fedora)
      run_root dnf -y install dnf-plugins-core
      run_root dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      run_root dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    almalinux)
      run_root dnf -y install dnf-plugins-core
      run_root dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      run_root dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
  esac
}

ensure_docker_service() {
  run_root systemctl enable --now docker
  if ! run_root docker info >/dev/null 2>&1; then
    die "Docker is installed but the daemon is not responding."
  fi
}

verify_docker_compose() {
  run_root docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is not available after installation."
}

verify_systemd_if_monitoring_enabled() {
  [[ "$ENABLE_MONITORING" == "true" ]] || return
  command -v systemctl >/dev/null 2>&1 || die "systemctl is required to install the monitoring timer on this host."
}

prepare_runtime_layout() {
  run_root mkdir -p "$RUNTIME_DIR"
  run_root mkdir -p "$STORAGE_HOST_PATH" "$CADDY_DATA_PATH" "$CADDY_CONFIG_PATH"
}

backup_existing_runtime_if_needed() {
  if [[ ! -f "$RUNTIME_ENV_FILE" && ! -f "$RUNTIME_COMPOSE_FILE" && ! -f "$RUNTIME_CADDY_FILE" && ! -f "$RUNTIME_MONITOR_SERVICE_FILE" && ! -f "$RUNTIME_MONITOR_TIMER_FILE" ]]; then
    return
  fi

  local backup_dir="$RUNTIME_DIR/backups/$(date +%Y%m%d-%H%M%S)"
  run_root mkdir -p "$backup_dir"

  [[ -f "$RUNTIME_ENV_FILE" ]] && run_root cp "$RUNTIME_ENV_FILE" "$backup_dir/.env"
  [[ -f "$RUNTIME_COMPOSE_FILE" ]] && run_root cp "$RUNTIME_COMPOSE_FILE" "$backup_dir/compose.yml"
  [[ -f "$RUNTIME_CADDY_FILE" ]] && run_root cp "$RUNTIME_CADDY_FILE" "$backup_dir/Caddyfile"
  [[ -f "$RUNTIME_MONITOR_SERVICE_FILE" ]] && run_root cp "$RUNTIME_MONITOR_SERVICE_FILE" "$backup_dir/lewismd-share-monitor.service"
  [[ -f "$RUNTIME_MONITOR_TIMER_FILE" ]] && run_root cp "$RUNTIME_MONITOR_TIMER_FILE" "$backup_dir/lewismd-share-monitor.timer"

  log "Backed up the previous runtime config to $backup_dir"
}

write_runtime_env() {
  local temp_file
  temp_file="$(mktemp)"

  cat >"$temp_file" <<EOF
LEWISMD_SHARE_SITE_ADDRESS=$SITE_ADDRESS
LEWISMD_SHARE_PUBLIC_BASE=$PUBLIC_BASE
LEWISMD_SHARE_HTTP_PORT=$HTTP_PORT
LEWISMD_SHARE_STORAGE_HOST_PATH=$STORAGE_HOST_PATH
LEWISMD_SHARE_CADDY_DATA_PATH=$CADDY_DATA_PATH
LEWISMD_SHARE_CADDY_CONFIG_PATH=$CADDY_CONFIG_PATH
LEWISMD_SHARE_API_TOKEN=$API_TOKEN
LEWISMD_SHARE_SIGNING_SECRET=$SIGNING_SECRET
LEWISMD_SHARE_MAX_PAYLOAD_BYTES=200000
LEWISMD_SHARE_MAX_ASSET_BYTES=5000000
LEWISMD_SHARE_MAX_ASSET_COUNT=16
LEWISMD_SHARE_REPLAY_WINDOW_SECONDS=300
LEWISMD_SHARE_PUMA_MAX_THREADS=$PUMA_MAX_THREADS
WEB_CONCURRENCY=$WEB_CONCURRENCY
LEWISMD_SHARE_INSTANCE_NAME=$INSTANCE_NAME
LEWISMD_SHARE_MONITOR_INTERVAL_MINUTES=$MONITOR_INTERVAL_MINUTES
LEWISMD_SHARE_MONITOR_DISK_THRESHOLD_PERCENT=$MONITOR_DISK_THRESHOLD_PERCENT
EOF

  if [[ -n "$HTTPS_PORT" ]]; then
    printf 'LEWISMD_SHARE_HTTPS_PORT=%s\n' "$HTTPS_PORT" >>"$temp_file"
  fi

  if [[ -n "$ACME_EMAIL" ]]; then
    printf 'LEWISMD_SHARE_ACME_EMAIL=%s\n' "$ACME_EMAIL" >>"$temp_file"
  fi

  if [[ -n "$HEALTHCHECKS_PING_URL" ]]; then
    printf 'LEWISMD_SHARE_HEALTHCHECKS_PING_URL=%s\n' "$HEALTHCHECKS_PING_URL" >>"$temp_file"
  fi

  if [[ -n "$ALERT_WEBHOOK_KIND" ]]; then
    printf 'LEWISMD_SHARE_ALERT_WEBHOOK_KIND=%s\n' "$ALERT_WEBHOOK_KIND" >>"$temp_file"
  fi

  if [[ -n "$ALERT_WEBHOOK_URL" ]]; then
    printf 'LEWISMD_SHARE_ALERT_WEBHOOK_URL=%s\n' "$ALERT_WEBHOOK_URL" >>"$temp_file"
  fi

  if [[ -n "$ALERT_WEBHOOK_SECRET" ]]; then
    printf 'LEWISMD_SHARE_ALERT_WEBHOOK_SECRET=%s\n' "$ALERT_WEBHOOK_SECRET" >>"$temp_file"
  fi

  run_root cp "$temp_file" "$RUNTIME_ENV_FILE"
  rm -f "$temp_file"
}

write_runtime_caddyfile() {
  local temp_file
  temp_file="$(mktemp)"

  if [[ -n "$ACME_EMAIL" ]]; then
    cat >"$temp_file" <<EOF
{
  email $ACME_EMAIL
}

$SITE_ADDRESS {
  encode zstd gzip

  header {
    -Server
  }

  reverse_proxy share-api:9292

  log {
    output stdout
    format console
  }
}
EOF
  else
    cat >"$temp_file" <<EOF
$SITE_ADDRESS {
  encode zstd gzip

  header {
    -Server
  }

  reverse_proxy share-api:9292

  log {
    output stdout
    format console
  }
}
EOF
  fi

  run_root cp "$temp_file" "$RUNTIME_CADDY_FILE"
  rm -f "$temp_file"
}

write_runtime_compose() {
  local temp_file
  temp_file="$(mktemp)"

  cat >"$temp_file" <<EOF
name: $COMPOSE_PROJECT_NAME

services:
  share-api:
    build:
      context: "$SERVICE_SOURCE_DIR"
    restart: unless-stopped
    env_file:
      - "$RUNTIME_ENV_FILE"
    environment:
      LEWISMD_SHARE_STORAGE_PATH: /var/lib/lewismd-share
      PORT: 9292
    volumes:
      - "$STORAGE_HOST_PATH:/var/lib/lewismd-share"
    expose:
      - "9292"
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:9292/up"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    networks:
      - share-backplane

  caddy:
    image: caddy:2.9-alpine
    restart: unless-stopped
    env_file:
      - "$RUNTIME_ENV_FILE"
    depends_on:
      share-api:
        condition: service_healthy
    ports:
      - "$HTTP_PORT:80"
EOF

  if [[ -n "$HTTPS_PORT" ]]; then
    printf '      - "%s:443"\n' "$HTTPS_PORT" >>"$temp_file"
  fi

  cat >>"$temp_file" <<EOF
    volumes:
      - "$RUNTIME_CADDY_FILE:/etc/caddy/Caddyfile:ro"
      - "$CADDY_DATA_PATH:/data"
      - "$CADDY_CONFIG_PATH:/config"
    networks:
      - share-backplane

networks:
  share-backplane:
    name: lewismd-share-backplane
EOF

  run_root cp "$temp_file" "$RUNTIME_COMPOSE_FILE"
  rm -f "$temp_file"
}

write_runtime_monitoring_units() {
  [[ "$ENABLE_MONITORING" == "true" ]] || return

  local service_temp timer_temp monitor_command
  service_temp="$(mktemp)"
  timer_temp="$(mktemp)"
  monitor_command="$(printf '%q --runtime-dir %q --env-file %q --compose-file %q --quiet' "$SCRIPT_DIR/monitor_share_api.sh" "$RUNTIME_DIR" "$RUNTIME_ENV_FILE" "$RUNTIME_COMPOSE_FILE")"

  cat >"$service_temp" <<EOF
[Unit]
Description=LewisMD remote share API monitor
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$REPO_ROOT
ExecStart=/usr/bin/env bash -lc "$monitor_command"
EOF

  cat >"$timer_temp" <<EOF
[Unit]
Description=Run the LewisMD remote share API monitor periodically

[Timer]
OnBootSec=2m
OnUnitActiveSec=${MONITOR_INTERVAL_MINUTES}m
Persistent=true
Unit=lewismd-share-monitor.service

[Install]
WantedBy=timers.target
EOF

  run_root cp "$service_temp" "$RUNTIME_MONITOR_SERVICE_FILE"
  run_root cp "$timer_temp" "$RUNTIME_MONITOR_TIMER_FILE"
  rm -f "$service_temp" "$timer_temp"
}

configure_firewall_if_requested() {
  [[ "$OPEN_FIREWALL" == "true" ]] || return

  log "Configuring the firewall..."

  case "$DISTRO_FAMILY" in
    ubuntu)
      if ! command -v ufw >/dev/null 2>&1; then
        run_root apt-get update -y
        run_root apt-get install -y ufw
      fi

      if ! run_root ufw status | grep -q "Status: active"; then
        warn "ufw is currently inactive. Enabling it after opening SSH and the selected share ports."
        run_root ufw allow OpenSSH || run_root ufw allow 22/tcp
      fi
      run_root ufw allow "${HTTP_PORT}/tcp"
      if [[ -n "$HTTPS_PORT" ]]; then
        run_root ufw allow "${HTTPS_PORT}/tcp"
      fi
      if ! run_root ufw status | grep -q "Status: active"; then
        run_root ufw --force enable
      fi
      ;;
    fedora|almalinux)
      if ! command -v firewall-cmd >/dev/null 2>&1; then
        run_root dnf -y install firewalld
      fi

      run_root systemctl enable --now firewalld
      run_root firewall-cmd --permanent --add-port="${HTTP_PORT}/tcp"
      if [[ -n "$HTTPS_PORT" ]]; then
        run_root firewall-cmd --permanent --add-port="${HTTPS_PORT}/tcp"
      fi
      run_root firewall-cmd --reload
      ;;
  esac
}

start_stack() {
  log "Starting the remote share stack..."
  run_root docker compose -f "$RUNTIME_COMPOSE_FILE" --env-file "$RUNTIME_ENV_FILE" up -d --build
}

install_monitoring_timer_if_requested() {
  [[ "$ENABLE_MONITORING" == "true" ]] || return

  log "Installing the host-level monitoring timer..."
  run_root cp "$RUNTIME_MONITOR_SERVICE_FILE" /etc/systemd/system/lewismd-share-monitor.service
  run_root cp "$RUNTIME_MONITOR_TIMER_FILE" /etc/systemd/system/lewismd-share-monitor.timer
  run_root systemctl daemon-reload
  run_root systemctl enable --now lewismd-share-monitor.timer
}

wait_for_api_health() {
  local attempt

  for attempt in $(seq 1 30); do
    if run_root docker compose -f "$RUNTIME_COMPOSE_FILE" --env-file "$RUNTIME_ENV_FILE" exec -T share-api curl -fsS http://127.0.0.1:9292/up >/dev/null 2>&1; then
      return 0
    fi

    sleep 2
  done

  return 1
}

assert_port_listening() {
  local port="$1"
  local output=""

  if command -v ss >/dev/null 2>&1; then
    output="$(run_root ss -ltn)"
  elif command -v netstat >/dev/null 2>&1; then
    output="$(run_root netstat -ltn)"
  else
    warn "Could not verify listening ports because neither ss nor netstat is available."
    return 0
  fi

  grep -Eq "[:.]${port}[[:space:]].*LISTEN|LISTEN[[:space:]].*[:.]${port}" <<<"$output" || die "Expected port $port to be listening, but it was not detected."
}

verify_firewall_rules() {
  [[ "$OPEN_FIREWALL" == "true" ]] || return

  case "$DISTRO_FAMILY" in
    ubuntu)
      local ufw_status
      ufw_status="$(run_root ufw status)"
      grep -q "${HTTP_PORT}/tcp" <<<"$ufw_status" || die "Firewall validation failed for port $HTTP_PORT."
      if [[ -n "$HTTPS_PORT" ]]; then
        grep -q "${HTTPS_PORT}/tcp" <<<"$ufw_status" || die "Firewall validation failed for port $HTTPS_PORT."
      fi
      ;;
    fedora|almalinux)
      local firewalld_ports
      firewalld_ports="$(run_root firewall-cmd --list-ports)"
      grep -q "${HTTP_PORT}/tcp" <<<"$firewalld_ports" || die "Firewall validation failed for port $HTTP_PORT."
      if [[ -n "$HTTPS_PORT" ]]; then
        grep -q "${HTTPS_PORT}/tcp" <<<"$firewalld_ports" || die "Firewall validation failed for port $HTTPS_PORT."
      fi
      ;;
  esac
}

smoke_check_url() {
  if [[ "$PUBLIC_MODE" == "domain" ]]; then
    printf 'https://%s/up' "$PUBLIC_HOST"
  else
    printf 'http://127.0.0.1:%s/up' "$HTTP_PORT"
  fi
}

check_public_edge() {
  local url
  url="$(smoke_check_url)"

  if [[ "$PUBLIC_MODE" == "domain" ]]; then
    curl -kfsS --resolve "${PUBLIC_HOST}:443:127.0.0.1" "$url" >/dev/null
  else
    curl -fsS "$url" >/dev/null
  fi
}

run_smoke_checks() {
  log "Running post-install smoke checks..."

  wait_for_api_health || die "The share-api container never became healthy. Inspect docker compose logs for details."

  assert_port_listening "$HTTP_PORT"
  if [[ -n "$HTTPS_PORT" ]]; then
    assert_port_listening "$HTTPS_PORT"
  fi

  verify_firewall_rules

  if ! check_public_edge; then
    die "The public edge check failed. Caddy or the published ports may still be misconfigured."
  fi
}

run_initial_monitor_check_if_requested() {
  [[ "$ENABLE_MONITORING" == "true" ]] || return

  log "Running the first host-level monitoring pass..."
  run_root bash "$SCRIPT_DIR/monitor_share_api.sh" --runtime-dir "$RUNTIME_DIR" --env-file "$RUNTIME_ENV_FILE" --compose-file "$RUNTIME_COMPOSE_FILE"
  run_root systemctl is-active --quiet lewismd-share-monitor.timer || die "The monitoring timer was installed, but systemd does not report it as active."
}

write_local_config_summary() {
  local scheme="https"
  local api_port="$HTTPS_PORT"

  if [[ "$PUBLIC_MODE" == "raw_ip" ]]; then
    scheme="http"
    api_port="$HTTP_PORT"
  fi

  local temp_file
  temp_file="$(mktemp)"
  cat >"$temp_file" <<EOF
# Add these lines to the .fed file on the local LewisMD machine:
share_backend = remote
share_remote_api_scheme = $scheme
share_remote_api_host = $PUBLIC_HOST
share_remote_api_port = $api_port
share_remote_public_base = $PUBLIC_BASE
share_remote_api_token = $API_TOKEN
share_remote_signing_secret = $SIGNING_SECRET
share_remote_timeout_seconds = 10
share_remote_verify_tls = $VERIFY_TLS
share_remote_upload_assets = true
share_remote_instance_name = $INSTANCE_NAME
EOF

  run_root cp "$temp_file" "$RUNTIME_SUMMARY_FILE"
  rm -f "$temp_file"
}

print_success_summary() {
  echo
  log "Remote share API installation complete."
  echo
  echo "Runtime files:"
  echo "  Env file:      $RUNTIME_ENV_FILE"
  echo "  Compose file:  $RUNTIME_COMPOSE_FILE"
  echo "  Caddyfile:     $RUNTIME_CADDY_FILE"
  if [[ "$ENABLE_MONITORING" == "true" ]]; then
    echo "  Monitor unit:  $RUNTIME_MONITOR_SERVICE_FILE"
    echo "  Timer unit:    $RUNTIME_MONITOR_TIMER_FILE"
  fi
  echo "  Local .fed:    $RUNTIME_SUMMARY_FILE"
  echo
  echo "Useful commands:"
  echo "  docker compose -f \"$RUNTIME_COMPOSE_FILE\" --env-file \"$RUNTIME_ENV_FILE\" ps"
  echo "  docker compose -f \"$RUNTIME_COMPOSE_FILE\" --env-file \"$RUNTIME_ENV_FILE\" logs -f"
  echo "  docker compose -f \"$RUNTIME_COMPOSE_FILE\" --env-file \"$RUNTIME_ENV_FILE\" up -d --build"
  echo "  bash \"$SCRIPT_DIR/upgrade_share_api.sh\""
  echo "  bash \"$SCRIPT_DIR/backup_share_api.sh\""
  echo "  bash \"$SCRIPT_DIR/uninstall_share_api.sh\""
  if [[ "$ENABLE_MONITORING" == "true" ]]; then
    echo "  systemctl status lewismd-share-monitor.timer"
    echo "  bash \"$SCRIPT_DIR/monitor_share_api.sh\" --runtime-dir \"$RUNTIME_DIR\" --env-file \"$RUNTIME_ENV_FILE\" --compose-file \"$RUNTIME_COMPOSE_FILE\""
    echo "  bash \"$SCRIPT_DIR/send_share_api_alert.sh\" --env-file \"$RUNTIME_ENV_FILE\" --event service_down --status down --message \"manual test\""
  fi
  echo
  echo "Public base:"
  echo "  $PUBLIC_BASE"
  echo
  echo "Next step:"
  echo "  Copy the generated .fed block from:"
  echo "  $RUNTIME_SUMMARY_FILE"
  echo "  into the .fed file used by the local LewisMD app."
  echo "  Operator guide: $REPO_ROOT/docs/remote_share_api.md"
}

main "$@"
