Option Explicit
Dim shell, fso, scriptDir, psScript, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = fso.BuildPath(scriptDir, "Set-InternalDisplayRefresh.ps1")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """ -Mode Auto -BatteryHz 60 -AcHz 120 -Quiet"
shell.Run cmd, 0, False
