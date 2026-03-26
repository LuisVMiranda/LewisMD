[CmdletBinding()]
param(
  [int]$Port,
  [string]$NotesPath,
  [string]$Browser,
  [switch]$ValidateOnly,
  [switch]$StopOnly,
  [switch]$SkipRuntimeValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:WindowsIdentity = "launcher"
$script:LauncherMode = "launch"
$script:LauncherSessionId = $null
$script:RailsLogWriter = $null
$script:RailsOutputHandler = $null
$script:RailsErrorHandler = $null
$script:ResolvedConfig = $null

function Resolve-ScriptPath {
  param([string]$RelativePath)

  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $RelativePath))
}

function Resolve-LauncherPath {
  param(
    [string]$PathValue,
    [string]$RepoRoot
  )

  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    return $null
  }

  $expanded = [Environment]::ExpandEnvironmentVariables($PathValue)
  if ($expanded.StartsWith("~")) {
    $expanded = Join-Path $HOME $expanded.Substring(1).TrimStart("\", "/")
  }

  if ([System.IO.Path]::IsPathRooted($expanded)) {
    return [System.IO.Path]::GetFullPath($expanded)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $expanded))
}

function Ensure-Directory {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-RotatedLogPath {
  param([string]$Path)

  $directory = Split-Path -Parent $Path
  $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
  $extension = [System.IO.Path]::GetExtension($Path)

  return Join-Path $directory ($baseName + ".previous" + $extension)
}

function Initialize-LogFile {
  param(
    [string]$Path,
    [string]$Label,
    [int64]$MaxBytes = 1048576
  )

  $directory = Split-Path -Parent $Path
  Ensure-Directory -Path $directory

  if (Test-Path -LiteralPath $Path) {
    $existing = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -ne $existing -and $existing.Length -ge $MaxBytes) {
      $rotatedPath = Get-RotatedLogPath -Path $Path
      Move-Item -LiteralPath $Path -Destination $rotatedPath -Force
    }
  }

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType File -Path $Path -Force | Out-Null
  }

  $separator = ("=" * 78)
  $header = @(
    ""
    $separator
    "[{0}] [{1}] Session {2} started for {3}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Label, $script:LauncherSessionId, $script:LauncherMode
    $separator
  )

  Add-Content -Path $Path -Value $header -Encoding UTF8
}

function Write-LauncherMessage {
  param(
    [string]$Message,
    [ValidateSet("INFO", "WARN", "ERROR")]
    [string]$Level = "INFO"
  )

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "[$timestamp] [$Level] $Message"
  Add-Content -Path $script:ResolvedConfig.LauncherLogFile -Value $line -Encoding UTF8

  switch ($Level) {
    "WARN" { Write-Host "[launcher] $Message" -ForegroundColor Yellow }
    "ERROR" { Write-Host "[launcher] $Message" -ForegroundColor Red }
    default { Write-Host "[launcher] $Message" }
  }
}

function Test-ProcessAlive {
  param([int]$ProcessId)

  return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Read-LaunchState {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return $null
  }

  try {
    return $raw | ConvertFrom-Json
  } catch {
    if ($raw.Trim() -match "^\d+$") {
      return [pscustomobject]@{
        pid = [int]$raw.Trim()
      }
    }

    Write-LauncherMessage "Ignoring unreadable launcher state file at $Path." "WARN"
    return $null
  }
}

function Write-LaunchState {
  param(
    [int]$ProcessId,
    [int]$PortNumber,
    [string]$NotesPathValue
  )

  $payload = [ordered]@{
    pid = $ProcessId
    port = $PortNumber
    notesPath = $NotesPathValue
    startedAt = (Get-Date).ToString("o")
  }

  $payload | ConvertTo-Json | Set-Content -Path $script:ResolvedConfig.StateFile -Encoding UTF8
}

function Remove-LaunchState {
  foreach ($path in @($script:ResolvedConfig.StateFile, $script:ResolvedConfig.RailsServerPidFile)) {
    if ([string]::IsNullOrWhiteSpace($path)) {
      continue
    }

    try {
      Remove-Item -LiteralPath $path -Force -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
      continue
    } catch [System.Management.Automation.PSArgumentException] {
      continue
    }
  }
}

