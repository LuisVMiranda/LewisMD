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
Dim scriptDir, repoRoot, startScript, splashSource, splashExecutable, launcherLog, railsLog, progressFile, iconPath, splashLogoPath, shortcutPath
Dim command, splashCommand, cscExe
Dim exitCode, argument, dryRun, installShortcut
Dim hiddenWindowStyle, splashWindowStyle

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
repoRoot = fso.GetAbsolutePathName(fso.BuildPath(scriptDir, "..\.."))
startScript = fso.BuildPath(scriptDir, "start_lewismd.bat")
splashSource = fso.BuildPath(scriptDir, "show_lewismd_splash.cs")
splashExecutable = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "tmp\windows-launcher\LewisMDSplash.exe"))
launcherLog = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "tmp\windows-launcher\launcher.log"))
railsLog = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "tmp\windows-launcher\rails.log"))
progressFile = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "tmp\windows-launcher\launcher-progress.json"))
iconPath = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "public\icon.ico"))
splashLogoPath = fso.GetAbsolutePathName(fso.BuildPath(repoRoot, "public\icon.png"))
shortcutPath = fso.BuildPath(shell.SpecialFolders("Desktop"), "LewisMD.lnk")
cscExe = ResolveCscPath()
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
splashCommand = """" & splashExecutable & """ """ & progressFile & """ """ & splashLogoPath & """ """ & startScript & """ """ & launcherLog & """"

If dryRun Then
  WScript.Echo "startScript=" & startScript
  WScript.Echo "splashSource=" & splashSource
  WScript.Echo "splashExecutable=" & splashExecutable
  WScript.Echo "cscExe=" & cscExe
  WScript.Echo "launcherLog=" & launcherLog
  WScript.Echo "railsLog=" & railsLog
  WScript.Echo "progressFile=" & progressFile
  WScript.Echo "iconPath=" & iconPath
  WScript.Echo "splashLogoPath=" & splashLogoPath
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
If EnsureSplashExecutable() Then
  DeleteProgressFile
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

Function EnsureSplashExecutable()
  Dim outputFolder, compileCommand, compileExitCode

  EnsureSplashExecutable = False

  If Not fso.FileExists(splashSource) Then
    Exit Function
  End If

  If Len(cscExe) = 0 Or Not fso.FileExists(cscExe) Then
    Exit Function
  End If

  outputFolder = fso.GetParentFolderName(splashExecutable)
  If Not fso.FolderExists(outputFolder) Then
    fso.CreateFolder(outputFolder)
  End If

  If fso.FileExists(splashExecutable) Then
    If fso.GetFile(splashExecutable).DateLastModified >= fso.GetFile(splashSource).DateLastModified Then
      EnsureSplashExecutable = True
      Exit Function
    End If
  End If

  compileCommand = QuoteForCmd(cscExe) & " /nologo /target:winexe /out:" & QuoteForCmd(splashExecutable)
  compileCommand = compileCommand & " /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Runtime.Serialization.dll "
  compileCommand = compileCommand & QuoteForCmd(splashSource)

  compileExitCode = shell.Run(compileCommand, hiddenWindowStyle, True)
  If compileExitCode = 0 And fso.FileExists(splashExecutable) Then
    EnsureSplashExecutable = True
  End If
End Function

Sub DeleteProgressFile()
  On Error Resume Next
  If fso.FileExists(progressFile) Then
    fso.DeleteFile progressFile, True
  End If
  On Error GoTo 0
End Sub

Function ResolveCscPath()
  Dim candidates, candidate

  candidates = Array( _
    shell.ExpandEnvironmentStrings("%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"), _
    shell.ExpandEnvironmentStrings("%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe") _
  )

  ResolveCscPath = ""
  For Each candidate In candidates
    If fso.FileExists(candidate) Then
      ResolveCscPath = candidate
      Exit Function
    End If
  Next
End Function

Function QuoteForCmd(value)
  QuoteForCmd = """" & value & """"
End Function

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
