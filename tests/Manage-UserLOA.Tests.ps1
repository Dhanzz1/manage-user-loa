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

    It 'uses high confirmation impact for Start-UserLOA' {
        $actual = ([System.Management.Automation.CommandMetadata](Get-Command Start-UserLOA)).ConfirmImpact
        Assert-Equal -Actual $actual -Expected 'High' -Message 'Start-UserLOA should use high confirmation impact.'
    }

    It 'uses high confirmation impact for End-UserLOA' {
        $actual = ([System.Management.Automation.CommandMetadata](Get-Command End-UserLOA)).ConfirmImpact
        Assert-Equal -Actual $actual -Expected 'High' -Message 'End-UserLOA should use high confirmation impact.'
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

    It 'returns manual review for scheduled OOO inside the threshold' {
        $snapshot = [pscustomobject]@{
            OOOState     = 'Scheduled'
            OOOStartTime = (Get-Date).AddHours(4)
        }

        $actual = & $module { param($s) Resolve-OOOAction -Snapshot $s } $snapshot
        Assert-Equal -Actual $actual -Expected 'ManualReview' -Message 'Scheduled OOO inside the threshold should resolve to ManualReview.'
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

    It 'joins a base URL and relative endpoint cleanly' {
        $actual = & $module { Join-LOAApiUrl -BaseUrl 'https://yourdomain.com/' -Endpoint '/api/users' }
        Assert-Equal -Actual $actual -Expected 'https://yourdomain.com/api/users' -Message 'Relative API endpoints should join cleanly.'
    }

    It 'preserves absolute endpoints as-is' {
        $actual = & $module { Join-LOAApiUrl -BaseUrl 'https://yourdomain.com' -Endpoint 'https://api.example.com/users' }
        Assert-Equal -Actual $actual -Expected 'https://api.example.com/users' -Message 'Absolute endpoints should be preserved as-is.'
    }
}
