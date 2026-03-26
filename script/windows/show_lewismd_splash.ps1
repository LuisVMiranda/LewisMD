[CmdletBinding()]
param(
  [string]$ProgressFile,
  [string]$IconPath,
  [int]$PollIntervalMilliseconds = 250,
  [int]$StartupTimeoutSeconds = 90,
  [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class LewisMDSplashNativeMethods
{
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

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

  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $PathValue))
}

function Resolve-Config {
  $defaultsPath = Resolve-ScriptPath "launcher.defaults.psd1"
  if (-not (Test-Path -LiteralPath $defaultsPath)) {
    throw "Launcher defaults file not found: $defaultsPath"
  }

  $defaults = Import-PowerShellDataFile $defaultsPath
  $repoRoot = Resolve-ScriptPath "..\.."

  $resolvedProgressFile = if ($PSBoundParameters.ContainsKey("ProgressFile")) {
    Resolve-LauncherPath -PathValue $ProgressFile -RepoRoot $repoRoot
  } else {
    Resolve-LauncherPath -PathValue $defaults.ProgressFile -RepoRoot $repoRoot
  }

  $resolvedIconPath = if ($PSBoundParameters.ContainsKey("IconPath")) {
    Resolve-LauncherPath -PathValue $IconPath -RepoRoot $repoRoot
  } else {
    Resolve-LauncherPath -PathValue "public\icon.png" -RepoRoot $repoRoot
  }

  return [pscustomobject]@{
    RepoRoot = $repoRoot
    ProgressFile = $resolvedProgressFile
    IconPath = $resolvedIconPath
    VisibleLauncherScript = Resolve-LauncherPath -PathValue "script\windows\start_lewismd.bat" -RepoRoot $repoRoot
    LauncherLogFile = Resolve-LauncherPath -PathValue "tmp\windows-launcher\launcher.log" -RepoRoot $repoRoot
    PollIntervalMilliseconds = [Math]::Max(100, $PollIntervalMilliseconds)
    StartupTimeoutSeconds = [Math]::Max(15, $StartupTimeoutSeconds)
  }
}

function Read-ProgressPayload {
  param(
    [string]$Path,
    [hashtable]$Fallback,
    [datetime]$MinimumUpdatedAt
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject]$Fallback
  }

  try {
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
      return [pscustomobject]$Fallback
    }

    $payload = $raw | ConvertFrom-Json -ErrorAction Stop
    $percent = if ($null -ne $payload.percent) { [int]$payload.percent } else { [int]$Fallback.percent }
    $updatedAt = $null
    if ($null -ne $payload.updatedAt) {
      try {
        $updatedAt = [datetime]$payload.updatedAt
      } catch {
        $updatedAt = $null
      }
    }

    if ($null -eq $updatedAt -or $updatedAt -lt $MinimumUpdatedAt) {
      return [pscustomobject]$Fallback
    }

    return [pscustomobject]@{
      state = if ($null -ne $payload.state) { [string]$payload.state } else { [string]$Fallback.state }
      percent = [Math]::Max(0, [Math]::Min(100, $percent))
      message = if ($null -ne $payload.message -and -not [string]::IsNullOrWhiteSpace([string]$payload.message)) {
        [string]$payload.message
      } else {
        [string]$Fallback.message
      }
      step = if ($null -ne $payload.step) { [string]$payload.step } else { [string]$Fallback.step }
    }
  } catch {
    return [pscustomobject]$Fallback
  }
}

function Get-DefaultProgressPayload {
  return @{
    state = "starting"
    percent = 5
    message = "Starting LewisMD..."
    step = "prepare"
  }
}

function Get-SplashMutexName {
  param([string]$ProgressPath)

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($ProgressPath.ToLowerInvariant())
  $hashBytes = [System.Security.Cryptography.SHA256]::HashData($bytes)
  $hash = [Convert]::ToHexString($hashBytes)

  return "Local\LewisMD-Splash-{0}" -f $hash
}

