# Windows Launcher

This folder holds the optional personal Windows launcher for LewisMD.

The goal is to make LewisMD feel like a lightweight desktop app on Windows
without introducing a heavy Electron shell or replacing the project's main
Docker-first workflow.

## Current status

Phase 10 now includes the validation and closeout pass for the launcher workspace:

- [bootstrap_lewismd.bat](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/bootstrap_lewismd.bat)
- [start_lewismd.bat](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/start_lewismd.bat)
- [launch_lewismd.ps1](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/launch_lewismd.ps1)
- [Launch_LewisMD.vbs](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/Launch_LewisMD.vbs)
- [stop_lewismd.bat](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/stop_lewismd.bat)

Bootstrap prepares the runtime, the visible launcher verifies that runtime, and
the PowerShell orchestrator now owns the real server/browser lifecycle. The stop
helper gives users a simple manual cleanup path if a previous launch leaves
stale state behind.

## Runtime contract

- Ruby runtime: repo-local Ruby installed into `portable_ruby/`
- Expected Ruby line: `ruby-3.4.8`
- Rails environment: `development`
- Default local port: `7777`
- Default notes path: `notes/`
- Local Bundler path: `vendor/bundle/windows`
- Launcher state path: `tmp/windows-launcher/`
- Health check endpoint: `/up`

These defaults are stored in
[launcher.defaults.psd1](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/launcher.defaults.psd1)
so future scripts can import one small source of truth.

## Planned files

- `bootstrap_lewismd.bat`
  - one-time setup for Bundler and local gems
- `start_lewismd.bat`
  - visible launcher for normal use and debugging
- `launch_lewismd.ps1`
  - main orchestrator for PID tracking, readiness polling, and cleanup
- `Launch_LewisMD.vbs`
  - hidden wrapper for a polished double-click launch
- `stop_lewismd.bat`
  - manual cleanup helper if a prior launch leaves stale state behind

## Supported overrides

The launcher plan currently allows these environment variables:

- `LEWISMD_PORT`
- `LEWISMD_BROWSER`
- `LEWISMD_NOTES_PATH`

These keep the Windows path flexible for personal use without requiring users
to edit the scripts directly.

## Bootstrap behavior

Run this once when the repo-local Windows runtime is missing or needs repair:

```bat
script\windows\bootstrap_lewismd.bat
```

What it does:

- downloads and installs the official RubyInstaller runtime into `portable_ruby\` when Ruby is missing
- verifies that `portable_ruby\bin\ruby.exe` exists
- checks that the launcher defaults still match `.ruby-version`
- installs Bundler into the portable Ruby if it is missing
- configures a repo-local bundle path at `vendor/bundle/windows`
- installs the local gems needed for the launcher runtime

By default it excludes the test group to keep the personal launcher footprint
smaller. If you want the local Windows runtime to include every Bundler group,
run:

```bat
script\windows\bootstrap_lewismd.bat --all-groups
```

If you just want to validate the setup without installing gems, run:

```bat
script\windows\bootstrap_lewismd.bat --check-only
```

`--check-only` does not install Ruby automatically. It is the quick validation
path used by the visible launcher before deciding whether a full bootstrap is
needed.

## Visible launcher behavior

Once bootstrap is ready, the future visible launcher entrypoint is:

```bat
script\windows\start_lewismd.bat
```

At this phase it does two useful things already:

- keeps launch output visible for troubleshooting
- runs `bootstrap_lewismd.bat --check-only` before attempting any launch
- falls back to the full bootstrap automatically when that quick check fails in visible mode

It now delegates to `launch_lewismd.ps1` for the real launch flow, while still
remaining the readable entrypoint users can rely on when something goes wrong.
If the dedicated Edge/Chrome launcher profile is still finishing shutdown, the
visible wrapper now waits briefly and retries one transient browser-handoff
failure automatically before surfacing an error.

Hidden mode intentionally opts out of this automatic bootstrap fallback. If the
runtime is missing, the hidden launcher fails fast and points the user back to
the visible setup path.

## PowerShell orchestrator behavior

The main launcher logic now lives in:

```powershell
script\windows\launch_lewismd.ps1
```

What it does:

- validates the portable Ruby runtime
- checks Bundler and `bundle check`
- creates launcher state under `tmp/windows-launcher/`
- polls `http://127.0.0.1:<port>/up` instead of sleeping blindly
- tracks the exact Rails PID in a launcher-managed state file
- refuses to launch if the target port is already owned by another process
- opens Edge or Chrome in `--app` mode with a dedicated browser profile
- waits for the dedicated launcher browser profile to stabilize before reusing
  it or declaring startup complete
