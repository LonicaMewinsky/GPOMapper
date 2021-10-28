param ([string]$Mode="Install")

$installFolder = "C:\ProgramData\GPOMapper"

If ($Mode -eq "Install"){
    #add relevant windows capabilities..
    Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0 -ErrorAction Stop
    Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 -ErrorAction Stop

    #cleanup existing task if found
    Get-ScheduledTask -TaskName "GPOMapper*" | Unregister-ScheduledTask -Confirm:$false

    #copy script info to install folder
    if(!(Test-Path -Path $installFolder)) {New-Item $installFolder -ItemType Directory}
    Copy-Item $PSScriptRoot\* $installFolder -Force

    #create scheduled task
    $class = cimclass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler
    $trigger = $class | New-CimInstance -ClientOnly
    $trigger.Enabled = 1
    $trigger.Delay = "PT15S"
    $trigger.Subscription = "<QueryList><Query Id='0' Path='Microsoft-Windows-NetworkProfile/Operational'><Select Path='Microsoft-Windows-NetworkProfile/Operational'>*[System[Provider[@Name='Microsoft-Windows-NetworkProfile'] and EventID=10000]]</Select></Query></QueryList>"
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn
    $action = New-ScheduledTaskAction -Execute "$($installFolder)\Wrapper.vbs"
    $principal = New-ScheduledTaskPrincipal -GroupId "S-1-5-32-545" -Id "Author"
    $task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger,$logonTrigger
    $registeredTask = Register-ScheduledTask -TaskName "GPOMapper" -InputObject $task -Force
    
    #set registry for detection (like for configmgr or intune)
    if($registeredTask){
        New-Item -Path "HKLM:\SOFTWARE\GPOMapper" -force | New-ItemProperty -Name "Version" -PropertyType String -Value "2.0"
    }
}

If ($Mode -eq "Uninstall"){
    Unregister-ScheduledTask -TaskName "GPOMapper"
    Remove-Item -Path "HKLM:\SOFTWARE\GPOMapper" -force
}