function Load-BitmapImage {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
  $bitmap.BeginInit()
  $bitmap.UriSource = [System.Uri]::new($Path)
  $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $bitmap.EndInit()
  $bitmap.Freeze()

  return $bitmap
}

function Start-SpinnerAnimation {
  param([System.Windows.Media.RotateTransform]$RotateTransform)

  $animation = New-Object System.Windows.Media.Animation.DoubleAnimation
  $animation.From = 0
  $animation.To = 360
  $animation.Duration = [System.Windows.Duration]::new([TimeSpan]::FromSeconds(1.6))
  $animation.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $animation.EasingFunction = New-Object System.Windows.Media.Animation.SineEase

  $RotateTransform.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $animation)
}

function Stop-SpinnerAnimation {
  param([System.Windows.Media.RotateTransform]$RotateTransform)

  $RotateTransform.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
}

function Start-FadeClose {
  param([System.Windows.Window]$Window)

  if ($script:SplashClosing) {
    return
  }

  $script:SplashClosing = $true
  $fadeAnimation = New-Object System.Windows.Media.Animation.DoubleAnimation
  $fadeAnimation.From = $Window.Opacity
  $fadeAnimation.To = 0
  $fadeAnimation.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(220))
  $fadeAnimation.add_Completed({
    $Window.Close()
  })

  $Window.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeAnimation)
}

function Hide-ConsoleWindow {
  param([IntPtr]$ConsoleHandle)

  if ($ConsoleHandle -eq [IntPtr]::Zero) {
    return
  }

  [LewisMDSplashNativeMethods]::ShowWindow($ConsoleHandle, 0) | Out-Null
}

function Promote-SplashWindow {
  param([System.Windows.Window]$Window)

  try {
    $Window.ShowActivated = $true
    $Window.Topmost = $true
    $Window.Activate() | Out-Null
    $Window.Focus() | Out-Null
    $Window.Topmost = $false
    $Window.Topmost = $true
  } catch {
  }
}

function Get-ErrorHintText {
  param(
    [string]$Step,
    [object]$Config
  )

  $visibleLauncher = $Config.VisibleLauncherScript
  $launcherLog = $Config.LauncherLogFile

  if ($Step -eq "timeout") {
    return "LewisMD may still finish opening, but if it keeps stalling, run the visible launcher for details:`n$visibleLauncher`n`nLauncher log:`n$launcherLog"
  }

  return "Open the visible launcher for details:`n$visibleLauncher`n`nLauncher log:`n$launcherLog"
}