- waits for the app window to close
- waits for launcher-profile browser processes to disappear cleanly before
  considering the session fully closed
- stops only the launcher-managed Rails process on exit

For a validation-only pass without launching the browser, you can run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File script\windows\launch_lewismd.ps1 -ValidateOnly
```

## Hidden launcher behavior

The polished double-click entrypoint is:

```text
script\windows\Launch_LewisMD.vbs
```

What it does:

- runs `start_lewismd.bat` with the console hidden
- skips the visible launcher's extra bootstrap validation because the
  PowerShell orchestrator still validates the runtime itself
- passes `--no-pause-on-error` so hidden failures do not leave an invisible paused window behind
- waits for the launcher/app session to end
- shows a simple message box if startup fails
- points the user back to the visible launcher and the launcher log path
- can create a desktop shortcut with the LewisMD icon via `--install-shortcut`

For non-interactive validation, you can inspect the resolved command without
launching anything:

```bat
cscript //NoLogo script\windows\Launch_LewisMD.vbs --dry-run
```

To create or refresh a desktop shortcut that launches LewisMD with the project
icon, run:

```bat
cscript //NoLogo script\windows\Launch_LewisMD.vbs --install-shortcut
```

That shortcut points to the current VBS file through `wscript.exe` and uses
[`public/icon.ico`](/C:/Users/Admin/Documents/GitHub/LewisMD/public/icon.ico) as its
icon. Windows does not support setting a custom icon on one individual `.vbs`
file directly, so the shortcut is the correct shell-level workaround.

## Stop helper behavior

The manual recovery entrypoint is:

```bat
script\windows\stop_lewismd.bat
```

What it does:

- asks `launch_lewismd.ps1` to enter stop-only mode
- stops only the launcher-managed Rails process
- removes stale launcher state if the Rails process is already gone
- works without re-running bootstrap or launching a browser window

For a quick usage reminder, you can run:

```bat
script\windows\stop_lewismd.bat --help
```

## Design constraints

- The launcher is optional and Windows-only.
- It should never kill all `ruby.exe` processes globally.
- It should prefer `/up` readiness polling over fixed startup sleeps.
- It should keep a visible debug path even if hidden launch mode is added.
- It should remain versioned with LewisMD, not split into a separate repo.

## Log files and diagnostics

The launcher keeps its runtime state under:

```text
tmp/windows-launcher/
```

Important files:

- `launcher.log`
  - launcher lifecycle messages from the visible batch wrapper and the
    PowerShell orchestrator
- `rails.log`
  - stdout/stderr captured from the Rails server process
- `launcher-state.json`
  - launcher-managed state used for PID tracking and recovery decisions
- `launcher-progress.json`
  - lightweight startup progress state for the future splash/feedback window
- `server.pid`
  - the PID file written by `rails server`

Diagnostic behavior:

- each PowerShell launcher session writes a clear session boundary into the logs
- `launcher.log` and `rails.log` keep one rotated `*.previous.log` copy if they
  grow too large
- hidden-launch failures point users to both the visible launcher and the log
  files
- the stop helper can clean stale launcher state even when Rails is already gone

## Git and repo policy

The launcher scripts in this folder are meant to stay versioned with LewisMD.
Only the local runtime artifacts are ignored:

- `portable_ruby/`
- `vendor/bundle/windows/`
- `tmp/windows-launcher/`

This keeps the repository clean without hiding the actual launcher scripts,
README notes, or future Windows-specific helpers.
