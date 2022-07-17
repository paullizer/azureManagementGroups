<#PSScriptInfo

.VERSION 
    1.5

.GUID 
    931b571e-53d7-49c6-a316-0da3d930c4c0

.AUTHOR 
    Paul Lizer, paullizer@microsoft.com

.COMPANYNAME 
    Microsoft

.COPYRIGHT 
    Creative Commons Attribution 4.0 International Public License

.TAGS

.LICENSEURI 
    TBD

.PROJECTURI 
    TBD

.ICONURI

.EXTERNALMODULEDEPENDENCIES 
    NONE

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES 
    TBD

.LINK  
    TBD

.LINK  
    TBD
    
.EXAMPLE  
    TBD 

        Deploy-ManagementGroups.ps1

.PRIVATEDATA

#>

<# 

.DESCRIPTION 
 TBD. 

#> 

<#***************************************************
                       Process
-----------------------------------------------------
    
TBD

***************************************************#>
    

<#***************************************************
                       Terminology
-----------------------------------------------------
N\A
***************************************************#>


<#***************************************************
                       Variables
***************************************************#>

Param(

    [Parameter(Mandatory=$true)]
    [string]$csvFilePath,
    [Parameter(Mandatory=$false)]
    [string]$tenantId,
    [Parameter(Mandatory=$false)]
    [switch]$moveSubscriptions

    )

$ErrorActionPreference = 'SilentlyContinue'
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true
Set-Item -Path Env:\SuppressAzureRmModulesRetiringWarning  -Value $true
Clear-Host

$csvManagementGroupStructure = Import-Csv $csvFilePath | Select-Object *,"Environment_Id"


<#***************************************************count-1
                       Functions
***************************************************#>



<#***************************************************
                       Execution
***************************************************#>

$uniqueCsvRootMg = $csvManagementGroupStructure.ROOT | Select-Object -unique
$uniqueCsvModeMgs = $csvManagementGroupStructure.Mode | Select-Object -unique

switch ( $uniqueCsvRootMg.count )
{
    {$PSItem -lt 1}
        {
            # NEED A ROOT
            Exit
        }
    {$PSItem -gt 1}
        {
            # TOO MANY ROOTS, CAN ONLY HAVE ONE
            Exit
        }
    Default 
        { 
            # Just Right
        }
}


switch ( $uniqueCsvModeMgs.count )
{
    {$PSItem -lt 1}
        {
            # NEED AT LEAST ONE MODE
            Exit
        }
    Default 
        { 
            # Just Right
        }
}


if ($tenantId){
    try {
        $tenant = Get-AzTenant -TenantId $tenantId
    }
    catch {

    }
} else {
    try {
        $connectionAz = Connect-AzAccount -WarningAction Ignore
        $tenant = Get-AzTenant
    }
    catch {
    
    }
}



if ($tenant.count -gt 1){
    $boolFoundTenant = $false
    Write-host "`nYou have more than one tenant associated with your account."
    foreach ($ten in $tenant){
        Write-host ("`t" + $ten.Name + ": " + $ten.Id)
    }

    while(!$boolFoundTenant){
        $tenantId = Read-host "`nPlease enter the Tenant Id for the appropriate tenant"
        try {
            $tenant = Get-AzTenant -TenantId $tenantId
        }
        catch {

        }
        if ($tenant) {
            Write-Host "`nYou've selected:"
            foreach ($ten in $tenant){
                Write-host ("`t" + $ten.Name + ": " + $ten.Id)
                $boolFoundTenant = $true
            }
        } else {
            Write-host "`nYou failed to enter a correct Tenant Id, please be careful when performing your copy and paste."
        }
    }
}

try {
    Write-host ("`nRequesting Az Account Connection to Tenant: " + $tenant.Id)
    $connectionAz = Connect-AzAccount -Tenant $tenant.Id -WarningAction Ignore
    #$subs =  Get-AzSubscription -TenantId $tenant.Id
    #$context = Set-AzContext -Tenant $tenant.Id -Subscription $subs[0].name
    Write-Host ("`tSuccessfully connected to " + $connectionAz.Context.Tenant.Id)
}
catch {

}

try {
        $azureManagementGroupStructure = Get-AzManagementGroup  -Expand -Recurse $tenant.Id
}
catch {
    
}

# Root Work
Write-Host "`nEvaluating Root Existence"
if ($uniqueCsvRootMg -ne $azureManagementGroupStructure.Children.DisplayName){

    # Create Root Management Group
    Write-Host "`tRoot $uniqueCsvRootMg does not exist."
    Write-Host "`t`tAttempting to create."
    try {
        $rootMg = New-AzManagementGroup -GroupName ((New-Guid).Guid) -DisplayName $uniqueCsvRootMg
    }
    catch {
        
    }
    Write-Host "`t`tSuccessfully Created."
} else {

    $rootMg = $azureManagementGroupStructure.children
    Write-Host "`tRoot $uniqueCsvRootMg exists."
}

# Mode Work
Write-Host "`nEvaluating Mode Existence"

