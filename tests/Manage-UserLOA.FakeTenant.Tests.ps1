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
. (Join-Path $PSScriptRoot 'Fakes\FakeTenant.ps1')

function Initialize-FakeTenantTest {
    New-LOAFakeTenant
    Register-LOAFakeTenantMocks
    & (Get-Module Manage-UserLOA) { $Script:Config = $global:LOAFake.Config }
}

Describe 'Manage-UserLOA against the fake tenant' {
    It 'fake tenant: Start moves Jane to the LOA OU, disables, hides and delegates' {
        Initialize-FakeTenantTest

        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false

        $state = Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com'
        Assert-Equal -Actual $state.Enabled -Expected $false -Message 'Jane should be disabled.'
        Assert-Equal -Actual $state.HiddenFromGAL -Expected $true -Message 'Jane should be hidden from the GAL.'
        Assert-Equal -Actual $state.ParentOU -Expected 'OU=Users on Temporary Leave,OU=Corporate,DC=yourdomain,DC=com' -Message 'Jane should be in the LOA OU.'
        Assert-Equal -Actual $state.StashedOU -Expected 'OU=Sales,OU=Corporate,DC=yourdomain,DC=com' -Message 'Jane''s original OU should be stashed.'
        Assert-Equal -Actual ($state.FullAccess -join ',') -Expected 'john.smith@yourdomain.com' -Message 'John should have FullAccess.'
        Assert-Equal -Actual ($state.SendAs -join ',') -Expected 'john.smith@yourdomain.com' -Message 'John should have SendAs.'
        Assert-Equal -Actual $state.OOOState -Expected 'Enabled' -Message 'The LOA OOO should be enabled.'
    }

    It 'fake tenant: Start then End returns Jane to her starting state' {
        Initialize-FakeTenantTest
        $before = ConvertTo-LOAComparable (Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com')

        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false
        End-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com' -Confirm:$false

        $after = ConvertTo-LOAComparable (Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com')
        Assert-Equal -Actual $after -Expected $before -Message 'End should undo everything Start changed for Jane.'
    }

    It 'fake tenant: WhatIf leaves state unchanged' {
        Initialize-FakeTenantTest
        $before = ConvertTo-LOAComparable (Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com')

        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -WhatIf

        $after = ConvertTo-LOAComparable (Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com')
        Assert-Equal -Actual $after -Expected $before -Message 'WhatIf should not change any state.'
    }

    It 'fake tenant: Start on Bob leaves his enabled OOO untouched' {
        Initialize-FakeTenantTest

        Start-UserLOA -UserPrincipalName 'bob.lee@yourdomain.com' -Confirm:$false

        $state = Get-LOAFakeUserState -UserPrincipalName 'bob.lee@yourdomain.com'
        Assert-Equal -Actual $state.OOOState -Expected 'Enabled' -Message 'Bob''s OOO should still be enabled.'
        Assert-Equal -Actual $global:LOAFake.Mailboxes['bob.lee@yourdomain.com'].OOO.InternalMessage -Expected 'Personal OOO set by the user' -Message 'Bob''s personal OOO message should be untouched.'
        Assert-MockCalled Invoke-LOASetMailboxAutoReplyConfiguration -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
    }

    It 'fake tenant: scheduled OOO is never overwritten without ForceOOO' {
        Initialize-FakeTenantTest
        $ooo = $global:LOAFake.Mailboxes['jane.doe@yourdomain.com'].OOO
        $ooo.AutoReplyState = 'Scheduled'
        $ooo.StartTime = (Get-Date).AddDays(30)
        $ooo.InternalMessage = 'Personal scheduled OOO'

        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false

        Assert-Equal -Actual $ooo.AutoReplyState -Expected 'Scheduled' -Message 'Scheduled OOO should be left alone without -ForceOOO.'
        Assert-Equal -Actual $ooo.InternalMessage -Expected 'Personal scheduled OOO' -Message 'The scheduled OOO message should be unchanged.'

        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ForceOOO -Confirm:$false

        Assert-Equal -Actual $ooo.AutoReplyState -Expected 'Enabled' -Message '-ForceOOO should replace the scheduled OOO with the LOA message.'
    }
}
