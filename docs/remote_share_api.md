# Remote Share API

This guide documents the optional VPS-side remote publishing flow for LewisMD.

It is meant for operators who want to:

- keep LewisMD itself local and private
- publish selected shared notes to a small public-facing VPS service
- manage that VPS service with guided scripts instead of hand-editing the stack

The remote service is intentionally narrow. It is **not** a second full LewisMD
instance. It only accepts authenticated share publish/update/revoke requests and
serves read-only public share snapshots.

## What Lives Where

Tracked deployment assets:

- [install_share_api.sh](/C:/Users/Admin/Documents/GitHub/LewisMD/deploy/share_api/install_share_api.sh)
- [upgrade_share_api.sh](/C:/Users/Admin/Documents/GitHub/LewisMD/deploy/share_api/upgrade_share_api.sh)
- [backup_share_api.sh](/C:/Users/Admin/Documents/GitHub/LewisMD/deploy/share_api/backup_share_api.sh)
- [uninstall_share_api.sh](/C:/Users/Admin/Documents/GitHub/LewisMD/deploy/share_api/uninstall_share_api.sh)
- [monitor_share_api.sh](/C:/Users/Admin/Documents/GitHub/LewisMD/deploy/share_api/monitor_share_api.sh)
- [send_share_api_alert.sh](/C:/Users/Admin/Documents/GitHub/LewisMD/deploy/share_api/send_share_api_alert.sh)
- [compose.yml](/C:/Users/Admin/Documents/GitHub/LewisMD/deploy/share_api/compose.yml)
- [Caddyfile](/C:/Users/Admin/Documents/GitHub/LewisMD/deploy/share_api/Caddyfile)
- [.env.example](/C:/Users/Admin/Documents/GitHub/LewisMD/deploy/share_api/.env.example)

Generated runtime files on the VPS:

- `deploy/share_api/runtime/.env`
- `deploy/share_api/runtime/compose.yml`
- `deploy/share_api/runtime/Caddyfile`
- `deploy/share_api/runtime/lewismd_remote_share_config.fed.txt`
- `deploy/share_api/runtime/lewismd-share-monitor.service`
- `deploy/share_api/runtime/lewismd-share-monitor.timer`
- `deploy/share_api/runtime/monitor/state.env`

The whole `deploy/share_api/runtime/` directory is intentionally ignored by Git.

## Install

On the VPS, from the LewisMD repository root:

```bash
bash deploy/share_api/install_share_api.sh
```

What the installer does:

- detects Ubuntu, Fedora, or AlmaLinux
- installs Docker, Compose, and basic host dependencies if needed
- prompts for the public host mode and required operator choices
- writes the runtime deployment files under `deploy/share_api/runtime/`
- optionally configures the firewall
- boots the stack and validates `/up`
- optionally installs the host-level monitoring timer
- prints the exact `.fed` values needed by the local LewisMD machine

## Local LewisMD Configuration

After installation, copy the generated block from:

```text
deploy/share_api/runtime/lewismd_remote_share_config.fed.txt
```

into the `.fed` file used by the local LewisMD app.

The key values include:

- `share_backend = remote`
- `share_remote_api_scheme`
- `share_remote_api_host`
- `share_remote_api_port`
- `share_remote_public_base`
- `share_remote_api_token`
- `share_remote_signing_secret`
- `share_remote_verify_tls`
- `share_remote_upload_assets`
- `share_remote_instance_name`

## Health And Monitoring

The remote share stack uses two health layers:

- container-level `/up` checks inside Docker
- host-level monitoring outside Docker

The host-level monitor is:

- [monitor_share_api.sh](/C:/Users/Admin/Documents/GitHub/LewisMD/deploy/share_api/monitor_share_api.sh)

It checks:

- the public `/up` URL
- the local edge path from the VPS host
- the Compose-managed service state
- disk usage on the persisted share storage path

When enabled through the installer, the monitor is installed as:

- `lewismd-share-monitor.service`
- `lewismd-share-monitor.timer`

Supported outbound notifications:

- generic JSON webhook
- Slack incoming webhook
- Discord webhook
- Healthchecks.io heartbeat and fail pings

Alerts are transition-only by default, so repeated healthy or unhealthy runs do
not spam the configured destination.

