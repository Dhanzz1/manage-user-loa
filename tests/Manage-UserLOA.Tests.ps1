function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [string]$Message
    )

    if ($Actual -is [array] -or $Expected -is [array]) {
        $actualJson = ConvertTo-Json $Actual -Compress
        $expectedJson = ConvertTo-Json $Expected -Compress
        if ($actualJson -ne $expectedJson) {
            throw "$Message`nExpected: $expectedJson`nActual: $actualJson"
        }
        return
    }

    if ($Actual -ne $Expected) {
        throw "$Message`nExpected: $Expected`nActual: $Actual"
    }
}

Describe 'Manage-UserLOA public module' {
    $modulePath = Join-Path $PSScriptRoot '..\src\Manage-UserLOA\Manage-UserLOA.psm1'
    $module = Import-Module $modulePath -Force -PassThru

    It 'manifest version is 1.1.0' {
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\src\Manage-UserLOA\Manage-UserLOA.psd1')
        Assert-Equal -Actual $manifest.ModuleVersion -Expected '1.1.0' -Message 'The manifest should declare v1.1.0.'
    }

    It 'uses high confirmation impact for Start-UserLOA' {
        $actual = ([System.Management.Automation.CommandMetadata](Get-Command Start-UserLOA)).ConfirmImpact
        Assert-Equal -Actual $actual -Expected 'High' -Message 'Start-UserLOA should use high confirmation impact.'
    }

    It 'uses high confirmation impact for End-UserLOA' {
        $actual = ([System.Management.Automation.CommandMetadata](Get-Command End-UserLOA)).ConfirmImpact
        Assert-Equal -Actual $actual -Expected 'High' -Message 'End-UserLOA should use high confirmation impact.'
    }

    It 'rejects an invalid Start-UserLOA user principal name before execution' {
        $actualMessage = $null
        try {
            Start-UserLOA -UserPrincipalName 'not-a-upn' -ManagerUPN 'john.smith@yourdomain.com' -WhatIf
        } catch {
            $actualMessage = $_.Exception.Message
        }

        Assert-Equal -Actual ($actualMessage -like '*Cannot validate argument*UserPrincipalName*') -Expected $true -Message 'Start-UserLOA should reject malformed user principal names at parameter binding time.'
    }

    It 'rejects an invalid End-UserLOA manager principal name before execution' {
        $actualMessage = $null
        try {
            End-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'not-a-upn' -WhatIf
        } catch {
            $actualMessage = $_.Exception.Message
        }

        Assert-Equal -Actual ($actualMessage -like '*Cannot validate argument*ManagerUPN*') -Expected $true -Message 'End-UserLOA should reject malformed manager principal names at parameter binding time.'
    }

    It 'extracts the parent OU from a standard DN' {
        $actual = & $module { Get-ParentOU 'CN=Jane Doe,OU=Users,DC=yourdomain,DC=com' }
        Assert-Equal -Actual $actual -Expected 'OU=Users,DC=yourdomain,DC=com' -Message 'Parent OU extraction should strip the CN from a standard DN.'
    }

    It 'handles escaped commas in the common name' {
        $actual = & $module { Get-ParentOU 'CN=Doe\, Jane,OU=Users,DC=yourdomain,DC=com' }
        Assert-Equal -Actual $actual -Expected 'OU=Users,DC=yourdomain,DC=com' -Message 'Parent OU extraction should handle escaped commas.'
    }

    It 'formats null as none' {
        $actual = & $module { Format-LOASummaryValue $null }
        Assert-Equal -Actual $actual -Expected '(none)' -Message 'Null summary values should render as (none).'
    }

    It 'formats blank text as none' {
        $actual = & $module { Format-LOASummaryValue '   ' }
        Assert-Equal -Actual $actual -Expected '(none)' -Message 'Blank summary values should render as (none).'
    }

    It 'passes through populated text' {
        $actual = & $module { Format-LOASummaryValue 'OU=Users,DC=yourdomain,DC=com' }
        Assert-Equal -Actual $actual -Expected 'OU=Users,DC=yourdomain,DC=com' -Message 'Populated summary values should pass through unchanged.'
    }

    It 'matches exact UPN identities' {
        $actual = & $module { Test-LOADelegateIdentityMatch -Identity 'john.smith@yourdomain.com' -DelegateUPN 'john.smith@yourdomain.com' }
        Assert-Equal -Actual $actual -Expected $true -Message 'Exact UPN matches should be recognized.'
    }

    It 'matches alias-only identities' {
        $actual = & $module { Test-LOADelegateIdentityMatch -Identity 'john.smith' -DelegateUPN 'john.smith@yourdomain.com' }
        Assert-Equal -Actual $actual -Expected $true -Message 'Alias-only delegate identities should be recognized.'
    }

    It 'matches domain alias identities' {
        $actual = & $module { Test-LOADelegateIdentityMatch -Identity 'YOURDOMAIN\john.smith' -DelegateUPN 'john.smith@yourdomain.com' }
        Assert-Equal -Actual $actual -Expected $true -Message 'DOMAIN\\alias identities should be recognized.'
    }

    It 'does not match unrelated identities' {
        $actual = & $module { Test-LOADelegateIdentityMatch -Identity 'jane.doe' -DelegateUPN 'john.smith@yourdomain.com' }
        Assert-Equal -Actual $actual -Expected $false -Message 'Unrelated identities should not match.'
    }

    It 'sets OOO when the mailbox state is Disabled' {
        $snapshot = [pscustomobject]@{
            OOOState     = 'Disabled'
            OOOStartTime = $null
        }

        $actual = & $module { param($s) Resolve-OOOAction -Snapshot $s } $snapshot
        Assert-Equal -Actual $actual -Expected 'Set' -Message 'Disabled OOO should resolve to Set.'
    }

    It 'returns manual review when OOO is already enabled' {
        $snapshot = [pscustomobject]@{
            OOOState     = 'Enabled'
            OOOStartTime = $null
        }

        $actual = & $module { param($s) Resolve-OOOAction -Snapshot $s } $snapshot
        Assert-Equal -Actual $actual -Expected 'ManualReview' -Message 'Enabled OOO should resolve to ManualReview.'
    }

    It 'returns manual review for scheduled OOO far in the future' {
        $snapshot = [pscustomobject]@{
            OOOState     = 'Scheduled'
            OOOStartTime = (Get-Date).AddDays(30)
        }

        $actual = & $module { param($s) Resolve-OOOAction -Snapshot $s } $snapshot
        Assert-Equal -Actual $actual -Expected 'ManualReview' -Message 'Scheduled OOO should resolve to ManualReview however far away it starts.'
    }

    It 'returns manual review for scheduled OOO with no start time' {
        $snapshot = [pscustomobject]@{
            OOOState     = 'Scheduled'
            OOOStartTime = $null
        }

        $actual = & $module { param($s) Resolve-OOOAction -Snapshot $s } $snapshot
        Assert-Equal -Actual $actual -Expected 'ManualReview' -Message 'Scheduled OOO without a start time should resolve to ManualReview.'
    }

    It 'forces OOO when ForceOOO is supplied' {
        $snapshot = [pscustomobject]@{
            OOOState     = 'Enabled'
            OOOStartTime = $null
        }

        $actual = & $module { param($s) Resolve-OOOAction -Snapshot $s -ForceOOO } $snapshot
        Assert-Equal -Actual $actual -Expected 'Set' -Message 'ForceOOO should override the default OOO action.'
    }

    It 'describes enabled OOO clearly for manual review' {
        $snapshot = [pscustomobject]@{
            OOOState     = 'Enabled'
            OOOStartTime = $null
        }

        $actual = & $module { param($s) Get-OOOManualReviewContext -Snapshot $s } $snapshot
        Assert-Equal -Actual $actual -Expected 'OOO is already enabled' -Message 'Enabled OOO should describe the manual-review reason.'
    }

    It 'describes scheduled OOO without a threshold' {
        $start = [datetime]'2026-12-01 09:00'
        $snapshot = [pscustomobject]@{
            OOOState     = 'Scheduled'
            OOOStartTime = $start
        }

        $actual = & $module { param($s) Get-OOOManualReviewContext -Snapshot $s } $snapshot
        Assert-Equal -Actual $actual -Expected "OOO is scheduled to start at $start" -Message 'Scheduled OOO should describe its start time without threshold text.'
    }

    It 'no longer ships the Google Workspace or Generic REST connectors' {
        $removed = @('Join-LOAApiUrl', 'Invoke-LOAGoogleWorkspaceSuspension', 'Invoke-LOAGenericSaaSAction', 'Invoke-LOASaaSDeactivation', 'Invoke-LOASaaSReactivation')
        foreach ($name in $removed) {
            $command = & $module { param($n) Get-Command $n -ErrorAction SilentlyContinue } $name
            Assert-Equal -Actual ($null -eq $command) -Expected $true -Message "$name should no longer exist in the module."
        }
    }

    It 'polls for a converged post-change snapshot instead of relying on a fixed delay' {
        InModuleScope Manage-UserLOA {
            $script:pollCount = 0
            Mock Invoke-LOAGetUserStateSnapshot {
                $script:pollCount++
                if ($script:pollCount -eq 1) {
                    return [pscustomobject]@{
                        FullAccessGrants = @()
                    }
                }

                return [pscustomobject]@{
                    FullAccessGrants = @('john.smith@yourdomain.com')
                }
            }
            Mock Start-Sleep {}

            $result = Wait-LOAUserStateSnapshot `
                -UserPrincipalName 'jane.doe@yourdomain.com' `
                -IsSatisfied { param($snapshot) @($snapshot.FullAccessGrants) -contains 'john.smith@yourdomain.com' } `
                -MaxAttempts 3 `
                -DelaySeconds 2

            if (@($result.FullAccessGrants)[0] -ne 'john.smith@yourdomain.com') {
                throw 'The retry helper should return the first converged snapshot.'
            }
            Assert-MockCalled Invoke-LOAGetUserStateSnapshot -ModuleName Manage-UserLOA -Times 2 -Exactly -Scope It
            Assert-MockCalled Start-Sleep -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
        }
    }

    It 'returns the latest snapshot and warns when convergence does not happen in time' {
        InModuleScope Manage-UserLOA {
            Mock Invoke-LOAGetUserStateSnapshot {
                [pscustomobject]@{
                    FullAccessGrants = @()
                }
            }
            Mock Start-Sleep {}
            Mock Write-Host {}

            $result = Wait-LOAUserStateSnapshot `
                -UserPrincipalName 'jane.doe@yourdomain.com' `
                -IsSatisfied { param($snapshot) @($snapshot.FullAccessGrants) -contains 'john.smith@yourdomain.com' } `
                -MaxAttempts 3 `
                -DelaySeconds 2 `
                -WarningMessage 'Mailbox state did not converge before the summary snapshot.'

            if (@($result.FullAccessGrants).Count -ne 0) {
                throw 'The retry helper should return the latest snapshot when convergence times out.'
            }
            Assert-MockCalled Invoke-LOAGetUserStateSnapshot -ModuleName Manage-UserLOA -Times 3 -Exactly -Scope It
            Assert-MockCalled Start-Sleep -ModuleName Manage-UserLOA -Times 2 -Exactly -Scope It
            Assert-MockCalled Write-Host -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
        }
    }
}
