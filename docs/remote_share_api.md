# Remote Share API

This guide documents the optional VPS-side remote publishing flow for LewisMD.

It is meant for operators who want to:

- keep LewisMD itself local and private
- publish selected shared notes to a small public-facing VPS service
- manage that VPS service with guided scripts instead of hand-editing the stack

The remote service is intentionally narrow. It is **not** a second full LewisMD
instance. It only accepts authenticated share publish/update/revoke requests and
serves read-only public share snapshots.

## Reader Experience

Remote public share pages now render the full LewisMD shared-reader interface:

- shared-note title chrome
- theme picker
- locale picker
- export/share actions
- display controls for zoom, text width, and font family
- a same-origin snapshot iframe that holds the sanitized rendered note

The VPS still owns the outer page. LewisMD does not blindly upload an arbitrary
outer HTML document and publish it as-is.

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
- `deploy/share_api/runtime/nginx-lewismd-share.conf`
- `deploy/share_api/runtime/lewismd_remote_share_config.fed.txt`
- `deploy/share_api/runtime/lewismd-share-monitor.service`
- `deploy/share_api/runtime/lewismd-share-monitor.timer`
- `deploy/share_api/runtime/lewismd-share-sweeper.service`
- `deploy/share_api/runtime/lewismd-share-sweeper.timer`
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
- prompts for the edge mode and required operator choices
- writes the runtime deployment files under `deploy/share_api/runtime/`
- optionally configures the firewall
- boots the stack and validates `/up`
- installs the expired-share sweeper timer
- optionally installs the host-level monitoring timer
- prints the exact `.fed` values needed by the local LewisMD machine

### Edge Modes

The installer supports two deployment topologies:

- `managed_caddy`
  - Caddy is part of the generated Docker Compose stack
  - the installer owns the public `80/443` edge for this service
- `external_reverse_proxy`
  - the `share-api` container binds to `127.0.0.1:<internal_port>`
  - an existing reverse proxy such as Nginx forwards the public host to it
  - the installer generates `deploy/share_api/runtime/nginx-lewismd-share.conf`

The `external_reverse_proxy` mode is the right choice when the VPS already runs
Nginx or another shared public edge.

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
- `share_remote_expiration_days`
- `share_remote_instance_name`

`share_remote_expiration_days` controls how long newly published or refreshed
remote shares stay live before they expire automatically.

## Share Link Model

The remote share identity model is intentionally simple:

- different notes get different public links
- many different notes can be shared at the same time
- the same note keeps one active public link and refreshes that existing link

So if you share five different notes, you will get five different public URLs.
Those URLs can all be open and accessible simultaneously.

Refreshing a remote share extends its expiration from the current time again.
Revoking a remote share removes it immediately instead of waiting for the
expiry sweep.

## Expiry Sweep

Remote share expiry is enforced in two ways:

- the share API immediately serves expired or revoked links as `404`
- the VPS runs a periodic sweeper timer that deletes expired metadata,
  snapshots, assets, and indexes from disk

The generated systemd units are:

- `lewismd-share-sweeper.service`
- `lewismd-share-sweeper.timer`

Relevant runtime settings include:

- `LEWISMD_SHARE_EXPIRY_SWEEP_MINUTES`
- `LEWISMD_SHARE_MAX_EXPIRATION_DAYS`
- `LEWISMD_SHARE_MONITOR_SWEEPER_STALE_MINUTES`
- `LEWISMD_SHARE_MONITOR_STORAGE_GROWTH_MB`

The public share shell and snapshot routes are also served with strict
`Cache-Control: no-store` headers so expired or revoked notes do not linger as
"ghost" pages in normal browser or proxy caches.

## Legacy Share Migration

Older remote shares that were published before the full shared-reader rollout
still render through a compatibility path.

Migration behavior:

- legacy fragment-only shares continue to work
- refreshing an existing legacy share republishes it as the newer snapshot
  package format
- refreshed shares keep their existing public token for the same note path

This keeps already-shared links alive while gradually moving them onto the newer
reader shell.

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
- expiry sweeper freshness and failure state
- storage-growth anomalies between monitor runs

In `external_reverse_proxy` mode, the installer may defer enabling the monitor
timer until the generated reverse-proxy config has been installed and the public
edge actually responds.

When enabled through the installer, the monitor is installed as:

- `lewismd-share-monitor.service`
- `lewismd-share-monitor.timer`

Supported outbound notifications:

- generic JSON webhook
- Slack incoming webhook
- Discord webhook
- Healthchecks.io heartbeat and fail pings

Additional transition alerts include:

- `cleanup_failed`
- `cleanup_stale`
- `cleanup_stopped`
- `cleanup_recovered`
- `storage_growth_high`

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
- refreshes the Caddy image when the deployment uses `managed_caddy`
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

The upgrade helper now also reapplies ownership to the persisted share-storage
path and runs a container-side write probe before it reports success. That
prevents the common "read endpoints work, but publishing returns a server 500"
failure mode caused by storage paths drifting back to `root` ownership.

## Backup

To create a restorable backup archive:

```bash
bash deploy/share_api/backup_share_api.sh
```

The backup archive includes:

- persisted share storage
- generated runtime config files
- Caddy data/config state when present
- the generated Nginx example when present
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
- remove the monitoring timer, sweeper timer, and their systemd unit files
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
- or the generated reverse-proxy config if you are using an external reverse proxy

### LewisMD says `Invalid share request` when creating a remote share link

This usually means the local app reached the VPS, but the VPS rejected or failed
the write request. Start with:

```bash
docker compose -f deploy/share_api/runtime/compose.yml --env-file deploy/share_api/runtime/.env logs --tail=200 share-api
docker compose -f deploy/share_api/runtime/compose.yml --env-file deploy/share_api/runtime/.env exec -T share-api bundle exec ruby bin/verify_storage_write.rb
```

If the write probe fails, the most common cause is storage ownership drifting
away from the container user (`10001:10001`). Fix it with:

```bash
sudo chown -R 10001:10001 /var/lib/lewismd-share/storage
bash deploy/share_api/upgrade_share_api.sh --yes
```

If the VPS already runs Nginx or another shared reverse proxy, make sure the
runtime is still in `external_reverse_proxy` mode. Re-running the installer in
the managed Caddy mode on a shared VPS can leave the runtime pointing at the
wrong public-edge topology.

If the share-api logs show:

```text
NoMethodError: undefined method `presence'
```

then the VPS is still running an older standalone share-api build that used a
Rails-only helper inside the Rack app. Pull the latest repo version and rebuild
the share-api container:

```bash
git pull
bash deploy/share_api/upgrade_share_api.sh --yes
```

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

### Need to confirm the expiry janitor is running

Check:

```bash
systemctl status lewismd-share-sweeper.timer
systemctl status lewismd-share-sweeper.service
```

The monitor also reads the janitor state report written under the persisted
share storage path, so a timer that is active but no longer producing fresh
cleanup reports will still trigger a stale-cleanup alert.

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
