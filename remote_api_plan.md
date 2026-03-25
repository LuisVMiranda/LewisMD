# LewisMD Remote Share API Plan

## Purpose

This document defines the implementation plan for an **optional remote publishing
system** for LewisMD.

The goal is to keep LewisMD as a **local-first, private application** while
allowing users to publish selected shared notes to a small public-facing API
hosted on a VPS.

This plan intentionally avoids turning the VPS into a second full LewisMD
instance. The remote side should behave as a **narrow share relay**:

- accept authenticated publish/update/revoke requests from the local app
- store and serve public read-only note snapshots
- expose only a minimal, hardened surface to the internet

## Core Product Decisions

### 1. Remote publishing is optional

Default behavior remains local-only:

- `share_backend = local`

Users must explicitly opt into remote publishing in `.fed`.

### 2. The browser frontend does not talk directly to the VPS

The local LewisMD backend remains the only component that:

- reads `.fed`
- knows the VPS token and signing secret
- publishes outward

This prevents credential leakage in Stimulus or browser dev tools.

### 3. The VPS receives sanitized share payloads, not arbitrary full HTML

The local app sends:

- note identity
- title
- sanitized HTML fragment
- metadata
- asset manifest

The remote service sanitizes again before storage and wraps the fragment in its
own fixed public shell.

### 4. The VPS is a dedicated share API, not a full notes app

The public service must not expose:

- file trees
- note editing
- templates
- local backups
- AI features
- config mutation

Only share publishing and read-only serving are in scope.

### 5. Docker Compose is the preferred VPS runtime

This keeps Ubuntu, Fedora, and AlmaLinux support manageable while minimizing
cross-distro differences.

## High-Level Architecture

### Local LewisMD app

Responsibilities:

- decide whether share backend is `local` or `remote`
- build the sanitized payload
- upload referenced assets if enabled
- authenticate with the remote API
- preserve the last known public URL and sync state

### Remote share API

Responsibilities:

- authenticate write requests
- re-sanitize incoming fragments
- persist metadata, snapshots, and assets
- serve public share pages and assets
- expose health and capability endpoints

### Reverse proxy

Recommended:

- Caddy in front of the API

Responsibilities:

- TLS termination
- public routing
- security headers where appropriate
- access logging

## Architectural Reconciliation

This plan has been cross-checked against the existing LewisMD architecture in:

- [AGENTS.md](C:/Users/Admin/Documents/GitHub/LewisMD/AGENTS.md)
- [CLAUDE.md](C:/Users/Admin/Documents/GitHub/LewisMD/CLAUDE.md)
- [antigravity.md](C:/Users/Admin/Documents/GitHub/LewisMD/antigravity.md)

The main conclusion is that the remote publishing feature should be implemented
as an extension of the current local share/export flow, not as a second parallel
system.

### Existing code paths we should explicitly reuse

#### 1. Config and runtime settings

Configuration must continue to flow through:

- [app/models/config.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/models/config.rb)

This matches the contributor guidance:

- use `Config.new.get("key")`
- keep `.fed` as the main runtime override surface
- do not read raw `ENV` directly for app configuration

#### 2. Frontend share UX

The current browser-side share UX already exists in:

- [app/javascript/controllers/app_controller.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/controllers/app_controller.js)
- [app/javascript/controllers/export_menu_controller.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/controllers/export_menu_controller.js)

The remote-share rollout should preserve the existing frontend contract:

- `POST /shares`
- `PATCH /shares/:path`
- `DELETE /shares/:path`
- `GET /shares/:path`

The browser should continue to talk only to the local Rails app. The local
backend decides whether a share is `local` or `remote`.

#### 3. Existing preview/export rendering pipeline

Remote publishing should reuse the rendering already produced by the current
preview/export stack:

- [app/javascript/controllers/preview_controller.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/controllers/preview_controller.js)
- [app/javascript/lib/rendered_document_payload.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/lib/rendered_document_payload.js)
- [app/javascript/lib/export_document_builder.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/lib/export_document_builder.js)
- [app/javascript/controllers/app_controller.js](C:/Users/Admin/Documents/GitHub/LewisMD/app/javascript/controllers/app_controller.js)

That means:

- do not invent a second markdown renderer for remote sharing
- do not move rendering responsibility into the VPS
- do not ask the frontend to generate a separate remote-only payload shape

Instead, Phase 2 and beyond should continue transforming the current share
document into a server-owned sanitized payload.

#### 4. Existing local share storage and controller flow

The current local share implementation already establishes the correct layering:

- [app/controllers/shares_controller.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/controllers/shares_controller.rb)
- [app/services/share_service.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/services/share_service.rb)
- [app/services/share_provider_selector.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/services/share_provider_selector.rb)

