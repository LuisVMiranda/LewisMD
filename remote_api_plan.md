# LewisMD Remote Share API Plan

## Purpose

This document defines the revised implementation plan for LewisMD's optional
remote publishing system.

The original remote-share rollout proved the narrow VPS relay, signed write
contract, asset uploads, installer, monitoring, and Windows/local launcher
integration. The next objective is different:

- keep LewisMD local-first and private
- keep the VPS as a small read-only share relay
- replace the current minimal remote fragment view with the full shared-reader UI
- add automatic expiration and server-side cleanup so remote shares do not pile
  up forever

This plan is intentionally architecture-first. It extends the systems already in
the repository instead of creating a second parallel share stack.

## Current State Rebaseline

### What already exists

- local and remote share backends behind the same `/shares` browser contract
- a standalone Rack relay under `services/share_api`
- signed write requests, replay protection, and filesystem-backed VPS storage
- image asset upload support
- installer, monitoring, backup, upgrade, and uninstall tooling

### What needs to change

The current remote relay still stores and serves a sanitized HTML fragment
inside a minimal public shell. That is secure, but it does not match the richer
shared-reader experience already available locally.

The new target is:

- a server-owned remote share shell that visually and behaviorally matches the
  existing local shared-reader UI
- a versioned snapshot package instead of a fragment-only payload
- built-in expiration and cleanup
- first-class support for both managed Caddy deployments and existing Nginx
  reverse-proxy VPS setups

## Architecture Alignment

This plan has been reconciled against:

- [AGENTS.md](C:/Users/Admin/Documents/GitHub/LewisMD/AGENTS.md)
- [CLAUDE.md](C:/Users/Admin/Documents/GitHub/LewisMD/CLAUDE.md)
- [antigravity.md](C:/Users/Admin/Documents/GitHub/LewisMD/antigravity.md)

### Existing systems we must reuse

#### Config and runtime settings

Configuration stays in:

- [app/models/config.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/models/config.rb)

Rules:

- continue using `Config.new.get("key")`
- continue using `.fed` as the runtime override surface
- do not introduce direct `ENV` reads in the main Rails app for configurable
  behavior

#### Browser share UX

The browser already talks to the local Rails app through:

- [app/controllers/shares_controller.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/controllers/shares_controller.rb)
- [app/javascript/controllers/app_controller.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/controllers/app_controller.js)
- [app/javascript/controllers/export_menu_controller.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/controllers/export_menu_controller.js)

That contract must stay unchanged:

- `POST /shares`
- `PATCH /shares/:path`
- `DELETE /shares/:path`
- `GET /shares/:path`

The browser must continue talking only to the local Rails app.

#### Preview/export rendering pipeline

The source material for remote publishing must continue to come from:

- [app/javascript/controllers/preview_controller.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/controllers/preview_controller.js)
- [app/javascript/lib/rendered_document_payload.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/lib/rendered_document_payload.js)
- [app/javascript/lib/export_document_builder.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/lib/export_document_builder.js)

Rules:

- do not invent a second markdown renderer
- do not move note rendering responsibility into the VPS
- do not create a separate browser-only remote rendering path

#### Local shared-reader UI

The existing share reader already lives in:

- [app/views/shares/show.html.erb](C:/Users/Admin/Documents/GitHub/LewisMD/app/views/shares/show.html.erb)
- [app/assets/tailwind/components/share_view.css](C:/Users/Admin/Documents/GitHub/LewisMD/app/assets/tailwind/components/share_view.css)
- [app/javascript/controllers/share_view_controller.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/controllers/share_view_controller.js)

This is the UI target for remote shares. We should extract and adapt it, not
recreate it from scratch.

#### Existing controller/service layering

The current local share layering is already correct:

- [app/controllers/shares_controller.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/controllers/shares_controller.rb)
- [app/services/share_service.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/services/share_service.rb)
- [app/services/share_provider_selector.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/services/share_provider_selector.rb)
- [app/services/share_publishers/remote_share_provider.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/services/share_publishers/remote_share_provider.rb)
- [app/services/remote_share_registry_service.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/services/remote_share_registry_service.rb)

Rules:

- keep controllers thin
- keep remote mode behind provider selection
- keep local share metadata registry filesystem-backed
- do not introduce a database

#### Existing VPS relay

The remote service already exists in:

- [services/share_api/app.rb](C:/Users/Admin/Documents/GitHub/LewisMD/services/share_api/app.rb)
- [services/share_api/lib/share_api/storage.rb](C:/Users/Admin/Documents/GitHub/LewisMD/services/share_api/lib/share_api/storage.rb)