function Resolve-ManagedProcessIdForStop {
  $managedState = Read-LaunchState -Path $script:ResolvedConfig.StateFile
  if ($null -ne $managedState -and $null -ne $managedState.pid) {
    return [int]$managedState.pid
  }

  if (Test-Path -LiteralPath $script:ResolvedConfig.RailsServerPidFile) {
    $raw = Get-Content -LiteralPath $script:ResolvedConfig.RailsServerPidFile -Raw -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($raw) -and $raw.Trim() -match "^\d+$") {
      return [int]$raw.Trim()
    }
  }

  return $null
}

function Test-HealthEndpoint {
  param([string]$Uri)

  $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
  if ($null -ne $curl) {
    try {
      $statusCode = & $curl.Source -s -o NUL -w "%{http_code}" $Uri
      return ($LASTEXITCODE -eq 0 -and $statusCode -match "^\d{3}$" -and [int]$statusCode -ge 200 -and [int]$statusCode -lt 400)
    } catch {
      return $false
    }
  }

  try {
    $requestArguments = @{
      Uri = $Uri
      TimeoutSec = 2
      Method = "Get"
      ErrorAction = "Stop"
    }

    if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey("UseBasicParsing")) {
      $requestArguments.UseBasicParsing = $true
    }

    $response = Invoke-WebRequest @requestArguments
    return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
  } catch {
    return $false
  }
}

function Wait-ForHealthEndpoint {
  param(
    [string]$Uri,
    [int]$TimeoutSeconds,
    [System.Diagnostics.Process]$ServerProcess
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

  while ((Get-Date) -lt $deadline) {
    if ($null -ne $ServerProcess -and $ServerProcess.HasExited) {
      throw "Rails exited before the health endpoint became ready. Review $($script:ResolvedConfig.RailsLogFile)."
    }

    if (Test-HealthEndpoint -Uri $Uri) {
      return
    }

    Start-Sleep -Seconds 1
  }

  throw "LewisMD did not become healthy within ${TimeoutSeconds}s. Review $($script:ResolvedConfig.RailsLogFile)."
}

function Get-ListeningProcessId {
  param([int]$PortNumber)

  $tcpCommand = Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue
  if ($null -ne $tcpCommand) {
    $connection = Get-NetTCPConnection -LocalPort $PortNumber -State Listen -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($null -ne $connection) {
      return [int]$connection.OwningProcess
    }
  }

  $pattern = "^\s*TCP\s+\S+:$PortNumber\s+\S+\s+LISTENING\s+(\d+)\s*$"
  $match = netstat -ano -p tcp | Select-String -Pattern $pattern | Select-Object -First 1
  if ($null -ne $match) {
    return [int]$match.Matches[0].Groups[1].Value
  }

  return $null
}

function Stop-ManagedRailsServer {
  param(
    [int]$ProcessId,
    [string]$Reason
  )

  if (-not (Test-ProcessAlive -ProcessId $ProcessId)) {
    Write-LauncherMessage "Launcher-managed Rails process $ProcessId is already stopped. ($Reason)" "WARN"
    Remove-LaunchState
    return
  }

  Write-LauncherMessage "Stopping launcher-managed Rails process $ProcessId. ($Reason)"

  try {
    Stop-Process -Id $ProcessId -ErrorAction Stop
  } catch {
    Write-LauncherMessage "Initial stop request for Rails process $ProcessId failed: $($_.Exception.Message)" "WARN"
  }

  $deadline = (Get-Date).AddSeconds(8)
  while ((Get-Date) -lt $deadline) {
    if (-not (Test-ProcessAlive -ProcessId $ProcessId)) {
      Remove-LaunchState
      return
    }

    Start-Sleep -Milliseconds 400
  }

  Write-LauncherMessage "Rails process $ProcessId did not exit in time. Forcing shutdown." "WARN"
  Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
  Remove-LaunchState
}

function Test-BundlerReady {
  $env:BUNDLE_GEMFILE = (Join-Path $script:ResolvedConfig.RepoRoot "Gemfile")
  $env:BUNDLE_APP_CONFIG = $script:ResolvedConfig.BundleAppConfig
  $env:BUNDLE_PATH = $script:ResolvedConfig.BundlePath
  $env:BUNDLE_WITHOUT = "test"

  Write-LauncherMessage "Checking Bundler inside the portable Ruby runtime..."
  & $script:ResolvedConfig.BundleCmd --version *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "Bundler is not available in the portable Ruby runtime. Run script\windows\bootstrap_lewismd.bat first."
  }

  Write-LauncherMessage "Checking whether the local Windows bundle is ready..."
  & $script:ResolvedConfig.BundleCmd check *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "Bundler dependencies are not installed for the Windows launcher. Run script\windows\bootstrap_lewismd.bat first."
  }
}