Remote publishing should build on this shape:

- thin controller
- provider-selected backend
- service objects for business logic
- filesystem storage for local mode

#### 5. Existing public share reader

LewisMD already has a polished read-only shared view in:

- [app/views/layouts/share.html.erb](C:/Users/Admin/Documents/GitHub/LewisMD/app/views/layouts/share.html.erb)
- [app/views/shares/show.html.erb](C:/Users/Admin/Documents/GitHub/LewisMD/app/views/shares/show.html.erb)

The VPS service should not depend on Rails to render these templates directly,
but the remote public shell should borrow the same product decisions:

- read-only presentation
- minimal controls
- no editing state
- no note-tree exposure

#### 6. Existing deployment and installer conventions

LewisMD already has install/deploy conventions in:

- [install.sh](C:/Users/Admin/Documents/GitHub/LewisMD/install.sh)
- [config/fed/fed.sh](C:/Users/Admin/Documents/GitHub/LewisMD/config/fed/fed.sh)
- [docker-compose.yml](C:/Users/Admin/Documents/GitHub/LewisMD/docker-compose.yml)

The remote-share installer should follow the same principles:

- one clear entrypoint script
- health-check driven validation using `/up`
- Docker Compose as the runtime boundary
- print final next-step instructions instead of assuming operator knowledge
- keep the remote setup optional and isolated from the default local install path

### Plan adjustments from this reconciliation

The implementation phases remain valid, but the following constraints should now
be treated as explicit requirements:

- keep the current `/shares` browser contract unchanged
- keep remote publishing entirely behind the local Rails backend
- reuse the existing rendered-preview/export document pipeline as the source
  material for remote payload construction
- keep the remote API as a narrow relay, not a second LewisMD UI
- shape the VPS installer like the existing `install.sh` experience: one
  entrypoint, guided setup, clear final instructions

## Required `.fed` Settings

These keys should be added to [app/models/config.rb](C:/Users/Admin/Documents/GitHub/LewisMD/app/models/config.rb).

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
- `share_remote_healthchecks_ping_url = `
- `share_remote_alert_webhook_url = `

### Sensitive

- `share_remote_api_token = `
- `share_remote_signing_secret = `
- `share_remote_alert_webhook_secret = `

### Notes

- Keep `share_backend = local` as the default.
- Mark secret keys as sensitive in `Config::SENSITIVE_KEYS`.
- Render commented template lines for all new remote-share keys in generated
  `.fed` files.

## Remote API Contract

### Capability endpoint

Public or authenticated read-only:

- `GET /api/v1/capabilities`

Returns:

- API version
- minimum supported client version
- feature flags
- max payload size
- max asset size/count

This prevents local/VPS version drift from failing silently.

### Health endpoint

- `GET /up`

Used by:

- installer smoke tests
- uptime monitoring
- systemd timer heartbeat jobs

### Authenticated write endpoints

- `POST /api/v1/shares`
- `PUT /api/v1/shares/:token`
- `DELETE /api/v1/shares/:token`

### Public read endpoints

- `GET /s/:token`
- `GET /assets/:token/:asset_name`

## Payload Design

### Local app sends

- note path
- logical note identifier
- share title
- sanitized HTML fragment
- content hash
- optional theme/locale hints
- asset manifest
- optional source metadata for auditing

### Local app does not send

- full editable note state
- app config
- templates
- folder metadata
- secrets
- arbitrary scripts

### Asset manifest fields

Per asset:

- normalized original path
- filename
- mime type
- byte size
- sha256
- upload token/reference

## Sanitization Strategy

### Local sanitization

Before publish, LewisMD should sanitize the generated share fragment using a
strict allowlist.

Allow only:

- headings
- paragraphs
- lists
- blockquotes
- code and pre
- tables
- emphasis tags
- links
- images

Disallow:

- `script`
- `iframe`
- `form`
- `object`
- `embed`
- dangerous URL schemes
- event-handler attributes
- inline JavaScript

### Remote sanitization

The VPS sanitizes the fragment again before writing it to storage.

This protects against:

- local bugs
- malformed payloads
- future regressions in the local renderer

### Public shell rendering

The remote API should never trust uploaded outer HTML. It should generate its
own page shell and inject only the sanitized fragment into a controlled content
container.

## Remote Storage Layout

Suggested filesystem layout on the VPS:

- `/var/lib/lewismd-share/shares/<token>.json`
- `/var/lib/lewismd-share/path-index/<path-hash>.json`
- `/var/lib/lewismd-share/snapshots/<token>/index.html`
- `/var/lib/lewismd-share/assets/<token>/<sha>-<filename>`
- `/var/lib/lewismd-share/nonces/<request-id>.json`