## Upgrade

To rebuild the share API from the current repo checkout and restart the stack:

```bash
bash deploy/share_api/upgrade_share_api.sh
```

Behavior:

- optionally creates a pre-upgrade backup first
- sends `deploy_started`, `deploy_succeeded`, or `deploy_failed` alerts when a
  webhook is configured
- refreshes the Caddy image
- rebuilds the `share-api` image with the current source tree
- restarts the stack with Docker Compose
- verifies `/up`
- runs the host-level monitor after the upgrade unless you skip it explicitly

Useful flags:

```bash
bash deploy/share_api/upgrade_share_api.sh --yes
bash deploy/share_api/upgrade_share_api.sh --skip-backup
bash deploy/share_api/upgrade_share_api.sh --skip-monitor-check
```

## Backup

To create a restorable backup archive:

```bash
bash deploy/share_api/backup_share_api.sh
```

The backup archive includes:

- persisted share storage
- generated runtime config files
- Caddy data/config state
- backup metadata

By default it writes to:

```text
deploy/share_api/runtime/backups/manual/
```

You can override the output directory:

```bash
bash deploy/share_api/backup_share_api.sh --output-dir /srv/backups/lewismd-share
```

Each backup writes:

- `lewismd-share-backup-YYYYmmdd-HHMMSS.tar.gz`
- a matching `.sha256` checksum file

### Restore Notes

There is no dedicated restore script yet. A practical restore path is:

1. unpack the backup archive on the replacement VPS
2. restore the saved host-data directories to their original locations
3. restore the runtime files under `deploy/share_api/runtime/`
4. run `docker compose -f deploy/share_api/runtime/compose.yml --env-file deploy/share_api/runtime/.env up -d`
5. rerun the installer only if you intentionally want to regenerate runtime files

## Uninstall

To remove the remote share deployment conservatively:

```bash
bash deploy/share_api/uninstall_share_api.sh
```

Safe defaults:

- stop and remove the Docker stack
- remove the monitoring timer and systemd unit files
- keep share storage
- keep Caddy state
- keep generated runtime files

Useful flags:

```bash
bash deploy/share_api/uninstall_share_api.sh --yes
bash deploy/share_api/uninstall_share_api.sh --delete-runtime
bash deploy/share_api/uninstall_share_api.sh --delete-storage
bash deploy/share_api/uninstall_share_api.sh --delete-caddy-state
```

If you choose to delete persisted data, create a backup first unless you are
intentionally discarding the deployment state.

## Troubleshooting

### Public `/up` is failing

Check:

```bash
docker compose -f deploy/share_api/runtime/compose.yml --env-file deploy/share_api/runtime/.env ps
docker compose -f deploy/share_api/runtime/compose.yml --env-file deploy/share_api/runtime/.env logs -f
bash deploy/share_api/monitor_share_api.sh
```

If the local edge works but the public URL does not, look at:

- DNS
- public firewall rules
- TLS/certificate state in Caddy

### Monitoring timer is not running

Check:

```bash
systemctl status lewismd-share-monitor.timer
systemctl status lewismd-share-monitor.service
```

If needed, reload and re-enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now lewismd-share-monitor.timer
```

### Need to test the alert path manually

```bash
bash deploy/share_api/send_share_api_alert.sh \
  --env-file deploy/share_api/runtime/.env \
  --event service_down \
  --status down \
  --message "manual test"
```

### Need to re-run the monitor manually

```bash
bash deploy/share_api/monitor_share_api.sh \
  --runtime-dir deploy/share_api/runtime \
  --env-file deploy/share_api/runtime/.env \
  --compose-file deploy/share_api/runtime/compose.yml
```

### Need to redeploy after a repo update

```bash
git pull
bash deploy/share_api/upgrade_share_api.sh
```

## Important Limitations

- The monitoring, upgrade, backup, and uninstall scripts are Linux/VPS-oriented.
- The current validation in this repository covers the generated Compose
  configuration and the Ruby-side remote-share flow, but not a full end-to-end
  Linux systemd run from this Windows workstation.
- The remote share API remains intentionally narrow. It is not meant to grow
  into a second full LewisMD app on the VPS.