function Start-RailsServerProcess {
  if (-not (Test-Path -LiteralPath $script:ResolvedConfig.BinRailsScript)) {
    throw "bin/rails was not found at $($script:ResolvedConfig.BinRailsScript)."
  }

  $arguments = @(
    "-rbundler/setup"
    ('"' + $script:ResolvedConfig.BinRailsScript + '"')
    "server"
    "-b"
    "127.0.0.1"
    "-p"
    "$($script:ResolvedConfig.Port)"
    "-e"
    $script:ResolvedConfig.RailsEnvironment
    "-P"
    ('"' + $script:ResolvedConfig.RailsServerPidFile + '"')
  )

  Write-LauncherMessage "Starting Rails on http://127.0.0.1:$($script:ResolvedConfig.Port) ..."

  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $script:ResolvedConfig.RubyExe
  $startInfo.WorkingDirectory = $script:ResolvedConfig.RepoRoot
  $startInfo.Arguments = ($arguments -join " ")
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.EnvironmentVariables["BUNDLE_GEMFILE"] = (Join-Path $script:ResolvedConfig.RepoRoot "Gemfile")
  $startInfo.EnvironmentVariables["BUNDLE_APP_CONFIG"] = $script:ResolvedConfig.BundleAppConfig
  $startInfo.EnvironmentVariables["BUNDLE_PATH"] = $script:ResolvedConfig.BundlePath
  $startInfo.EnvironmentVariables["BUNDLE_WITHOUT"] = "test"
  $startInfo.EnvironmentVariables["RAILS_ENV"] = $script:ResolvedConfig.RailsEnvironment
  $startInfo.EnvironmentVariables["NOTES_PATH"] = $script:ResolvedConfig.NotesPath
  $startInfo.EnvironmentVariables["PORT"] = "$($script:ResolvedConfig.Port)"

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  $process.EnableRaisingEvents = $true

  Initialize-LogFile -Path $script:ResolvedConfig.RailsLogFile -Label "RAILS"
  $script:RailsLogWriter = New-Object System.IO.StreamWriter($script:ResolvedConfig.RailsLogFile, $true, ([System.Text.UTF8Encoding]::new($false)))
  $script:RailsLogWriter.AutoFlush = $true

  $script:RailsOutputHandler = [System.Diagnostics.DataReceivedEventHandler]{
    param($sender, $eventArgs)
    if ($null -ne $eventArgs.Data) {
      $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
      $script:RailsLogWriter.WriteLine("[$timestamp] [stdout] $($eventArgs.Data)")
    }
  }

  $script:RailsErrorHandler = [System.Diagnostics.DataReceivedEventHandler]{
    param($sender, $eventArgs)
    if ($null -ne $eventArgs.Data) {
      $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
      $script:RailsLogWriter.WriteLine("[$timestamp] [stderr] $($eventArgs.Data)")
    }
  }

  $process.add_OutputDataReceived($script:RailsOutputHandler)
  $process.add_ErrorDataReceived($script:RailsErrorHandler)

  if (-not $process.Start()) {
    throw "Failed to start the Rails process."
  }

  $process.BeginOutputReadLine()
  $process.BeginErrorReadLine()
  Write-LaunchState -ProcessId $process.Id -PortNumber $script:ResolvedConfig.Port -NotesPathValue $script:ResolvedConfig.NotesPath
  Write-LauncherMessage "Rails started with PID $($process.Id)."

  return $process
}