This remains the runtime boundary for public sharing. The work ahead is an
evolution of this relay, not a replacement.

### Real-world deployment finding

The first installer assumed bundled Caddy would own public `80/443`. The real
VPS validation showed an important supported topology:

- `managed_caddy`
- `external_reverse_proxy`

`external_reverse_proxy` must be a first-class install mode because many VPSes
already run Nginx for other subdomains.

## Product Decisions

### 1. Remote publishing remains optional

Default behavior remains:

- `share_backend = local`

Users explicitly opt into remote publishing in `.fed`.

### 2. The browser still does not talk directly to the VPS

The local Rails app remains the only component that:

- reads `.fed`
- knows API token and signing secret
- publishes to the VPS

### 3. The remote page will use the full shared-reader UI

This is now an explicit requirement.

However, the VPS should still own the outer public page. We will not blindly
upload and serve arbitrary client-provided outer HTML.

The right model is:

- upload a versioned snapshot package
- store a sanitized snapshot document for iframe rendering
- render the full shared-reader shell from server-owned assets and metadata

### 4. One active link per note remains the v1 behavior

The current identity model reuses one token per note path on refresh.

This plan keeps that behavior:

- different notes -> different links
- many notes can be shared simultaneously
- the same note refreshes the same link

Multiple concurrent public links for the same note are out of scope for this
plan and should be treated as a separate feature if needed later.

### 5. Expiration and cleanup are first-class requirements

Remote shares must support:

- configurable expiration from the local app
- immediate expiry enforcement on read
- physical deletion by a sweeper/janitor process
- removal of associated assets and indexes

### 6. The VPS remains a narrow read-only relay

The remote service must not expose:

- note trees
- editing
- local-only dialogs or settings
- templates
- backups
- AI features

Only publish/update/revoke and public share reading are in scope.

## Required `.fed` Settings

These keys belong in:

- [app/models/config.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/models/config.rb)

### Non-sensitive

- `share_backend = local`
- `share_remote_api_scheme = https`
- `share_remote_api_host = shares.example.com`
- `share_remote_api_port = 443`
- `share_remote_public_base = https://shares.example.com`
- `share_remote_timeout_seconds = 10`
- `share_remote_verify_tls = true`
- `share_remote_upload_assets = true`
- `share_remote_instance_name = my-vps`
- `share_remote_expiration_days = 30`
- `share_remote_healthchecks_ping_url = `
- `share_remote_alert_webhook_url = `

### Sensitive

- `share_remote_api_token = `
- `share_remote_signing_secret = `
- `share_remote_alert_webhook_secret = `

### Expiration semantics

- `share_remote_expiration_days` is the local default TTL for new and refreshed
  remote shares
- recommended default: `30`
- `0` may be treated as "no automatic expiration" if we decide to preserve that
  operator choice
- successful refresh extends expiration from the current time again

## Remote Share Contract

### Capability endpoint

- `GET /api/v1/capabilities`

Capabilities should include at least:

- API version
- minimum supported client version
- feature flags
- max payload bytes
- max asset bytes
- max asset count

New feature flags for the updated contract:

- `asset_uploads`
- `full_share_shell`
- `expiring_shares`

### Health endpoint

- `GET /up`

Used by:

- installer smoke tests
- monitoring
- reverse proxy validation
- operator troubleshooting

### Authenticated write endpoints

- `POST /api/v1/shares`
- `PUT /api/v1/shares/:token`
- `DELETE /api/v1/shares/:token`

### Public read endpoints

- `GET /s/:token`
- `GET /snapshots/:token`
- `GET /assets/:token/:asset_name`

## Snapshot Package Design

### Local app sends

- note path
- logical note identifier
- title
- `snapshot_version`
- `shell_version`
- `snapshot_document_html`
- shell metadata and display metadata
- theme/locale hints
- content hash
- asset manifest
- uploaded assets
- requested expiration timestamp or TTL-derived `expires_at`

### Local app does not send

- full editable note state
- app config
- folder metadata
- secrets
- arbitrary third-party scripts

### Snapshot package model

The package should separate:

- server-owned outer shell
- sanitized stored snapshot document for iframe rendering
- asset storage
- share metadata

That keeps the remote page expressive without turning the VPS into a blind HTML
host.

### Shell payload fields

Expected shell metadata should include at least:

- title
- locale
- theme id
- display defaults if needed
- any version markers required by the remote shell bundle

