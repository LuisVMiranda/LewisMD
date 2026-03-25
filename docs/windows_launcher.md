# Windows Personal Launcher

This guide documents the optional Windows launcher for LewisMD.

It is designed for personal/local use when you want LewisMD to feel more like a
lightweight desktop app on Windows by:

- starting a local Rails server with a portable Ruby runtime
- waiting for `/up` to become healthy
- opening the app in Edge or Chrome `--app` mode
- stopping the launcher-managed Rails process when the app window closes

This is **not** the project's primary installation path. The main LewisMD setup
remains the Docker-first flow documented in [README.md](/C:/Users/Admin/Documents/GitHub/LewisMD/README.md).

## What Lives Where

The launcher files live in:

- [script/windows/bootstrap_lewismd.bat](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/bootstrap_lewismd.bat)
- [script/windows/start_lewismd.bat](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/start_lewismd.bat)
- [script/windows/launch_lewismd.ps1](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/launch_lewismd.ps1)
- [script/windows/Launch_LewisMD.vbs](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/Launch_LewisMD.vbs)
- [script/windows/stop_lewismd.bat](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/stop_lewismd.bat)
- [script/windows/launcher.defaults.psd1](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/launcher.defaults.psd1)

Local runtime artifacts stay outside Git:

- `portable_ruby/`
- `vendor/bundle/windows/`
- `tmp/windows-launcher/`

## Runtime Model

The Windows launcher currently assumes:

- Ruby line from [.ruby-version](/C:/Users/Admin/Documents/GitHub/LewisMD/.ruby-version): `ruby-3.4.8`
- Rails environment: `development`
- default port: `7777`
- default notes path: `notes/`
- local bundled gems: `vendor/bundle/windows/`
- launcher state and logs: `tmp/windows-launcher/`

Those defaults are centralized in
[script/windows/launcher.defaults.psd1](/C:/Users/Admin/Documents/GitHub/LewisMD/script/windows/launcher.defaults.psd1).

## Setup

### 1. Run the one-time bootstrap

From the repository root:

```bat
script\windows\bootstrap_lewismd.bat
```

What bootstrap does:

- downloads and installs the official RubyInstaller runtime into `portable_ruby/` when Ruby is missing
- verifies the repo-local Ruby location
- checks that the launcher defaults still match `.ruby-version`
- installs Bundler into the portable runtime if needed
- configures a repo-local bundle path at `vendor/bundle/windows`
- installs the local gems needed by the launcher

The launcher currently uses the official RubyInstaller 3.4.8-1 x64 release
under the hood so the repo-local runtime matches the project's checked-in Ruby
line while staying isolated from the rest of the machine.

Useful variants:

```bat
script\windows\bootstrap_lewismd.bat --check-only
script\windows\bootstrap_lewismd.bat --all-groups
```

`--check-only` stays non-destructive. It validates the quick-start assumptions,
but it does not download or install Ruby.

### 2. Launch LewisMD visibly first

For the first real launch, use the visible wrapper:

```bat
script\windows\start_lewismd.bat
```

This is the best entrypoint while validating a new setup because it keeps
errors visible in the terminal.

It also self-heals the common first-run problem: if the quick `--check-only`
validation fails, the visible launcher now runs the full bootstrap
automatically before attempting the real app launch.

If startup fails when you double-click it, the window now stays open so you can
read the failure instead of disappearing immediately.

### 3. Use the hidden launcher for normal double-click use

Once the visible path works, you can use:

```text
script\windows\Launch_LewisMD.vbs
```

That wrapper hides the terminal window and launches the same underlying flow.
It also disables the visible launcher's "pause on error" behavior so hidden
failures return to the VBS message box instead of hanging in the background.
Hidden mode also opts out of the automatic bootstrap fallback so it never tries
to perform first-run setup invisibly in the background.

If you want a desktop shortcut with the LewisMD icon, create or refresh it with:

```bat
cscript //NoLogo script\windows\Launch_LewisMD.vbs --install-shortcut
```

That creates `LewisMD.lnk` on your desktop, pointing to the current VBS file
through `wscript.exe` and using
[`public/icon.ico`](/C:/Users/Admin/Documents/GitHub/LewisMD/public/icon.ico) as
the shortcut icon. Windows does not support assigning a different icon to one
individual `.vbs` file directly, so the shortcut is the correct workaround.

## Recovery

If a previous launcher session leaves stale state behind, run:

```bat
script\windows\stop_lewismd.bat
```

This stops only the launcher-managed Rails process and cleans stale launcher
state when possible. It never kills every `ruby.exe` on the machine.

## Logs and Diagnostics

The launcher writes diagnostics under:

```text
tmp/windows-launcher/
```

Important files:

- `launcher.log`
  - launcher lifecycle messages from bootstrap, the visible batch wrapper, and
    the PowerShell orchestrator
- `rails.log`
  - stdout/stderr captured from the Rails server process
- `launcher-state.json`
  - launcher-managed state used for PID tracking and stale-state cleanup
- `server.pid`
  - the PID file written by `rails server`

If logs grow too large, the launcher rotates one backup copy:

- `launcher.previous.log`
- `rails.previous.log`

## Environment Overrides

You can override the default launcher behavior with:

- `LEWISMD_PORT`
- `LEWISMD_BROWSER`
- `LEWISMD_NOTES_PATH`

Examples:

```powershell
$env:LEWISMD_PORT = "7788"
$env:LEWISMD_BROWSER = "msedge"
$env:LEWISMD_NOTES_PATH = "D:\Notes"
script\windows\start_lewismd.bat
```

## Validation Commands

Useful non-destructive checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File script\windows\launch_lewismd.ps1 -ValidateOnly
```

```bat
script\windows\bootstrap_lewismd.bat --check-only
script\windows\stop_lewismd.bat --help
```

```bat
cscript //NoLogo script\windows\Launch_LewisMD.vbs --dry-run
cscript //NoLogo script\windows\Launch_LewisMD.vbs --install-shortcut
```

## Validation Matrix

Validated in the current repo state:

- missing `portable_ruby/` fails clearly in bootstrap, visible launch, and
  PowerShell validation mode
- the visible launcher can now install the repo-local Ruby runtime automatically
- healthy local launch reaches `/up` successfully with the repo-local runtime
- hidden launcher dry-run resolves the expected command and log paths
- stop helper succeeds cleanly when nothing is running
- stop helper removes stale launcher-managed state when the tracked process is
  already dead
- invalid ports fail before launch with a clear error

Still pending on a real local Windows runtime:

- browser matrix checks for Edge-only, Chrome-only, both installed, and explicit
  `LEWISMD_BROWSER` overrides
- readiness timeout behavior against a real failing Rails boot
- port-conflict behavior while a different process is already listening
- a full launch/close cycle proving the browser window closes first and the
  launcher-managed Rails process stops afterward

## Important Limitations

- This launcher is Windows-only.
- It is meant for personal/local use, not for production hosting.
- It still depends on a working Ruby/Bundler runtime inside the repo.
- The main LewisMD distribution path is still Docker-first.
- Browser `--app` behavior depends on Edge/Chrome being available locally.

## Recommended Usage Pattern

1. Run `script\windows\bootstrap_lewismd.bat` once, or let the visible launcher do it for you on the first run
2. Test with `script\windows\start_lewismd.bat`
3. Switch to `script\windows\Launch_LewisMD.vbs` for day-to-day use
4. Use `script\windows\stop_lewismd.bat` if cleanup is needed