$resolvedConfig = Resolve-Config
$fallbackPayload = Get-DefaultProgressPayload

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="LewisMD"
        Width="560"
        Height="380"
        ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ShowActivated="True"
        ShowInTaskbar="False"
        Topmost="True">
  <Border CornerRadius="26"
          Padding="28"
          BorderThickness="1"
          BorderBrush="#26FFFFFF">
    <Border.Background>
      <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#FF2D1B4E" Offset="0"/>
        <GradientStop Color="#FFFF6B9D" Offset="1"/>
      </LinearGradientBrush>
    </Border.Background>
    <Border.Effect>
      <DropShadowEffect BlurRadius="32" ShadowDepth="0" Opacity="0.28"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0" VerticalAlignment="Center" HorizontalAlignment="Center">
        <Image x:Name="LogoImage"
               Width="120"
               Height="120"
               Stretch="Uniform"
               Margin="0,0,0,20"/>

        <Grid Width="60" Height="60" Margin="0,0,0,18">
          <Ellipse Width="44"
                   Height="44"
                   Stroke="#35FFFFFF"
                   StrokeThickness="4"
                   HorizontalAlignment="Center"
                   VerticalAlignment="Center"/>
          <Path x:Name="SpinnerArc"
                Stroke="White"
                StrokeThickness="4"
                StrokeStartLineCap="Round"
                StrokeEndLineCap="Round"
                Data="M 30,8 A 22,22 0 0 1 52,30"
                HorizontalAlignment="Center"
                VerticalAlignment="Center">
            <Path.RenderTransform>
              <RotateTransform x:Name="SpinnerRotate" CenterX="30" CenterY="30"/>
            </Path.RenderTransform>
          </Path>
        </Grid>

        <TextBlock Text="LewisMD"
                   FontSize="32"
                   FontWeight="SemiBold"
                   Foreground="White"
                   HorizontalAlignment="Center"
                   Margin="0,0,0,8"/>

        <TextBlock x:Name="StatusText"
                   Text="Starting LewisMD..."
                   FontSize="15"
                   Foreground="#F5FFFFFF"
                   TextAlignment="Center"
                   HorizontalAlignment="Center"
                   Margin="0,0,0,4"
                   TextWrapping="Wrap"/>

        <TextBlock x:Name="DetailText"
                   Text="Preparing the local launcher"
                   FontSize="13"
                   Foreground="#CCFFFFFF"
                   TextAlignment="Center"
                   HorizontalAlignment="Center"
                   MaxWidth="360"
                   TextWrapping="Wrap"/>

        <TextBlock x:Name="HintText"
                   Visibility="Collapsed"
                   FontSize="12"
                   Foreground="#F2FFFFFF"
                   TextAlignment="Center"
                   HorizontalAlignment="Center"
                   MaxWidth="420"
                   Margin="0,14,0,0"
                   TextWrapping="Wrap"/>
      </StackPanel>

      <StackPanel Grid.Row="1" Margin="0,16,0,0">
        <ProgressBar x:Name="ProgressBar"
                     Minimum="0"
                     Maximum="100"
                     Height="8"
                     Value="5"
                     Foreground="#FFFFFFFF"
                     Background="#26FFFFFF"
                     BorderThickness="0"/>
        <DockPanel Margin="0,10,0,0">
          <TextBlock x:Name="StepText"
                     DockPanel.Dock="Left"
                     Text="prepare"
                     FontSize="12"
                     Foreground="#CCFFFFFF"/>
          <TextBlock x:Name="PercentText"
                     DockPanel.Dock="Right"
                     Text="5%"
                     FontSize="12"
                     FontWeight="SemiBold"
                     Foreground="#FFFFFFFF"
                     HorizontalAlignment="Right"/>
        </DockPanel>
        <Button x:Name="DismissButton"
                Visibility="Collapsed"
                Content="Close"
                Width="124"
                Height="34"
                HorizontalAlignment="Center"
                Margin="0,16,0,0"
                Cursor="Hand"
                Background="#1F000000"
                Foreground="White"
                BorderBrush="#40FFFFFF"
                BorderThickness="1"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
"@

[xml]$xamlDocument = $xaml
$xmlReader = New-Object System.Xml.XmlNodeReader $xamlDocument
$window = [System.Windows.Markup.XamlReader]::Load($xmlReader)

$logoImage = $window.FindName("LogoImage")
$statusText = $window.FindName("StatusText")
$detailText = $window.FindName("DetailText")
$hintText = $window.FindName("HintText")
$progressBar = $window.FindName("ProgressBar")
$percentText = $window.FindName("PercentText")
$stepText = $window.FindName("StepText")
$spinnerArc = $window.FindName("SpinnerArc")
$spinnerRotate = $window.FindName("SpinnerRotate")
$dismissButton = $window.FindName("DismissButton")

$logoBitmap = Load-BitmapImage -Path $resolvedConfig.IconPath
if ($null -ne $logoBitmap) {
  $logoImage.Source = $logoBitmap
}

if ($ValidateOnly) {
  Write-Output ("Splash helper is valid. Progress file: {0}" -f $resolvedConfig.ProgressFile)
  exit 0
}

$mutexName = Get-SplashMutexName -ProgressPath $resolvedConfig.ProgressFile
$script:SplashMutex = [System.Threading.Mutex]::new($false, $mutexName)
$script:SplashMutexHandle = $false

try {
  $script:SplashMutexHandle = $script:SplashMutex.WaitOne(0, $false)
} catch [System.Threading.AbandonedMutexException] {
  $script:SplashMutexHandle = $true
}

if (-not $script:SplashMutexHandle) {
  exit 0
}

