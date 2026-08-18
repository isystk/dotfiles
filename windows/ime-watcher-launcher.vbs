' Launcher for ime-watcher.ps1 that avoids leaving an icon on the taskbar.
' "powershell.exe -WindowStyle Hidden" alone can still flash a console window
' onto the taskbar briefly before hiding it. Running via WScript.Shell.Run
' with windowStyle=0 never creates a visible console window at all.
'
' Usage: place this file next to ime-watcher.ps1, and create the startup
' shortcut pointing at THIS file instead of at ime-watcher.ps1 directly.
' NOTE: keep this file ASCII-only (VBScript doesn't reliably support UTF-8).

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
strScriptDir = objFSO.GetParentFolderName(WScript.ScriptFullName)
strPs1Path = strScriptDir & "\ime-watcher.ps1"

objShell.Run "powershell.exe -ExecutionPolicy Bypass -File """ & strPs1Path & """", 0, False
