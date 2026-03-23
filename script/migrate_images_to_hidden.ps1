$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $repoRoot "notes\.frankmd\images"
$sources = @(
  (Join-Path $repoRoot "images"),
  (Join-Path $repoRoot "notes\images")
)

New-Item -ItemType Directory -Force -Path $destination | Out-Null

foreach ($source in $sources) {
  if (-not (Test-Path $source)) { continue }

  Get-ChildItem -Path $source -File | ForEach-Object {
    Move-Item -Path $_.FullName -Destination $destination -Force
  }

  if (-not (Get-ChildItem -Path $source -Force)) {
    Remove-Item -Path $source -Force
  }
}

Write-Output "Migrated images into: $destination"
Get-ChildItem -Path $destination -File | Select-Object -ExpandProperty FullName