$script:SplashClosing = $false
$script:ConsoleWindowHandle = [LewisMDSplashNativeMethods]::GetConsoleWindow()
$launchStartedAt = Get-Date
$readyObservedAt = $null
$lastPayload = [pscustomobject]$fallbackPayload

function Update-WindowFromPayload {
  param([object]$Payload)

  $statusText.Text = switch ($Payload.state) {
    "error" { "LewisMD couldn't finish starting" }
    "ready" { "LewisMD is ready" }
    "running" { "LewisMD is open" }
    "stopping" { "Closing LewisMD..." }
    "validation" { "Validating launcher runtime" }
    default { "Starting LewisMD..." }
  }

  $detailText.Text = $Payload.message
  $progressBar.Value = $Payload.percent
  $percentText.Text = ("{0}%" -f $Payload.percent)
  $stepText.Text = if ([string]::IsNullOrWhiteSpace($Payload.step)) { "prepare" } else { $Payload.step }

  if ($Payload.state -eq "error") {
    Stop-SpinnerAnimation -RotateTransform $spinnerRotate
    $spinnerArc.Stroke = [System.Windows.Media.Brushes]::MistyRose
    $progressBar.Foreground = [System.Windows.Media.Brushes]::MistyRose
    $hintText.Text = Get-ErrorHintText -Step $Payload.step -Config $resolvedConfig
    $hintText.Visibility = [System.Windows.Visibility]::Visible
    $dismissButton.Visibility = [System.Windows.Visibility]::Visible
  } else {
    $spinnerArc.Stroke = [System.Windows.Media.Brushes]::White
    $progressBar.Foreground = [System.Windows.Media.Brushes]::White
    $hintText.Visibility = [System.Windows.Visibility]::Collapsed
    $dismissButton.Visibility = [System.Windows.Visibility]::Collapsed
  }
}

Start-SpinnerAnimation -RotateTransform $spinnerRotate
Update-WindowFromPayload -Payload $lastPayload

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds($resolvedConfig.PollIntervalMilliseconds)
$timer.Add_Tick({
  $payload = Read-ProgressPayload -Path $resolvedConfig.ProgressFile -Fallback $fallbackPayload -MinimumUpdatedAt $launchStartedAt
  $lastPayload = $payload
  Update-WindowFromPayload -Payload $payload

  if ($payload.state -eq "error") {
    $timer.Stop()
    return
  }

  if ($payload.state -in @("ready", "running")) {
    if ($null -eq $readyObservedAt) {
      $readyObservedAt = Get-Date
    } elseif (((Get-Date) - $readyObservedAt).TotalMilliseconds -ge 700) {
      $timer.Stop()
      Start-FadeClose -Window $window
      return
    }
  } else {
    $readyObservedAt = $null
  }

  if (((Get-Date) - $launchStartedAt).TotalSeconds -ge $resolvedConfig.StartupTimeoutSeconds) {
    $timeoutPayload = [pscustomobject]@{
      state = "error"
      percent = 100
      message = "LewisMD is taking longer than expected to start. You can keep waiting or open the visible launcher for details."
      step = "timeout"
    }

    Update-WindowFromPayload -Payload $timeoutPayload
    $timer.Stop()
  }
})

$window.Add_SourceInitialized({
  Start-SpinnerAnimation -RotateTransform $spinnerRotate
  Promote-SplashWindow -Window $window
})

$window.Add_ContentRendered({
  Promote-SplashWindow -Window $window
  Hide-ConsoleWindow -ConsoleHandle $script:ConsoleWindowHandle
})

$dismissButton.Add_Click({
  Start-FadeClose -Window $window
})

$window.Add_Closed({
  $timer.Stop()
  Stop-SpinnerAnimation -RotateTransform $spinnerRotate
  if ($script:SplashMutexHandle) {
    try {
      $script:SplashMutex.ReleaseMutex()
    } catch {
    }
    $script:SplashMutexHandle = $false
  }
  if ($null -ne $script:SplashMutex) {
    $script:SplashMutex.Dispose()
    $script:SplashMutex = $null
  }
})

$timer.Start()
[void]$window.ShowDialog()