## Share States

Remote shares should have clear lifecycle states:

- `active`
- `stale`
- `expired`
- `revoked`
- `deleted`

### Meaning

- `active`: current public snapshot is valid
- `stale`: last refresh failed, but last known public URL remains valid
- `expired`: TTL has passed and public reads must stop immediately
- `revoked`: explicitly disabled by the user
- `deleted`: files have been physically removed

## Expiration And Cleanup Contract

### Immediate enforcement

On every public read:

- if share is revoked -> return uniform `404`
- if share is expired -> return uniform `404`
- if share is invalid or missing -> return uniform `404`

This prevents ghost notes from remaining accessible while waiting for cleanup.

### Physical cleanup

A janitor/sweeper job must remove:

- share metadata
- stored snapshot document
- assets for the token
- identity/path index entries
- any stale bookkeeping records that are safe to remove

### Refresh behavior

Successful refresh should:

- keep the same token for the same note path
- extend `expires_at`
- replace the stored snapshot package atomically

### Revoke behavior

Revoke should:

- stop public serving immediately
- remove associated files
- remove indexes
- preserve uniform public `404`

### Cache behavior

To avoid ghost notes:

- shell and snapshot routes should use strict no-store or equivalent no-cache
  headers
- assets should not outlive the share lifecycle
- cleanup must remove the physical asset files too

## Remote Storage Layout

Suggested filesystem layout:

- `/var/lib/lewismd-share/shares/<token>.json`
- `/var/lib/lewismd-share/path-index/<path-hash>.json`
- `/var/lib/lewismd-share/snapshots/<token>/index.html`
- `/var/lib/lewismd-share/assets/<token>/<sha>-<filename>`
- `/var/lib/lewismd-share/nonces/<request-id>.json`

Optional if needed later:

- `/var/lib/lewismd-share/tombstones/<token>.json`

### Storage rules

- use atomic writes
- fsync before rename when practical
- stage assets before promotion
- delete orphaned assets on update/revoke/expiry
- never partially replace a live share

## UI Reuse Strategy

### Existing UI target

Remote shares should match the local reader in:

- [app/views/shares/show.html.erb](C:/Users/Admin/Documents/GitHub/LewisMD/app/views/shares/show.html.erb)
- [app/assets/tailwind/components/share_view.css](C:/Users/Admin/Documents/GitHub/LewisMD/app/assets/tailwind/components/share_view.css)
- [app/javascript/controllers/share_view_controller.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/controllers/share_view_controller.js)

### Known extraction challenges

The current local share view still depends on:

- [app/views/notes/_export_menu.html.erb](C:/Users/Admin/Documents/GitHub/LewisMD/app/views/notes/_export_menu.html.erb)
- [app/javascript/controllers/theme_controller.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/controllers/theme_controller.js)
- [app/javascript/controllers/locale_controller.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/controllers/locale_controller.js)
- Rails translation/config endpoints
- inline Tailwind utility classes embedded in the ERB shell

### Design decision

We should:

- extract a reusable share shell structure from the existing local reader
- create remote-safe static JS/CSS for theme, locale, export, and display
  controls
- preserve the current local UX while removing Rails-only assumptions from the
  parts the VPS must reuse

We should not:

- invent a second unrelated remote UI
- upload the literal client outer page and serve it blindly

## Authentication And Replay Protection

Every write request should include:

- `Authorization: Bearer <token>`
- `X-LewisMD-Timestamp`
- `X-LewisMD-Request-Id`
- `X-LewisMD-Signature`

Validation rules remain:

- bearer token must match configured API token
- HMAC signature must match
- timestamp must be inside replay window
- request ID must not be reused

## Security Requirements

### Mandatory

- HTTPS in production
- long random API token
- HMAC signing secret
- strict CSP for public shell
- strict no-cache handling for shell and snapshot routes
- request size limits
- asset type allowlist
- uniform public `404`
- no browser exposure of remote secrets

### Strongly recommended

- use a domain instead of raw IP
- support both Caddy and existing reverse proxies cleanly
- keep the app internal behind the reverse proxy in external-proxy mode

### Explicit pitfalls to avoid

- exposing the full LewisMD app publicly
- trusting uploaded outer HTML
- mixing public token handling with admin auth
- forgetting to delete expired assets
- assuming Caddy owns `80/443` on every VPS

## Edge And Deployment Modes

### Managed edge

- `managed_caddy`

Use when the share relay owns public `80/443`.

### Existing reverse proxy

