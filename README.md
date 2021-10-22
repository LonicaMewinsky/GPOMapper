# GPOMapper
No-good terrible powershell script that processes GPOs for AD-Sync'd users' mapped drives.

How to use:

Run GPOMapper_Install.ps1 as admin. Contains -install/uninstall switches. This will copy scripts
locally and create a scheduled task. Task will run at logon or networking change (like VPN).

Writes content to "C:\ProgramData\GPOMapper"

For detection: HKLM:\SOFTWARE\GPOMapper\[string]Version=2.0
