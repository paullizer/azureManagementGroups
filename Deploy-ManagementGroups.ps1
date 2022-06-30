<#PSScriptInfo

.VERSION 
    1.0

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
    [switch]$moveSubscriptions

    )

$ErrorActionPreference = 'SilentlyContinue'
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true
Set-Item -Path Env:\SuppressAzureRmModulesRetiringWarning  -Value $true

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

#Connect-AzAccount

try {
    $tenant = Get-AzTenant
}
catch {

}

try {
    $azureManagementGroupStructure = Get-AzManagementGroup  -Expand -Recurse $tenant.Id
}
catch {
    
}

# Root Work
Write-Host "Evaluating Root Existence"
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
Write-Host "Evaluating Mode Existence"

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
    Write-Host "Subscription Move was selected."
    Write-Host "Evaluating $subMoveCount subscriptions to move."

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