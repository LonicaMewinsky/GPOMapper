Import-Module GroupPolicy
if(!($?)){return "Group Policy module not installed!"}
Import-Module ActiveDirectory
if(!($?)){return "Active Directory module not installed!"}

#Test path to SYSVOL to confirm connectivity to domain and access to policies folder
$sysvolPath = "\\$($env:USERDNSDOMAIN)\SYSVOL\$($env:USERDNSDOMAIN)\Policies"
if(!(Test-Path -Path $sysvolPath)){return "No connection to reference path ($sysvolPath)"}

#Get user object
$myUser = Get-ADUser -Identity $env:username -Server $env:USERDNSDOMAIN
if(!($?)){return "Could not access information for user ($env:USERNAME)"}
$userOU = "OU="+($myUser.DistinguishedName -split "OU=",2)[1]
$ldapFilter = "(member:1.2.840.113556.1.4.1941:=$($myUser.DistinguishedName))"
$memberOf = Get-ADGroup -Server $env:USERDNSDOMAIN -LDAPFilter $ldapFilter | select -ExpandProperty Name

#Make list of policies linked to user's OU
#consider: sites links
$inheritedGPOLinks = (Get-GPInheritance -Target $userOU -Domain $env:USERDNSDOMAIN).InheritedGpoLinks | Where-Object {$_.Enabled -eq "True"}
$GPOLinks = (Get-GPInheritance -Target $userOU -Domain $env:USERDNSDOMAIN).GpoLinks | Where-Object {$_.Enabled -eq "True"}
$combinedGPOLinks = ($inheritedGPOLinks + $GPOLinks)
if(!($combinedGPOLinks)){return "Could not generate list of associated policies."}

#Mapping function for later use
function DriveMappingFunction($driveMapObject){
    #if the task got this far, we assume any existing drive letter should be deleted -- remove if found
    #if the action is "D" for delete, job is done. return
    Get-PSDrive -Name $driveMapObject.DriveLetter -ErrorAction SilentlyContinue  | Remove-PSDrive -Scope Global
    if($driveMapObject.Action -eq "D"){ return }

    #map it
    Write-Output "Mapping $($driveMapObject.DrivePath)"
    $mappedDrive = New-PSDrive -Name $driveMapObject.DriveLetter -Root $driveMapObject.DrivePath -PSProvider FileSystem -Persist -scope Global
        if($driveMapObject.DriveLabel){
            (New-Object -ComObject Shell.Application).NameSpace("$($driveMapObject.DriveLetter):").Self.Name = $driveMapObject.DriveLabel
        }

}

#Resolve policies into neat little objects for further processing
$gpoMappings = @()
foreach($linkedGPO in $combinedGPOLinks){
    $gpPermissions = Get-GPPermission -Guid $linkedGPO.GpoId -Domain $env:USERDNSDOMAIN -all | ?{$_.Permission -eq "GpoApply"}
    #Policies may have multiple GpoApply permissions so need to check them all
    foreach($permission in $gpPermissions){
        if(($memberOf -contains $permission.Trustee.Name) -or ($permission.Trustee.Name -eq "Authenticated Users")){
            $hasPermission = 1
        }
    }
    #Security filter passed? Make mapping objects and add to array
    if($hasPermission){
            $gpoObject = New-Object System.DirectoryServices.DirectoryEntry("LDAP://" + (Get-GPO $linkedGPO.GpoId -Domain $env:USERDNSDOMAIN).Path)
            $resultantPath = $gpoObject.gPCFileSysPath
            $workingXML = "$resultantPath\User\Preferences\Drives\Drives.xml"
            if(Test-Path $workingXML){
                [xml]$psXML = Get-Content $workingXML
                foreach ($drive in $psXML.Drives.Drive){
                    $gpoMappings += New-Object PSObject -Property @{
                    DriveLabel = $drive.Properties.label
                    DriveLetter = $drive.Properties.Letter
                    DrivePath = $drive.Properties.Path
                    DriveFilter = $drive.Filters.InnerXML
                    Action = $drive.Properties.Action
                }
            }
        }
    }
}
if(!($gpoMappings)){return "Could not resolve policies to GPO mappings."}

#Process mapping filters and attributes
foreach($gpoMapping in $gpoMappings){
    [xml]$filterXML = $gpoMapping.DriveFilter

    #If drive exists, check the existing path
    #If action is "D" for Delete, it's OK if the drive exists so it can be removed
    #We still want to process the other rules to ensure the deletion is intended for this user
    $existingDrive = Get-PSDrive -Name ($gpoMapping.DriveLetter) -ErrorAction SilentlyContinue
    if(($existingDrive.DisplayRoot -eq $gpoMapping.DrivePath) -and ($gpoMapping.Action -ne "D")){ 
        Write-Output "Path $($gpoMapping.DrivePath) not mapped. Already mapped correctly."
        continue
    }
    #If there is a FilterGroup, check against it
    if($filterXML.FilterGroup.name){
        $groupCheck = [bool]([int]($memberOf -contains ($filterXML.FilterGroup.name -split "\\",2)[1]) - [int]$filterXML.FilterGroup.not)
        if(!($groupCheck)){
            Write-Output "Path $($gpoMapping.DrivePath) not mapped. User not member of FilterGroup."
            continue
        }
    }
    #If there is a FilterOU, check against it
    if($filterXML.FilterOrgUnit.name){
        $ouCheck = [bool]([int]($userOU -match ($filterXML.FilterOrgUnit.name)) - [int]$filterXML.FilterOrgUnit.not)
        if(!($ouCheck)){
            Write-Output "Path $($gpoMapping.DrivePath) not mapped. User not member of Filter OU."
            continue
        }
    }
    #If all checks passed, map the drive
    if((Test-Path $gpoMapping.DrivePath) -and ($gpoMapping.DriveLetter)){
        DriveMappingFunction $gpoMapping
    }
}