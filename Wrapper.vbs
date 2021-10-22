command = "powershell.exe -ExecutionPolicy Bypass -nologo -command C:\ProgramData\GPOMapper\GPOMapper.ps1"
set shell = CreateObject("WScript.Shell")
shell.Run command,0
