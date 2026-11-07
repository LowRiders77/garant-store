Option Explicit
Dim shell, fso, root, powershell, mainScript, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
powershell = shell.ExpandEnvironmentStrings("%WINDIR%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
mainScript = root & "\GarantStore.Next.ps1"
command = Chr(34) & powershell & Chr(34) & " -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & mainScript & Chr(34)
If shell.ExpandEnvironmentStrings("%GS_WPF_SMOKE%") = "1" Then
    WScript.Quit shell.Run(command, 0, True)
ElseIf shell.ExpandEnvironmentStrings("%GS_WPF_TRACK_LAUNCH%") = "1" Then
    WScript.Quit shell.Run(command, 0, True)
Else
    shell.Run command, 0, False
End If