### Storage rules

- use atomic writes
- fsync before rename when practical
- stage assets before promotion
- delete orphaned assets on update/revoke
- never partially replace a live share in-place

## Authentication And Replay Protection

Every write request should include:

- `Authorization: Bearer <token>`
- `X-LewisMD-Timestamp`
- `X-LewisMD-Request-Id`
- `X-LewisMD-Signature`

### Validation rules

- bearer token must match configured API token
- HMAC signature must match request body + headers
- timestamp must be within a short replay window
- request ID must not have been seen before

### Preventive measures

- store request IDs temporarily on disk
- expire old request IDs
- reject replays with the same request ID
- log all auth failures with source IP and reason

## Security Requirements

### Mandatory

- HTTPS only in production
- long random API token
- HMAC signing secret
- strict CSP for public pages
- uniform 404 behavior for invalid or revoked shares
- request size limits
- rate limiting
- asset type allowlist
- secret values never exposed to the browser

### Strongly recommended

- use a real domain instead of raw IP
- keep Caddy as the only public entrypoint
- place the share API on an internal Docker network
- rotate publish secrets
- keep public share tokens separate from admin auth

### Explicit pitfalls to avoid

- exposing the full LewisMD app publicly
- trusting arbitrary incoming HTML
- storing SVG in v1
- relying on frontend-side remote secrets
- exposing Docker engine ports
- assuming Docker always cooperates with host firewalls by default

## Firewall And Network Model

### Public ports

Expose only:

- `80/tcp`
- `443/tcp`

### Internal ports

The share API container should stay internal to Docker networking.

### Firewall tools by distro

- Ubuntu: `ufw` if present, otherwise explicit `iptables`/`nftables` guidance
- Fedora: `firewall-cmd`
- AlmaLinux: `firewall-cmd`

### Preventive measure

The installer must verify actual listening sockets after deployment instead of
assuming the firewall rules behaved as expected.

## Monitoring And Webhooks

### Monitoring model

Use both:

- `/up` health checks
- host-level timer/service checks outside the containers

### Supported outbound notifications

- generic JSON webhook
- Slack incoming webhook
- Discord webhook
- Healthchecks.io heartbeat

For v1, the generated host-side monitor should support one alert webhook target
at a time plus an optional Healthchecks heartbeat URL.

### Suggested events

- `service_up`
- `service_down`
- `service_recovered`
- `deploy_started`
- `deploy_succeeded`
- `deploy_failed`
- `share_publish_failed`
- `disk_usage_high`
- `certificate_problem`

### Anti-spam rule

Only send alerts on state transitions unless explicitly configured otherwise.

## Installer Design

The VPS installer is a major part of v1 and must be considered part of the
core plan, not an afterthought.

### Main entrypoint

Recommended file:

- `deploy/share_api/install_share_api.sh`

### Goals

- install all required dependencies
- configure Docker and Compose
- configure reverse proxy
- create runtime directories
- configure firewall rules
- run smoke tests
- guide the user through any required choices

### Distros to support

- Ubuntu
- Fedora
- AlmaLinux

### Dependency handling

The installer should detect and install if missing:

- Docker Engine
- Docker Compose plugin
- curl
- openssl
- systemd service utilities
- firewall tools if needed

Ruby should **not** be required on the VPS host when using the containerized
share API. If a helper script needs Ruby, it should run inside the container or
as part of the build image, not as a host dependency.

### Interactive installer prompts

The installer should ask for only the values that are truly user-dependent.

Prompts should include:

- domain name or public host
- whether to proceed with raw IP mode if no domain is available
- public contact email for TLS/cert provisioning
- public HTTP port for raw IP mode
- whether to enable Healthchecks.io integration
- whether to enable Slack/Discord/generic webhook alerts
- webhook URLs and optional secrets
- instance name label
- monitoring interval in minutes
- disk-usage threshold for warning alerts
- storage path override or default confirmation
- whether to open firewall rules automatically
- whether to create a backup timer

Optional prompt behavior:

- auto-generate strong API token and signing secret unless the user provides them
- confirm generated values before writing the `.env`
- print the exact `.fed` values the local LewisMD app should receive afterward

### Implementation note

To keep automatic HTTPS predictable in the first installer version, domain mode
should stay on standard ports `80` and `443`. Nonstandard public ports can be
offered only in raw-IP HTTP mode until a more advanced TLS story is added.

### Installer outputs

The installer should generate:

- `.env`
- `compose.yml`
- `Caddyfile`
- monitoring scripts
- systemd service/timer units if needed

### Post-install smoke tests

The installer must verify:

- Docker is running
- containers are healthy
- reverse proxy responds
- `/up` returns success
- public ports are listening
- firewall configuration matches the chosen port layout

### Backup and lifecycle helpers

Also create:

- `deploy/share_api/upgrade_share_api.sh`
- `deploy/share_api/backup_share_api.sh`
- `deploy/share_api/uninstall_share_api.sh`
- `deploy/share_api/check_share_api.sh`

## Local UX Rules

The local share menu should remain familiar:

- create shared link
- copy shared link
- refresh shared snapshot
- disable shared link

### Remote-mode feedback

Add clear user feedback for:

- incompatible remote API version
- authentication failure
- TLS verification failure
- service unavailable
- asset upload failure
- remote share out of sync

### Failure safety

- never auto-revoke on network failure
- preserve the last known share URL on failed refresh
- mark remote share state as stale when sync fails

## Testing Requirements

### Local app tests

- config parsing
- provider selection
- payload generation
- sanitization
- stale-state handling
- user error messages

### Remote API tests

- auth success/failure
- replay rejection
- sanitization enforcement
- public share serving
- revoke behavior
- asset upload validation
- header/CSP presence

### End-to-end tests

- publish
- refresh
- revoke
- publish with assets
- publish while VPS unavailable
- reinstall/upgrade smoke tests

### Installer tests

Validate the install flow on:

- Ubuntu
- Fedora
- AlmaLinux

## Recommended Implementation Phases

### Phase 1: Config and provider scaffolding

- add `.fed` keys
- add config sensitivity rules
- introduce local vs remote provider abstraction
- keep `local` as default

### Phase 2: Sanitized payload builder

- build sanitized share fragment locally
- define asset manifest contract
- add tests around allowed/disallowed markup

### Phase 3: Remote share registry and client

- remote provider implementation
- local persistence of remote share metadata
- version/capability preflight checks

### Phase 4: Share API service

- minimal authenticated write API
- public read endpoints
- filesystem-backed storage
- atomic writes

### Phase 5: Public rendering hardening

- fixed remote shell
- CSP and related headers
- token handling and uniform not-found behavior

### Phase 6: Asset uploads

- local asset detection
- upload flow
- manifest validation
- atomic promotion

### Phase 7: Dockerized VPS deployment

- compose stack
- Caddy integration
- internal networking
- environment generation

### Phase 8: Interactive installer

- distro detection
- dependency installation
- prompt flow
- firewall automation
- smoke tests

### Phase 9: Monitoring and alerting

- `/up` checks
- systemd timers
- webhooks
- state transition alerts

### Phase 10: Upgrade, backup, and recovery tooling

- upgrade script
- backup script
- uninstall script
- troubleshooting docs

Implementation guardrails for this phase:

- the upgrade script should create a pre-upgrade backup by default unless the
  operator explicitly skips it
- the backup archive should include runtime config, persisted share storage, and
  Caddy state so a replacement VPS can be restored without hand-rebuilding the
  environment
- uninstall should preserve data by default and only delete persisted state when
  the operator explicitly opts in
- operator docs should explain both the safe defaults and the manual recovery
  path from a backup archive

### Phase 11: Discoverability and deployment contract checks

- README discoverability for the optional VPS relay
- deployment artifact regression tests
- operator workflow coverage for install/upgrade/backup/uninstall

Implementation guardrails for this phase:

- the VPS operator path should be linked from the main README so users can find
  it without hunting through deployment folders
- automated tests should verify the tracked deployment artifacts still describe
  the expected contract even when a Linux VPS is not available locally
- these tests should focus on high-signal invariants such as:
  - compose topology
  - required monitoring env keys
  - upgrade/backup/uninstall script intent
  - operator guide coverage

## Plan Updates From The Earlier Draft

This plan updates the earlier draft in these important ways:

1. The VPS installer is now treated as a first-class phase, not a later polish step.
2. The installer must be interactive for user-dependent settings instead of
   expecting manual file editing.
3. The remote service is explicitly container-first, which removes host Ruby as
   a VPS prerequisite.
4. The remote shell must render around a sanitized fragment instead of serving
   uploaded outer HTML directly.
5. Asset upload and rewrite support stays in the v1 plan, not postponed
   indefinitely, because broken local images would make the feature feel
   incomplete.
6. Firewall verification is included as an explicit post-install step, not just
   “apply rules and hope”.
7. Monitoring, outbound webhooks, and transition-only alerts are part of the
   plan from the start.

## Recommended First Implementation Boundary

Before writing the VPS service itself, the safest place to begin is:

- config schema
- remote/local provider abstraction
- sanitized payload builder

That gives the local app a stable contract before the remote API and installer
are added.

Once those are done, the remote API can be implemented against a real payload
shape instead of a speculative one.