foreach ($uniqueCsvModeMg in $uniqueCsvModeMgs){

    $boolCreateModeMg = $true
    Write-Host "`tEvaluating if Mode $uniqueCsvModeMg exists."

    foreach ($azureMg in $azureManagementGroupStructure.Children.Children){
        if ($uniqueCsvModeMg -eq $azureMg.DisplayName){

            Write-Host "`t`tMode $uniqueCsvModeMg exists."
            $boolCreateModeMg = $false

            # eval environments
            Write-Host "`t`tEvaluating Environment Existence"

            for ($row = 0; $row -lt $csvManagementGroupStructure.count; $row++){
                if ($csvManagementGroupStructure[$row].Mode -eq $uniqueCsvModeMg){

                    Write-Host ("`t`t`tEvaluating if Environment " + $csvManagementGroupStructure[$row].Environment + " exists.")
                    try {
                        $azureModeMgStructure = Get-AzManagementGroup -GroupName $azureMg.Name -Expand
                    }
                    catch {
                        
                    }
                    $boolCreateEnvironMg = $true
                    
                    foreach ($child in $azureModeMgStructure.Children){
                        if ($csvManagementGroupStructure[$row].Environment -eq $child.DisplayName){

                            $boolCreateEnvironMg = $false
                            Write-Host ("`t`t`t`tEnvironment " + $csvManagementGroupStructure[$row].Environment + " exists.")
                            [string]$id = ($child.Id).toString()
                            $csvManagementGroupStructure[$row].Environment_Id = $id 
                        }
                    }

                    if ($boolCreateEnvironMg){

                        Write-Host ("`t`t`t`tEnvironment " + $csvManagementGroupStructure[$row].Environment + " does not exist.")
                        Write-Host "`t`t`t`tAttempting to create."
                        [string]$environmentName = ($csvManagementGroupStructure[$row].Environment).toString()
                        [string]$guid = ((New-Guid).Guid).toString()
                        [string]$parentId = ($azureMg.Id).toString()
                        try {
                            $newEnvironMg = New-AzManagementGroup -GroupName $guid -DisplayName $environmentName -ParentId $parentId
                        }
                        catch {

                        }
                        Write-Host "`t`t`t`tSuccessfully Created."
                        [string]$id = $newEnvironmentMg.Id
                        $csvManagementGroupStructure[$row].Environment_Id = $id 
                    }
                }
            }
        }
    }

    if ($boolCreateModeMg){

        Write-Host "`t`tMode $uniqueCsvModeMg does not exist."
        try {
            Write-Host "`t`tAttempting to create."
            $newModeMg = New-AzManagementGroup -GroupName ((New-Guid).Guid) -DisplayName $uniqueCsvModeMg -ParentId $rootMg.Id
            Write-Host "`t`tSuccessfully Created."
        }
        catch {
            
        }
        
        for ($row = 0; $row -lt $csvManagementGroupStructure.count; $row++){
            if ($csvManagementGroupStructure[$row].Mode -eq $uniqueCsvModeMg){
            
                Write-Host ("`t`t`tCreating Environment " + $csvManagementGroupStructure[$row].Environment + ".")
                [string]$environmentName = ($csvManagementGroupStructure[$row].Environment).toString()
                [string]$guid = ((New-Guid).Guid).toString()
                [string]$parentId = ($newModeMg.Id).toString()
                try {
                    $newEnvironMg = New-AzManagementGroup -GroupName $guid -DisplayName $environmentName -ParentId $parentId
                }
                catch {

                }
                [string]$id = $newEnvironmentMg.Id
                $csvManagementGroupStructure[$row].Environment_Id = $id 
            }
        }
    }
}

# Subscription Work
if ($moveSubscriptions){

    $subMoveCount = 0

    foreach($row in $csvManagementGroupStructure){
        if (![string]::IsNullOrWhiteSpace($row.subscription)){
            $subMoveCount++
        }
    }
    Write-Host "`n**Subscription Move was selected.**"
    Write-Host "`nEvaluating $subMoveCount subscriptions to move."

    for ($row = 0; $row -lt $csvManagementGroupStructure.count; $row++){
        if ($csvManagementGroupStructure[$row].Subscription){
            try {
                [string]$subName = ($csvManagementGroupStructure[$row].Subscription).toString()
                [string]$modeName = ($csvManagementGroupStructure[$row].Mode).toString()
                [string]$environName = ($csvManagementGroupStructure[$row].Environment).toString()
                $sub = Get-AzSubscription -SubscriptionName $subName
            }
            catch {
                
            }

            try {
                Write-Host "`tAttempting to move subscription $subName to $modeName/$environName."
                [string]$groupID = (($csvManagementGroupStructure[$row].Environment_Id).split("/")[4]).toString()
                [string]$subId = ($sub.Id).ToString()
                $newMgMembership = New-AzManagementGroupSubscription -GroupId $groupID -SubscriptionId $subId
                Write-Host "`t`tSuccessfully Moved."
            }
            catch {
                
            }
        }
    }
}