function Close-RailsServerCapture {
  param([System.Diagnostics.Process]$Process)

  if ($null -ne $Process) {
    try { $Process.CancelOutputRead() } catch {}
    try { $Process.CancelErrorRead() } catch {}
    try {
      if ($null -ne $script:RailsOutputHandler) {
        $Process.remove_OutputDataReceived($script:RailsOutputHandler)
      }
    } catch {}
    try {
      if ($null -ne $script:RailsErrorHandler) {
        $Process.remove_ErrorDataReceived($script:RailsErrorHandler)
      }
    } catch {}
    $Process.Dispose()
  }

  if ($null -ne $script:RailsLogWriter) {
    $script:RailsLogWriter.Dispose()
    $script:RailsLogWriter = $null
  }

  $script:RailsOutputHandler = $null
  $script:RailsErrorHandler = $null
}

function Get-BrowserCandidatePaths {
  param([string]$BrowserName)

  $normalized = $BrowserName.ToLowerInvariant()

  switch ($normalized) {
    "msedge" {
      return @(
        (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe")
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe")
        (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\Application\msedge.exe")
      ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    "chrome" {
      return @(
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe")
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe")
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
      ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    default {
      return @()
    }
  }
}

function Resolve-BrowserExecutable {
  param(
    [string]$RequestedBrowser,
    [object[]]$Candidates
  )

  if (-not [string]::IsNullOrWhiteSpace($RequestedBrowser)) {
    if ([System.IO.Path]::IsPathRooted($RequestedBrowser) -and (Test-Path -LiteralPath $RequestedBrowser)) {
      return [System.IO.Path]::GetFullPath($RequestedBrowser)
    }

    $candidate = Get-Command $RequestedBrowser -ErrorAction SilentlyContinue
    if ($null -eq $candidate) {
      foreach ($path in (Get-BrowserCandidatePaths -BrowserName $RequestedBrowser)) {
        if (Test-Path -LiteralPath $path) {
          return $path
        }
      }

      throw "Requested browser '$RequestedBrowser' was not found. Set LEWISMD_BROWSER to a valid command/path or install Edge/Chrome."
    }

    return $candidate.Source
  }

  foreach ($name in $Candidates) {
    $candidate = Get-Command $name -ErrorAction SilentlyContinue
    if ($null -ne $candidate) {
      return $candidate.Source
    }

    foreach ($path in (Get-BrowserCandidatePaths -BrowserName $name)) {
      if (Test-Path -LiteralPath $path) {
        return $path
      }
    }
  }

  throw "No supported browser was found. Install Edge or Chrome, or set LEWISMD_BROWSER."
}

function Get-BrowserProfileProcesses {
  param([string]$BrowserPath)

  $browserName = [System.IO.Path]::GetFileName($BrowserPath)
  $profileDir = $script:ResolvedConfig.BrowserProfileDir

  return @(
    Get-CimInstance Win32_Process -Filter ("Name = '{0}'" -f $browserName) -ErrorAction SilentlyContinue |
      Where-Object {
        $null -ne $_.CommandLine -and $_.CommandLine -like ("*{0}*" -f $profileDir)
      }
  )
}

function Get-BrowserSessionSnapshot {
  param([string]$BrowserPath)

  $profileProcesses = @(Get-BrowserProfileProcesses -BrowserPath $BrowserPath)
  $processIds = @($profileProcesses | Select-Object -ExpandProperty ProcessId)
  $hasWindow = $false

  foreach ($processId in $processIds) {
    $runtimeProcess = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -ne $runtimeProcess -and $runtimeProcess.MainWindowHandle -ne 0) {
      $hasWindow = $true
      break
    }
  }

  $signature = ($processIds | Sort-Object) -join ","

  return [pscustomobject]@{
    ProcessIds = $processIds
    HasWindow = $hasWindow
    Signature = $signature
  }
}

function Wait-ForBrowserSessionReady {
  param(
    [string]$BrowserPath,
    [int]$TimeoutSeconds,
    [int]$StabilitySeconds
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $lastSignature = $null
  $stableSince = $null

  while ((Get-Date) -lt $deadline) {
    $snapshot = Get-BrowserSessionSnapshot -BrowserPath $BrowserPath

    if ($snapshot.ProcessIds.Count -eq 0) {
      $lastSignature = $null
      $stableSince = $null
      Start-Sleep -Milliseconds 500
      continue
    }

    if ($snapshot.HasWindow) {
      return $snapshot
    }

    if ($snapshot.Signature -eq $lastSignature) {
      if ($null -eq $stableSince) {
        $stableSince = Get-Date
      } elseif (((Get-Date) - $stableSince).TotalSeconds -ge $StabilitySeconds) {
        return $snapshot
      }
    } else {
      $lastSignature = $snapshot.Signature
      $stableSince = Get-Date
    }

    Start-Sleep -Milliseconds 500
  }

  return $null
}

function Start-BrowserSession {
  param([string]$BrowserPath)

  Ensure-Directory -Path $script:ResolvedConfig.BrowserProfileDir

  $browserArguments = @(
    "--user-data-dir=$($script:ResolvedConfig.BrowserProfileDir)"
    "--app=http://127.0.0.1:$($script:ResolvedConfig.Port)"
  )

  Write-LauncherMessage "Launching browser app mode with $BrowserPath ..."

  $existingSnapshot = Wait-ForBrowserSessionReady `
    -BrowserPath $BrowserPath `
    -TimeoutSeconds ([Math]::Max($script:ResolvedConfig.BrowserSessionStabilitySeconds + 1, 3)) `
    -StabilitySeconds $script:ResolvedConfig.BrowserSessionStabilitySeconds
  if ($null -ne $existingSnapshot) {
    $existingIds = ($existingSnapshot.ProcessIds -join ", ")
    Write-LauncherMessage "Reusing existing LewisMD browser session for the dedicated profile (PIDs: $existingIds)." "WARN"

    return [pscustomobject]@{
      BrowserPath = $BrowserPath
      ProcessIds = @($existingSnapshot.ProcessIds)
      Reused = $true
    }
  }

  if (-not (Wait-ForBrowserSessionToClose -BrowserPath $BrowserPath -TimeoutSeconds 6 -StabilitySeconds $script:ResolvedConfig.BrowserShutdownStabilitySeconds)) {
    throw "The dedicated LewisMD browser profile is still shutting down. Wait a moment and try again."
  }

  for ($attempt = 1; $attempt -le $script:ResolvedConfig.BrowserLaunchRetryCount; $attempt++) {
    if ($attempt -gt 1) {
      Write-LauncherMessage (
        "Retrying browser launch for the dedicated LewisMD profile (attempt {0} of {1})." -f
        $attempt,
        $script:ResolvedConfig.BrowserLaunchRetryCount
      ) "WARN"
      Start-Sleep -Seconds $script:ResolvedConfig.BrowserLaunchRetryDelaySeconds
    }

    $process = Start-Process -FilePath $BrowserPath `
      -ArgumentList $browserArguments `
      -WorkingDirectory $script:ResolvedConfig.RepoRoot `
      -PassThru

    $snapshot = Wait-ForBrowserSessionReady `
      -BrowserPath $BrowserPath `
      -TimeoutSeconds $script:ResolvedConfig.BrowserStartupTimeoutSeconds `
      -StabilitySeconds $script:ResolvedConfig.BrowserSessionStabilitySeconds

    if ($null -ne $snapshot) {
      $joinedIds = ($snapshot.ProcessIds -join ", ")
      Write-LauncherMessage "Browser session is active for the dedicated LewisMD profile (PIDs: $joinedIds)."

      return [pscustomobject]@{
        BrowserPath = $BrowserPath
        ProcessIds = $snapshot.ProcessIds
        Reused = $false
      }
    }

    Write-LauncherMessage "Browser profile launch did not stabilize on attempt $attempt." "WARN"
    try {
      $process.Refresh()
      if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      }
    } catch {
      Write-LauncherMessage "Could not clean up transient browser bootstrap process $($process.Id)." "WARN"
    } finally {
      $process.Dispose()
    }

    Wait-ForBrowserSessionToClose `
      -BrowserPath $BrowserPath `
      -TimeoutSeconds 6 `
      -StabilitySeconds $script:ResolvedConfig.BrowserShutdownStabilitySeconds | Out-Null
  }

  throw "The browser app window did not stay open for the dedicated LewisMD profile. Close any conflicting launcher profile windows and try again."
}

function Wait-ForBrowserSessionToClose {
  param(
    [string]$BrowserPath,
    [int]$TimeoutSeconds = 0,
    [int]$StabilitySeconds = 2
  )

  $absenceSince = $null
  $deadline = if ($TimeoutSeconds -gt 0) {
    (Get-Date).AddSeconds($TimeoutSeconds)
  } else {
    $null
  }

  while ($true) {
    $snapshot = Get-BrowserSessionSnapshot -BrowserPath $BrowserPath
    if ($snapshot.ProcessIds.Count -eq 0) {
      if ($null -eq $absenceSince) {
        $absenceSince = Get-Date
      } elseif (((Get-Date) - $absenceSince).TotalSeconds -ge $StabilitySeconds) {
        return $true
      }
    } else {
      $absenceSince = $null
    }

    if ($null -ne $deadline -and (Get-Date) -ge $deadline) {
      return $false
    }

    Start-Sleep -Seconds 1
  }
}

function Resolve-Config {
  $defaultsPath = Resolve-ScriptPath "launcher.defaults.psd1"
  if (-not (Test-Path -LiteralPath $defaultsPath)) {
    throw "Launcher defaults file not found: $defaultsPath"
  }

  $defaults = Import-PowerShellDataFile $defaultsPath
  $repoRoot = Resolve-ScriptPath "..\.."

  $resolvedPort = if ($PSBoundParameters.ContainsKey("Port")) {
    $Port
  } elseif ($env:LEWISMD_PORT) {
    [int]$env:LEWISMD_PORT
  } else {
    [int]$defaults.DefaultPort
  }

  if ($resolvedPort -lt 1 -or $resolvedPort -gt 65535) {
    throw "Port $resolvedPort is outside the valid TCP range."
  }

  $resolvedNotesPath = if ($PSBoundParameters.ContainsKey("NotesPath")) {
    Resolve-LauncherPath -PathValue $NotesPath -RepoRoot $repoRoot
  } elseif ($env:LEWISMD_NOTES_PATH) {
    Resolve-LauncherPath -PathValue $env:LEWISMD_NOTES_PATH -RepoRoot $repoRoot
  } else {
    Resolve-LauncherPath -PathValue $defaults.DefaultNotesPath -RepoRoot $repoRoot
  }

  return [pscustomobject]@{
    RepoRoot = $repoRoot
    RubyVersion = $defaults.RubyVersion
    RailsEnvironment = $defaults.RailsEnvironment
    Port = $resolvedPort
    NotesPath = $resolvedNotesPath
    RequestedBrowser = if ($PSBoundParameters.ContainsKey("Browser")) { $Browser } elseif ($env:LEWISMD_BROWSER) { $env:LEWISMD_BROWSER } else { $null }
    PortableRubyDir = Resolve-LauncherPath -PathValue $defaults.PortableRubyDir -RepoRoot $repoRoot
    RubyExe = Resolve-LauncherPath -PathValue (Join-Path $defaults.PortableRubyDir "bin\ruby.exe") -RepoRoot $repoRoot
    BundleCmd = Resolve-LauncherPath -PathValue (Join-Path $defaults.PortableRubyDir "bin\bundle.bat") -RepoRoot $repoRoot
    BundlePath = Resolve-LauncherPath -PathValue $defaults.BundlePath -RepoRoot $repoRoot
    BundleAppConfig = [System.IO.Path]::GetFullPath((Join-Path (Resolve-LauncherPath -PathValue $defaults.StateDirectory -RepoRoot $repoRoot) "bundle-config"))
    BinRailsScript = Resolve-LauncherPath -PathValue "bin\rails" -RepoRoot $repoRoot
    StateDirectory = Resolve-LauncherPath -PathValue $defaults.StateDirectory -RepoRoot $repoRoot
    RailsLogFile = Resolve-LauncherPath -PathValue $defaults.RailsLogFile -RepoRoot $repoRoot
    LauncherLogFile = Resolve-LauncherPath -PathValue $defaults.LauncherLogFile -RepoRoot $repoRoot
    StateFile = Resolve-LauncherPath -PathValue $defaults.StateFile -RepoRoot $repoRoot
    BrowserProfileDir = Resolve-LauncherPath -PathValue $defaults.BrowserProfileDir -RepoRoot $repoRoot
    HealthUri = "http://127.0.0.1:$resolvedPort$($defaults.HealthEndpointPath)"
    BrowserCommands = @($defaults.BrowserCommands)
    BrowserStartupTimeoutSeconds = [int]$defaults.BrowserStartupTimeoutSeconds
    BrowserSessionStabilitySeconds = [int]$defaults.BrowserSessionStabilitySeconds
    BrowserShutdownStabilitySeconds = [int]$defaults.BrowserShutdownStabilitySeconds
    BrowserLaunchRetryCount = [int]$defaults.BrowserLaunchRetryCount
    BrowserLaunchRetryDelaySeconds = [int]$defaults.BrowserLaunchRetryDelaySeconds
    RailsServerPidFile = [System.IO.Path]::GetFullPath((Join-Path (Resolve-LauncherPath -PathValue $defaults.StateDirectory -RepoRoot $repoRoot) "server.pid"))
  }
}

$script:ResolvedConfig = Resolve-Config
$script:LauncherMode = if ($StopOnly) { "stop" } elseif ($ValidateOnly) { "validate" } else { "launch" }
$script:LauncherSessionId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), ([System.Guid]::NewGuid().ToString("N").Substring(0, 8))

Ensure-Directory -Path $script:ResolvedConfig.StateDirectory
Ensure-Directory -Path $script:ResolvedConfig.BundleAppConfig
Initialize-LogFile -Path $script:ResolvedConfig.LauncherLogFile -Label "LAUNCHER"

Write-LauncherMessage "Repo root: $($script:ResolvedConfig.RepoRoot)"
Write-LauncherMessage "Port: $($script:ResolvedConfig.Port)"
Write-LauncherMessage "Rails environment: $($script:ResolvedConfig.RailsEnvironment)"
Write-LauncherMessage "Session id: $($script:LauncherSessionId)"
Write-LauncherMessage "Launcher log file: $($script:ResolvedConfig.LauncherLogFile)"
Write-LauncherMessage "Rails log file: $($script:ResolvedConfig.RailsLogFile)"

try {
  if ($ValidateOnly -and $StopOnly) {
    throw "Use either -ValidateOnly or -StopOnly, not both."
  }

  if ($StopOnly) {
    $managedProcessId = Resolve-ManagedProcessIdForStop

    if ($null -eq $managedProcessId) {
      Write-LauncherMessage "No launcher-managed Rails process was found. Cleanup is already complete."
      Remove-LaunchState
      return
    }

    if (-not (Test-ProcessAlive -ProcessId $managedProcessId)) {
      Write-LauncherMessage "Removing stale launcher state for dead process $managedProcessId." "WARN"
      Remove-LaunchState
      return
    }

    Stop-ManagedRailsServer -ProcessId $managedProcessId -Reason "manual stop helper"
    return
  }

  Ensure-Directory -Path $script:ResolvedConfig.NotesPath
  Write-LauncherMessage "Notes path: $($script:ResolvedConfig.NotesPath)"

  if ($SkipRuntimeValidation) {
    Write-LauncherMessage "Skipping duplicate runtime validation because bootstrap already succeeded."
  } else {
    if (-not (Test-Path -LiteralPath $script:ResolvedConfig.RubyExe)) {
      throw "Portable Ruby was not found at $($script:ResolvedConfig.RubyExe). Run bootstrap after extracting the runtime."
    }

    & $script:ResolvedConfig.RubyExe --version *> $null
    if ($LASTEXITCODE -ne 0) {
      throw "Portable Ruby could not be executed from $($script:ResolvedConfig.RubyExe)."
    }

    Test-BundlerReady
  }

  if ($ValidateOnly) {
    Write-LauncherMessage "Validation-only mode completed successfully."
    return
  }

  $managedState = Read-LaunchState -Path $script:ResolvedConfig.StateFile
  $managedProcessId = $null
  $managedProcess = $null
  $browserSession = $null

  try {
    if ($null -ne $managedState) {
      $managedProcessId = [int]$managedState.pid
      $statePort = if ($null -ne $managedState.port) { [int]$managedState.port } else { $null }
      $stateNotesPath = if ($null -ne $managedState.notesPath) { [string]$managedState.notesPath } else { $null }

      if (-not (Test-ProcessAlive -ProcessId $managedProcessId)) {
        Write-LauncherMessage "Removing stale launcher state for dead process $managedProcessId." "WARN"
        Remove-LaunchState
        $managedState = $null
        $managedProcessId = $null
      } elseif ($statePort -ne $script:ResolvedConfig.Port -or $stateNotesPath -ne $script:ResolvedConfig.NotesPath) {
        Write-LauncherMessage "Existing launcher-managed server does not match the requested port or notes path. Restarting it." "WARN"
        Stop-ManagedRailsServer -ProcessId $managedProcessId -Reason "launcher settings changed"
        $managedState = $null
        $managedProcessId = $null
      } elseif (-not (Test-HealthEndpoint -Uri $script:ResolvedConfig.HealthUri)) {
        Write-LauncherMessage "Existing launcher-managed server is unhealthy. Restarting it." "WARN"
        Stop-ManagedRailsServer -ProcessId $managedProcessId -Reason "health endpoint not ready"
        $managedState = $null
        $managedProcessId = $null
      } else {
        Write-LauncherMessage "Reusing existing launcher-managed Rails server $managedProcessId."
      }
    }

    if ($null -eq $managedState) {
      $listeningProcess = Get-ListeningProcessId -PortNumber $script:ResolvedConfig.Port
      if ($null -ne $listeningProcess) {
        throw "Port $($script:ResolvedConfig.Port) is already in use by PID $listeningProcess. Stop that process or choose another LEWISMD_PORT."
      }

      $managedProcess = Start-RailsServerProcess
      $managedProcessId = $managedProcess.Id
      Wait-ForHealthEndpoint -Uri $script:ResolvedConfig.HealthUri -TimeoutSeconds 30 -ServerProcess $managedProcess
      Write-LauncherMessage "LewisMD is healthy at $($script:ResolvedConfig.HealthUri)."
    }

    $browserPath = Resolve-BrowserExecutable -RequestedBrowser $script:ResolvedConfig.RequestedBrowser -Candidates $script:ResolvedConfig.BrowserCommands
    Write-LauncherMessage "Using browser executable: $browserPath"

    $browserSession = Start-BrowserSession -BrowserPath $browserPath
    Write-LauncherMessage "Waiting for the LewisMD browser session to close..."
    Wait-ForBrowserSessionToClose -BrowserPath $browserSession.BrowserPath
    Write-LauncherMessage "Browser app window closed."
  } finally {
    if ($null -ne $managedProcessId) {
      Stop-ManagedRailsServer -ProcessId $managedProcessId -Reason "browser session ended"
    }

    if ($null -ne $managedProcess) {
      Close-RailsServerCapture -Process $managedProcess
    } elseif ($null -ne $script:RailsLogWriter) {
      Close-RailsServerCapture -Process $null
    }
  }
} catch {
  $errorMessage = $_.Exception.Message
  if ([string]::IsNullOrWhiteSpace($errorMessage)) {
    $errorMessage = $_.ToString()
  }

  Write-LauncherMessage $errorMessage "ERROR"

  if ($null -ne $_.InvocationInfo -and $null -ne $_.InvocationInfo.ScriptLineNumber -and $_.InvocationInfo.ScriptLineNumber -gt 0) {
    Write-LauncherMessage ("Failure location: line {0} in {1}" -f $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.ScriptName) "ERROR"
  }

  throw
} finally {
  Write-LauncherMessage "Launcher session finished."
}
