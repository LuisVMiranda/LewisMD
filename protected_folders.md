# Protected Folders Plan

## Goal

Add an optional in-app privacy layer for specific folders without adding a database, Redis, or a heavy authentication subsystem.

This feature would:
- protect selected folders and everything inside them with a password
- require the password again after 30 minutes of inactivity or expiry
- stay filesystem-backed and cookie-based
- add near-zero ongoing RAM overhead on a VPS

## Important Scope Clarification

This is **access control**, not encryption at rest.

It would protect notes from casual access through the LewisMD UI and routes, but it would **not** encrypt the underlying markdown files on disk. Anyone with direct filesystem or root/container access could still read them.

That makes it a useful second layer behind nginx auth, but not a replacement for disk encryption.

## Recommended Architecture

### Storage

Use a hidden metadata store under the notes root:

- `.frankmd/locks/`
- one metadata file per protected folder, for example:
  - `.frankmd/locks/private.json`
  - `.frankmd/locks/work/journal.json`

Each metadata file would contain:
- protected folder path
- password hash
- password hash algorithm/version
- created timestamp
- updated timestamp
- optional label/description

Do **not** store plaintext passwords.

### Password Hashing

Use `bcrypt` for the initial implementation.

Why:
- well understood
- simple Ruby integration
- CPU-expensive at unlock time, but tiny persistent memory footprint
- no extra long-running service

### Unlock State

Use encrypted/signed Rails cookies, not a server-side session store.

Each unlock cookie entry would include:
- locked folder path or canonical folder identifier
- unlocked_at
- expires_at

Suggested behavior:
- unlock lasts 30 minutes
- expiry is checked on every protected request
- no Redis
- no database session table

### Canonical Lock Model

Locks should be folder-prefix based.

If `projects/private` is protected:
- `projects/private/note.md` is protected
- `projects/private/subfolder/child.md` is protected
- sibling folders are not

Nested protected folders should be avoided in v1 unless a clear precedence rule is defined.

## Enforcement Surface

This is the critical part. A folder lock is only trustworthy if all note-revealing and note-mutating paths respect it.

### Must be enforced on:

- note show/load
- note create/update/destroy/rename
- folder create/destroy/rename
- tree rendering
- file finder
- note search
- AI prompt/grammar/image endpoints when they operate on locked content
- export endpoints
- share creation and share refresh
- image access if images are stored inside locked folders in the future

### Decisions needed for locked content visibility:

Option A:
- locked folders appear in the tree by name but cannot be opened

Option B:
- locked folders appear as generic placeholders, hiding note names

Recommendation:
- use Option A first
- show the folder name, but hide its note list and block content access until unlocked

This keeps the implementation smaller while still giving useful privacy.

## Filesystem Services

### New service: `ProtectedFoldersService`

Responsibilities:
- list protected folders
- read/write/delete lock metadata
- hash and verify passwords
- answer whether a given note/folder path is protected
- resolve which lock applies to a given path

### New service: `FolderUnlockService`

Responsibilities:
- issue unlock-cookie payloads
- validate expiry
- forget expired unlocks
- answer whether a path is currently unlocked in this browser

Keep these separate so password storage logic and request-time unlock logic do not tangle together.

## Rails Integration

### Recommended controller concern

Add a shared concern such as `ProtectablePathAccess`.

Responsibilities:
- normalize requested path
- consult `ProtectedFoldersService`
- consult unlock cookie state
- short-circuit with:
  - `403 Forbidden` for JSON/API requests
  - lock prompt state for HTML routes if needed

This keeps enforcement reusable across notes, folders, search, AI, and export controllers.

### New controller

Add `ProtectedFoldersController` or `FolderLocksController`.

Suggested endpoints:
- `POST /protected_folders`
- `PATCH /protected_folders/*path/unlock`
- `DELETE /protected_folders/*path/unlock`
- `PATCH /protected_folders/*path/password`
- `DELETE /protected_folders/*path`

These endpoints would:
- create/remove locks
- unlock/lock for the current browser
- rotate passwords

## Frontend/UI Plan

### Initial UI scope

Keep it minimal.

Add context-menu items on folders:
- `Protect folder`
- `Unlock folder`
- `Lock folder`
- `Change folder password`
- `Remove folder protection`

Add a compact unlock dialog:
- folder path label
- password input
- submit

### Timeout behavior

When the 30-minute window expires:
- future requests fail server-side
- the frontend should detect the lock response
- clear the current note UI if needed
- show the unlock dialog again

### Multiple tabs

Recommended v1 behavior:
- cookie-based unlock automatically applies to all tabs in the same browser
- expiry naturally applies to all tabs together

This is a feature, not a bug, and keeps the implementation simple.

## Search, File Tree, and Finder Rules

### Tree

Locked folder contents should not render until unlocked.

### Search

Locked content should be excluded from search results unless unlocked.

### File Finder

Locked notes should not appear unless unlocked.

These are essential to avoid metadata leaks.

## Autosave / Backup / Export / Share Considerations

### Autosave

If a protected note is open and the lock expires:
- autosave should stop
- the editor should lock visually
- local in-memory content should not be silently posted

### Offline backup

Need a decision:
- either allow local backup entries to exist for protected notes
- or disable them for protected paths

Recommendation:
- allow them in v1, but clearly treat this as convenience, not strong secrecy

### Export

Protected notes should only export when unlocked.

### Share

Protected notes should not be shareable unless explicitly unlocked at creation/refresh time.

Further recommendation:
- consider blocking snapshot sharing entirely for protected folders in v1
- that keeps the security story simpler

## Templates / Images / Other Hidden App Data

Protected folder logic should not accidentally lock hidden app-managed stores such as:
- `.frankmd/templates`
- `.frankmd/images`
- `.frankmd/shares`

Those folders are app infrastructure, not user content folders.

## Phased Implementation Plan

### Phase 1: Metadata + hashing + cookie primitives

- add `bcrypt`
- add `ProtectedFoldersService`
- add `FolderUnlockService`
- add metadata file format
- add tests for hashing, creation, verification, expiry payloads

### Phase 2: Backend enforcement on notes and tree

- add shared protection concern
- enforce on notes CRUD and tree rendering
- add unlock endpoint
- add tests for forbidden access and unlocked access

### Phase 3: Search, finder, AI, export, and share enforcement

- enforce protections consistently across secondary features
- add regression tests for leaks

### Phase 4: UI

- add folder context-menu entries
- add unlock dialog
- add timeout handling in the frontend

### Phase 5: Polish and docs

- update README
- document limitations clearly
- add antigravity notes and threat-model conclusions

## Expected Resource Consumption

### RAM

If implemented with:
- filesystem metadata
- bcrypt
- signed/encrypted cookies
- no Redis

The persistent RAM overhead should be very small.

Realistically:
- close to zero in day-to-day usage
- roughly in the low single-digit MB range at most as loaded code/object overhead
- not meaningfully different from the current Rails process footprint

### CPU

Unlock operations would cost more CPU than RAM because password hash verification is intentionally slow.

That is acceptable because unlocks are infrequent.

## Main Risks

- incomplete enforcement causing metadata leaks
- inconsistent behavior across note routes and auxiliary features
- user misunderstanding this as encryption instead of UI/API access control
- autosave or backup behavior exposing content after timeout if not handled carefully

## Recommendation

This feature is viable for LewisMD, but it should be treated as a major security-facing feature, not a quick enhancement.

The architecture above keeps it aligned with the project:
- no database
- no server-side session store
- low RAM overhead
- filesystem-first
- straightforward operational model

If implemented, the first priority should be **correct server-side enforcement**, not UI polish.
