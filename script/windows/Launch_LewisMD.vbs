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
Dim scriptDir, repoRoot, startScript, splashScript, launcherLog, railsLog, progressFile, iconPath, shortcutPath
Dim command, splashCommand, mshtaExe
Dim exitCode, argument, dryRun, installShortcut
Dim hiddenWindowStyle, splashWindowStyle

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
repoRoot = fso.GetAbsolutePathName(fso.BuildPath(scriptDir, "..\.."))
startScript = fso.BuildPath(scriptDir, "start_lewismd.bat")
splashScript = fso.BuildPath(scriptDir, "show_lewismd_splash.hta")
launcherLog = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "tmp\windows-launcher\launcher.log"))
railsLog = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "tmp\windows-launcher\rails.log"))
progressFile = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "tmp\windows-launcher\launcher-progress.json"))
iconPath = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "public\icon.ico"))
shortcutPath = fso.BuildPath(shell.SpecialFolders("Desktop"), "LewisMD.lnk")
mshtaExe = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\mshta.exe")
hiddenWindowStyle = 0
splashWindowStyle = 1

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
splashCommand = """" & mshtaExe & """ """ & splashScript & """"

If dryRun Then
  WScript.Echo "startScript=" & startScript
  WScript.Echo "splashScript=" & splashScript
  WScript.Echo "launcherLog=" & launcherLog
  WScript.Echo "railsLog=" & railsLog
  WScript.Echo "progressFile=" & progressFile
  WScript.Echo "iconPath=" & iconPath
  WScript.Echo "shortcutPath=" & shortcutPath
  WScript.Echo "splashCommand=" & splashCommand
  WScript.Echo "command=" & command
  WScript.Quit 0
End If

If installShortcut Then
  Call CreateDesktopShortcut()
  WScript.Echo "shortcutPath=" & shortcutPath
  WScript.Quit 0
End If

' Start the splash helper first so hidden launches still give the user immediate
' feedback while the PowerShell orchestrator boots Rails and opens the browser.
If fso.FileExists(splashScript) Then
  ' Use mshta.exe so the splash can render without spawning a browser tab or a
  ' visible PowerShell console host in front of the user.
  shell.Run splashCommand, splashWindowStyle, False
  WScript.Sleep 150
End If

' Window style 0 = hidden. WaitOnReturn=True keeps the wrapper alive until the
' visible launcher (and therefore the app session) exits.
exitCode = shell.Run(command, hiddenWindowStyle, True)

If exitCode <> 0 Then
  Call WriteProgressErrorPayload("LewisMD could not start in hidden mode. Open the visible launcher for setup help or detailed diagnostics.", "wrapper")
  WScript.Sleep 350
  MsgBox _
    "LewisMD could not start in hidden mode." & vbCrLf & vbCrLf & _
    "Run the visible launcher once to complete first-run setup or see details:" & vbCrLf & startScript & vbCrLf & vbCrLf & _
    "Launcher log:" & vbCrLf & launcherLog & vbCrLf & vbCrLf & _
    "Rails log (if Rails started):" & vbCrLf & railsLog, _
    vbCritical, _
    "LewisMD"
End If

WScript.Quit exitCode

Sub WriteProgressErrorPayload(message, stepName)
  Dim stateFolder, stream, payload

  stateFolder = fso.GetParentFolderName(progressFile)
  If Not fso.FolderExists(stateFolder) Then
    fso.CreateFolder(stateFolder)
  End If

  payload = "{""mode"":""launch"",""state"":""error"",""percent"":100,""message"":""" & EscapeJsonString(message) & """,""step"":""" & EscapeJsonString(stepName) & """,""updatedAt"":""" & IsoTimestamp(Now) & """}"

  Set stream = fso.CreateTextFile(progressFile, True, True)
  stream.Write payload
  stream.Close
End Sub

Function EscapeJsonString(value)
  value = Replace(value, "\", "\\")
  value = Replace(value, """", "\""")
  value = Replace(value, vbCrLf, "\n")
  value = Replace(value, vbCr, "\n")
  value = Replace(value, vbLf, "\n")
  EscapeJsonString = value
End Function

Function Pad2(numberValue)
  Pad2 = Right("0" & CStr(numberValue), 2)
End Function

Function IsoTimestamp(dateValue)
  IsoTimestamp = Year(dateValue) & "-" & Pad2(Month(dateValue)) & "-" & Pad2(Day(dateValue)) & "T" & _
    Pad2(Hour(dateValue)) & ":" & Pad2(Minute(dateValue)) & ":" & Pad2(Second(dateValue))
End Function

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
