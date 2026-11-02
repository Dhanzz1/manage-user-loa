function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message`nExpected: $Expected`nActual: $Actual"
    }
}

$modulePath = Join-Path $PSScriptRoot '..\src\Manage-UserLOA\Manage-UserLOA.psm1'
Import-Module $modulePath -Force | Out-Null

function Set-WorkflowTestState {
    param(
        [Parameter(Mandatory)]$BeforeSnapshot,
        [Parameter(Mandatory)]$AfterSnapshot
    )

    $global:LOABeforeSnapshot = $BeforeSnapshot
    $global:LOAAfterSnapshot = $AfterSnapshot
    $global:LOASnapshotCallCount = 0
}

function Initialize-CommonWorkflowMocks {
    InModuleScope Manage-UserLOA {
        Mock Import-LOAConfig {
            $Script:Config = @{
                LOAOUDistinguishedName = 'OU=Users on Temporary Leave,OU=Corporate,DC=yourdomain,DC=com'
                DomainController       = 'DC01.yourdomain.com'
                OUStashAttribute       = 'extensionAttribute10'
            }
        }
        Mock Connect-LOAServices {}
        Mock Invoke-LOASessionRevoke {}
        Mock Get-LOAEntraUserId { 'aaaaaaaa-0000-0000-0000-000000000001' }
        Mock Assert-LOAOrganizationalUnit {}
        Mock Show-UserSummary {}
        Mock Show-LOAPreExistingWarnings {}
        Mock Write-Host {}
        Mock Start-Sleep {}
        Mock Invoke-LOAGetUserStateSnapshot {
            $global:LOASnapshotCallCount++
            if ($global:LOASnapshotCallCount -eq 1) {
                return $global:LOABeforeSnapshot
            }

            return $global:LOAAfterSnapshot
        }
    }
}