- `external_reverse_proxy`

Use when the VPS already has Nginx or another edge service.

Behavior:

- bind the share relay to `127.0.0.1:<internal_port>`
- skip bundled public edge
- generate ready-to-use Nginx guidance/snippet
- still generate the local `.fed` summary file

## Monitoring And Operations

Monitoring must cover:

- `/up` availability
- container health
- reverse proxy reachability
- cleanup/janitor health
- disk growth from stored shares/assets

Suggested additional alerts:

- cleanup failure
- sweep backlog or storage growth anomaly
- certificate or reverse-proxy mismatch

## Installer Design Updates

The installer remains:

- [deploy/share_api/install_share_api.sh](C:/Users/Admin/Documents/GitHub/LewisMD/deploy/share_api/install_share_api.sh)

New required behavior:

- ask which edge mode to use
- support `managed_caddy` and `external_reverse_proxy`
- ask for expiration-related operator defaults if needed
- install or configure the janitor/sweeper timer
- generate the local `.fed` summary even when using external reverse proxy mode

Relevant env settings should include:

- `LEWISMD_SHARE_MAX_EXPIRATION_DAYS`
- `LEWISMD_SHARE_EXPIRY_SWEEP_MINUTES`

## Backward Compatibility

Already-published fragment-only remote shares should continue to render during
the transition.

Compatibility rule:

- legacy shares may continue using the old minimal rendering path
- once refreshed, they should be rewritten to the new snapshot-package format

This avoids breaking already shared public links during rollout.

## Recommended Implementation Phases

### Phase 1: Lock the new contract

- update this plan
- define the full-shell snapshot package contract
- define expiration semantics and cleanup behavior
- define compatibility and deployment-mode expectations

### Phase 2: Add expiration config to LewisMD

- add `share_remote_expiration_days`
- update `.fed` template/upgrade flow
- validate numeric behavior

### Phase 3: Refactor the local share shell for reuse

- extract the current local reader structure
- reduce Rails-only coupling
- move more styling responsibility into reusable share-view CSS

### Phase 4: Create a remote-safe reader UI bundle

- adapt the existing share-view behavior
- extract remote-safe theme, locale, export, and display controls
- remove dependence on Rails-only endpoints

### Phase 5: Expand the local publish payload

- evolve the current fragment builder into a snapshot package builder
- preserve current asset/metadata logic
- send shell metadata plus stored snapshot document and expiration data

### Phase 6: Expand remote storage and serving

- store full snapshot packages
- add snapshot route
- keep shell route server-owned
- keep legacy fragment fallback during migration

### Phase 7: Add expiry enforcement and cleanup

- enforce expired/revoked `404`s immediately
- add janitor cleanup for shares, assets, and indexes
- make revoke/expiry deletion reliable

### Phase 8: Render the full remote shared-reader UI

- replace the minimal remote public shell
- match the existing local reader UX
- keep CSP and public-surface hardening in place

### Phase 9: Update installer and deployment modes

- add `managed_caddy` and `external_reverse_proxy`
- generate Nginx guidance when needed
- wire in janitor scheduling and expiration env values

### Phase 10: Extend monitoring and operations

- monitor cleanup health and storage growth
- add operational visibility around expirations

### Phase 11: Tests, migration, and docs

- add coverage for config, payloads, storage, expiry, cleanup, rendering, and
  deployment modes
- update README, operator docs, and rollout docs

## Closeout Notes

With Phase 11 complete, the implemented remote-share system now provides:

- the full shared-reader UI on the VPS
- one active remote link per note path
- simultaneous sharing for many different notes
- configurable expiration with immediate 404 enforcement and janitor cleanup
- backward-compatible rendering for older fragment-only remote shares until
  they are refreshed
- installer/deployment support for both bundled Caddy and existing reverse
  proxies such as Nginx

Residual full-suite failures outside the remote-share area remain existing
repository baseline work and are not part of this rollout.

## Acceptance Criteria For This Replan

Before implementation starts, this revised plan should lock these choices:

- full remote shared-reader UI is in scope
- one active link per note remains the current identity model
- many different notes can be shared simultaneously
- expiration and cleanup are mandatory
- remote rendering stays server-owned
- deployment must support both clean VPS installs and existing Nginx setups

## Recommended Starting Boundary

Start with:

- contract/documentation lock
- expiration config addition
- local share-shell extraction

That sequence gives the rest of the implementation a stable contract and avoids
rewriting the remote service before the reusable UI boundary is clear.
