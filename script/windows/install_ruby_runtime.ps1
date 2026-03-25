[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$RepoRoot,

  [Parameter(Mandatory = $true)]
  [string]$InstallDir,

  [Parameter(Mandatory = $true)]
  [string]$RubyExePath,

  [Parameter(Mandatory = $true)]
  [string]$LauncherLogFile,

  [Parameter(Mandatory = $true)]
  [string]$InstallerUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Directory {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-InstallerMessage {
  param(
    [string]$Message,
    [ValidateSet("INFO", "WARN", "ERROR")]
    [string]$Level = "INFO"
  )

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "[$timestamp] [runtime] [$Level] $Message"
  Add-Content -Path $LauncherLogFile -Value $line -Encoding UTF8

  switch ($Level) {
    "WARN" { Write-Host "[runtime] $Message" -ForegroundColor Yellow }
    "ERROR" { Write-Host "[runtime] $Message" -ForegroundColor Red }
    default { Write-Host "[runtime] $Message" }
  }
}

Ensure-Directory -Path (Split-Path -Parent $LauncherLogFile)
Ensure-Directory -Path (Split-Path -Parent $InstallDir)

$downloadDirectory = Join-Path $RepoRoot "tmp/windows-launcher/downloads"
Ensure-Directory -Path $downloadDirectory

$installerName = Split-Path -Path $InstallerUrl -Leaf
$installerPath = Join-Path $downloadDirectory $installerName

try {
  if (Test-Path -LiteralPath $RubyExePath) {
    Write-InstallerMessage "Ruby runtime already exists at $RubyExePath. Skipping installer download."
    exit 0
  }

  if (Test-Path -LiteralPath $InstallDir) {
    Write-InstallerMessage "Removing incomplete runtime directory at $InstallDir before reinstalling." "WARN"
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
  }

  if (-not (Test-Path -LiteralPath $installerPath)) {
    Write-InstallerMessage "Downloading the official RubyInstaller runtime from $InstallerUrl ..."
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $installerPath
  } else {
    Write-InstallerMessage "Using the cached RubyInstaller download at $installerPath."
  }

  $arguments = @(
    "/verysilent"
    "/currentuser"
    ("/dir=" + $InstallDir)
    "/tasks=noassocfiles,nomodpath,noridkinstall"
  )

  Write-InstallerMessage "Installing the repo-local Ruby runtime into $InstallDir ..."
  $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -PassThru -Wait

  if ($process.ExitCode -ne 0) {
    throw "RubyInstaller exited with code $($process.ExitCode)."
  }

  if (-not (Test-Path -LiteralPath $RubyExePath)) {
    throw "RubyInstaller finished, but ruby.exe was not created at $RubyExePath."
  }

  $rubyVersionOutput = & $RubyExePath --version
  if ($LASTEXITCODE -ne 0) {
    throw "The installed runtime could not execute ruby.exe successfully."
  }

  Write-InstallerMessage "Repo-local Ruby runtime is ready: $rubyVersionOutput"
} catch {
  $message = $_.Exception.Message
  if ([string]::IsNullOrWhiteSpace($message)) {
    $message = $_.ToString()
  }

  Write-InstallerMessage $message "ERROR"
  throw
}
