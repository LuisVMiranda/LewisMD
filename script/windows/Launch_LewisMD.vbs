' LewisMD hidden Windows launcher
' -----------------------------------------------------------------------------
' This script exists for the "double-click and just open the app" experience.
' It runs the visible batch launcher completely hidden so the user does not
' need to stare at a console window while writing.
'
' Important design choice:
' - The real launch logic still lives in start_lewismd.bat and launch_lewismd.ps1
' - This wrapper only hides the terminal and surfaces a friendly message when
'   startup fails
'
' Optional validation aid for development:
'   cscript //NoLogo script\windows\Launch_LewisMD.vbs --dry-run
' This prints the resolved paths and command instead of trying to launch.

Option Explicit

Dim shell, fso
Dim scriptDir, repoRoot, startScript, launcherLog, railsLog, iconPath, shortcutPath
Dim command
Dim exitCode, argument, dryRun, installShortcut
Dim hiddenWindowStyle

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
repoRoot = fso.GetAbsolutePathName(fso.BuildPath(scriptDir, "..\.."))
startScript = fso.BuildPath(scriptDir, "start_lewismd.bat")
launcherLog = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "tmp\windows-launcher\launcher.log"))
railsLog = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "tmp\windows-launcher\rails.log"))
iconPath = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "public\icon.ico"))
shortcutPath = fso.BuildPath(shell.SpecialFolders("Desktop"), "LewisMD.lnk")
hiddenWindowStyle = 0

dryRun = False
installShortcut = False

For Each argument In WScript.Arguments
  If LCase(argument) = "--dry-run" Then
    dryRun = True
  ElseIf LCase(argument) = "--install-shortcut" Then
    installShortcut = True
  End If
Next

If Not fso.FileExists(startScript) Then
  MsgBox "LewisMD could not find the visible launcher:" & vbCrLf & vbCrLf & startScript, vbCritical, "LewisMD"
  WScript.Quit 1
End If

command = "cmd.exe /c """"" & startScript & """ --skip-bootstrap-check --no-auto-bootstrap --no-pause-on-error"""

If dryRun Then
  WScript.Echo "startScript=" & startScript
  WScript.Echo "launcherLog=" & launcherLog
  WScript.Echo "railsLog=" & railsLog
  WScript.Echo "iconPath=" & iconPath
  WScript.Echo "shortcutPath=" & shortcutPath
  WScript.Echo "command=" & command
  WScript.Quit 0
End If

If installShortcut Then
  Call CreateDesktopShortcut()
  WScript.Echo "shortcutPath=" & shortcutPath
  WScript.Quit 0
End If

' Window style 0 = hidden. WaitOnReturn=True keeps the wrapper alive until the
' visible launcher (and therefore the app session) exits.
exitCode = shell.Run(command, hiddenWindowStyle, True)

If exitCode <> 0 Then
  MsgBox _
    "LewisMD could not start in hidden mode." & vbCrLf & vbCrLf & _
    "Run the visible launcher once to complete first-run setup or see details:" & vbCrLf & startScript & vbCrLf & vbCrLf & _
    "Launcher log:" & vbCrLf & launcherLog & vbCrLf & vbCrLf & _
    "Rails log (if Rails started):" & vbCrLf & railsLog, _
    vbCritical, _
    "LewisMD"
End If

WScript.Quit exitCode

Sub CreateDesktopShortcut()
  Dim shortcut

  Set shortcut = shell.CreateShortcut(shortcutPath)
  shortcut.TargetPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\wscript.exe")
  shortcut.Arguments = """" & WScript.ScriptFullName & """"
  shortcut.WorkingDirectory = repoRoot
  shortcut.Description = "Launch LewisMD"

  If fso.FileExists(iconPath) Then
    shortcut.IconLocation = iconPath & ",0"
  End If

  shortcut.Save
End Sub