Describe 'Manage-UserLOA workflow orchestration' {
    It 'runs the Start-UserLOA happy path with delegation and default OOO' {
        Set-WorkflowTestState `
            -BeforeSnapshot ([pscustomobject]@{
                DisplayName = 'Jane Doe'
                OOOState = 'Disabled'
                OOOStartTime = $null
                FullAccessGrants = @()
                SendAsGrants = @()
            }) `
            -AfterSnapshot ([pscustomobject]@{
                DisplayName = 'Jane Doe'
                OOOState = 'Enabled'
                OOOStartTime = $null
                FullAccessGrants = @('john.smith@yourdomain.com')
                SendAsGrants = @('john.smith@yourdomain.com')
            })

        Initialize-CommonWorkflowMocks

        InModuleScope Manage-UserLOA {
            Mock Get-LOAUser {
                [pscustomobject]@{
                    DistinguishedName = 'CN=Jane Doe,OU=Users,DC=yourdomain,DC=com'
                    DisplayName = 'Jane Doe'
                    UserPrincipalName = 'jane.doe@yourdomain.com'
                    Manager = 'CN=John Smith,OU=Users,DC=yourdomain,DC=com'
                    msExchHideFromAddressLists = $false
                    Enabled = $true
                }
            }
            Mock Invoke-LOAGetADUser {
                [pscustomobject]@{
                    DisplayName = 'John Smith'
                    EmailAddress = 'john.smith@yourdomain.com'
                    UserPrincipalName = 'john.smith@yourdomain.com'
                }
            }
            Mock Get-LOAStashedOU { $null }
            Mock Test-LOAFullAccessGrant { $false }
            Mock Test-LOASendAsGrant { $false }
            Mock Invoke-LOASetADUser {}
            Mock Invoke-LOADisableADAccount {}
            Mock Invoke-LOAMoveADObject {}
            Mock Invoke-LOAAddMailboxPermission {}
            Mock Invoke-LOAAddRecipientPermission {}
            Mock Invoke-LOASetMailboxAutoReplyConfiguration {}
        }

        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com' -Confirm:$false

        Assert-MockCalled Invoke-LOASetADUser -ModuleName Manage-UserLOA -Times 2 -Exactly -Scope It
        Assert-MockCalled Invoke-LOADisableADAccount -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-LOAMoveADObject -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-LOAAddMailboxPermission -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-LOAAddRecipientPermission -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-LOASetMailboxAutoReplyConfiguration -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
    }

    It 'skips destructive Start-UserLOA actions when run with WhatIf' {
        $snapshot = [pscustomobject]@{
            DisplayName = 'Jane Doe'
            OOOState = 'Disabled'
            OOOStartTime = $null
            FullAccessGrants = @()
            SendAsGrants = @()
        }

        Set-WorkflowTestState -BeforeSnapshot $snapshot -AfterSnapshot $snapshot
        Initialize-CommonWorkflowMocks

        InModuleScope Manage-UserLOA {
            Mock Get-LOAUser {
                [pscustomobject]@{
                    DistinguishedName = 'CN=Jane Doe,OU=Users,DC=yourdomain,DC=com'
                    DisplayName = 'Jane Doe'
                    UserPrincipalName = 'jane.doe@yourdomain.com'
                    Manager = 'CN=John Smith,OU=Users,DC=yourdomain,DC=com'
                    msExchHideFromAddressLists = $false
                    Enabled = $true
                }
            }
            Mock Invoke-LOAGetADUser {
                [pscustomobject]@{
                    DisplayName = 'John Smith'
                    EmailAddress = 'john.smith@yourdomain.com'
                    UserPrincipalName = 'john.smith@yourdomain.com'
                }
            }
            Mock Get-LOAStashedOU { $null }
            Mock Invoke-LOASetADUser {}
            Mock Invoke-LOADisableADAccount {}
            Mock Invoke-LOAMoveADObject {}
            Mock Invoke-LOAAddMailboxPermission {}
            Mock Invoke-LOAAddRecipientPermission {}
            Mock Invoke-LOASetMailboxAutoReplyConfiguration {}
        }

        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com' -WhatIf

        Assert-MockCalled Invoke-LOASetADUser -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-LOADisableADAccount -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-LOAMoveADObject -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-LOAAddMailboxPermission -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-LOAAddRecipientPermission -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-LOASetMailboxAutoReplyConfiguration -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
    }

    It 'runs the End-UserLOA happy path and removes delegation' {
        Set-WorkflowTestState `
            -BeforeSnapshot ([pscustomobject]@{
                DisplayName = 'Jane Doe'
                OOOState = 'Enabled'
                OOOStartTime = $null
                FullAccessGrants = @('john.smith@yourdomain.com')
                SendAsGrants = @('john.smith@yourdomain.com')
            }) `
            -AfterSnapshot ([pscustomobject]@{
                DisplayName = 'Jane Doe'
                OOOState = 'Disabled'
                OOOStartTime = $null
                FullAccessGrants = @()
                SendAsGrants = @()
            })

        Initialize-CommonWorkflowMocks

        InModuleScope Manage-UserLOA {
            Mock Get-LOAUser {
                [pscustomobject]@{
                    DistinguishedName = 'CN=Jane Doe,OU=Users on Temporary Leave,OU=Corporate,DC=yourdomain,DC=com'
                    DisplayName = 'Jane Doe'
                    UserPrincipalName = 'jane.doe@yourdomain.com'
                    msExchHideFromAddressLists = $true
                    Enabled = $false
                }
            }
            Mock Get-LOAStashedOU { 'OU=Users,DC=yourdomain,DC=com' }
            Mock Get-LOAFullAccessGrantIdentities { @('john.smith@yourdomain.com') }
            Mock Get-LOASendAsGrantIdentities { @('john.smith@yourdomain.com') }
            Mock Invoke-LOAEnableADAccount {}
            Mock Invoke-LOASetADUser {}
            Mock Invoke-LOAMoveADObject {}
            Mock Invoke-LOARemoveMailboxPermission {}
            Mock Invoke-LOARemoveRecipientPermission {}
            Mock Invoke-LOASetMailboxAutoReplyConfiguration {}
        }

        End-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com' -Confirm:$false

        Assert-MockCalled Invoke-LOAEnableADAccount -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-LOASetADUser -ModuleName Manage-UserLOA -Times 2 -Exactly -Scope It
        Assert-MockCalled Invoke-LOAMoveADObject -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-LOARemoveMailboxPermission -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-LOARemoveRecipientPermission -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-LOASetMailboxAutoReplyConfiguration -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
    }

    It 'throws when End-UserLOA has no TargetOU and no stashed OU' {
        $snapshot = [pscustomobject]@{
            DisplayName = 'Jane Doe'
            OOOState = 'Enabled'
            OOOStartTime = $null
            FullAccessGrants = @()
            SendAsGrants = @()
        }

        Set-WorkflowTestState -BeforeSnapshot $snapshot -AfterSnapshot $snapshot
        Initialize-CommonWorkflowMocks

        InModuleScope Manage-UserLOA {
            Mock Get-LOAUser {
                [pscustomobject]@{
                    DistinguishedName = 'CN=Jane Doe,OU=Users on Temporary Leave,OU=Corporate,DC=yourdomain,DC=com'
                    DisplayName = 'Jane Doe'
                    UserPrincipalName = 'jane.doe@yourdomain.com'
                    msExchHideFromAddressLists = $true
                    Enabled = $false
                }
            }
            Mock Get-LOAStashedOU { $null }
            Mock Invoke-LOAEnableADAccount {}
            Mock Invoke-LOAMoveADObject {}
        }

        $threw = $false
        try {
            End-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com'
        } catch {
            $threw = $true
        }

        Assert-Equal -Actual $threw -Expected $true -Message 'End-UserLOA should throw when neither TargetOU nor stashed OU is available.'
        Assert-MockCalled Invoke-LOAEnableADAccount -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-LOAMoveADObject -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
    }
}
