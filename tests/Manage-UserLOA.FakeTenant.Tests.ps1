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

    It 'fake tenant: Start blocks, disables and revokes Jane in that order' {
        Initialize-FakeTenantTest

        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false

        $order = @($global:LOAFake.Calls | Where-Object { $_ -in @('AddGroupMember', 'DisableADAccount', 'RevokeSignInSession') }) -join ','
        Assert-Equal -Actual $order -Expected 'AddGroupMember,DisableADAccount,RevokeSignInSession' -Message 'Sign-in should be blocked before the AD disable, and sessions revoked after it.'
        Assert-Equal -Actual $global:LOAFake.Entra.Revoked['jane.doe@yourdomain.com'] -Expected 1 -Message 'Jane''s sessions should be revoked once.'
        Assert-Equal -Actual (Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com').BlockGroupMember -Expected $true -Message 'Jane should be in the sign-in block group.'
    }

    It 'fake tenant: End removes Jane from the block group and the round trip holds' {
        Initialize-FakeTenantTest
        $before = ConvertTo-LOAComparable (Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com')

        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false
        End-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com' -Confirm:$false

        $after = Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com'
        Assert-Equal -Actual $after.BlockGroupMember -Expected $false -Message 'End should remove Jane from the block group.'
        Assert-Equal -Actual (ConvertTo-LOAComparable $after) -Expected $before -Message 'End should undo everything Start changed for Jane.'
    }

    It 'fake tenant: revoke failure stops Start with Jane disabled, not moved, not delegated' {
        Initialize-FakeTenantTest
        $global:LOAFake.Entra.RevokeResult = $false

        $message = $null
        try { Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false } catch { $message = $_.Exception.Message }

        $state = Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com'
        Assert-Equal -Actual ($message -like 'Session revoke failed*') -Expected $true -Message "Start should throw the revoke error. Got: $message"
        Assert-Equal -Actual $state.Enabled -Expected $false -Message 'Jane should already be disabled.'
        Assert-Equal -Actual $state.ParentOU -Expected 'OU=Sales,OU=Corporate,DC=yourdomain,DC=com' -Message 'Jane should not have been moved.'
        Assert-Equal -Actual @($state.FullAccess).Count -Expected 0 -Message 'No delegation should have been granted.'
    }

    It 'fake tenant: rerun after revoke failure completes and does not re-add the block group' {
        Initialize-FakeTenantTest
        $global:LOAFake.Entra.RevokeResult = $false
        try { Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false } catch { }

        $global:LOAFake.Entra.RevokeResult = [pscustomobject]@{ Value = $true }
        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false

        $state = Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com'
        Assert-Equal -Actual $state.ParentOU -Expected 'OU=Users on Temporary Leave,OU=Corporate,DC=yourdomain,DC=com' -Message 'The rerun should finish the move.'
        Assert-Equal -Actual $state.StashedOU -Expected 'OU=Sales,OU=Corporate,DC=yourdomain,DC=com' -Message 'The original stash should survive the rerun.'
        Assert-MockCalled Invoke-LOAAddGroupMember -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-LOASetADUser -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It -ParameterFilter { $Replace -and $Replace.ContainsKey('extensionAttribute10') }
    }

    It 'fake tenant: block-group failure stops Start before the AD disable' {
        Initialize-FakeTenantTest
        $global:LOAFake.Faults['AddGroupMember'] = { throw 'Insufficient privileges to complete the operation.' }

        $message = $null
        try { Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false } catch { $message = $_.Exception.Message }

        $state = Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com'
        Assert-Equal -Actual ($message -like 'Sign-in block group add failed*') -Expected $true -Message "Start should throw the block-group error. Got: $message"
        Assert-Equal -Actual $state.Enabled -Expected $true -Message 'Jane should still be enabled.'
        Assert-Equal -Actual $state.ParentOU -Expected 'OU=Sales,OU=Corporate,DC=yourdomain,DC=com' -Message 'Jane should not have been moved.'
        Assert-Equal -Actual @($state.FullAccess).Count -Expected 0 -Message 'No delegation should have been granted.'
    }

    It 'fake tenant: Entra user missing stops Start before any change' {
        Initialize-FakeTenantTest
        $global:LOAFake.Entra.Users.Remove('jane.doe@yourdomain.com')

        $message = $null
        try { Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false } catch { $message = $_.Exception.Message }

        $state = Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com'
        Assert-Equal -Actual ($message -like 'Microsoft Graph pre-check failed*') -Expected $true -Message "Start should throw before changing anything. Got: $message"
        Assert-Equal -Actual $state.Enabled -Expected $true -Message 'Jane should still be enabled.'
        Assert-Equal -Actual $state.StashedOU -Expected $null -Message 'No OU stash should be written.'
    }

    It 'fake tenant: Entra user missing without a block group stops Start before any change' {
        Initialize-FakeTenantTest
        $global:LOAFake.Config.SignInBlockGroupId = ''
        $global:LOAFake.Entra.Users.Remove('jane.doe@yourdomain.com')

        $message = $null
        try { Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false } catch { $message = $_.Exception.Message }

        $state = Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com'
        Assert-Equal -Actual ($message -like 'Microsoft Graph pre-check failed*') -Expected $true -Message "Start should throw before changing anything. Got: $message"
        Assert-Equal -Actual $state.Enabled -Expected $true -Message 'Jane should not be disabled when revoke could never succeed.'
        Assert-Equal -Actual $state.StashedOU -Expected $null -Message 'No OU stash should be written.'
    }

    It 'fake tenant: unreadable block group stops Start before any change' {
        Initialize-FakeTenantTest
        $global:LOAFake.Faults['GetGroupMember'] = { throw "Invalid object identifier 'LOA-SignInBlocked'." }

        $message = $null
        try { Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false } catch { $message = $_.Exception.Message }

        Assert-Equal -Actual ($message -like 'Microsoft Graph pre-check failed*') -Expected $true -Message "Start should throw before changing anything. Got: $message"
        Assert-Equal -Actual (Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com').StashedOU -Expected $null -Message 'No OU stash should be written.'
    }

    It 'fake tenant: a thrown revoke error stops Start like a false result' {
        Initialize-FakeTenantTest
        $global:LOAFake.Config.SignInBlockGroupId = ''
        $global:LOAFake.Faults['RevokeSignInSession'] = { throw 'Insufficient privileges to complete the operation.' }

        $message = $null
        try { Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false } catch { $message = $_.Exception.Message }

        Assert-Equal -Actual ($message -like 'Session revoke failed*Insufficient privileges*') -Expected $true -Message "Start should throw the revoke error. Got: $message"
        Assert-Equal -Actual (Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com').ParentOU -Expected 'OU=Sales,OU=Corporate,DC=yourdomain,DC=com' -Message 'Jane should not have been moved.'
    }

    It 'fake tenant: WhatIf with a block group makes no Graph or AD writes' {
        Initialize-FakeTenantTest
        $before = ConvertTo-LOAComparable (Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com')

        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -WhatIf

        Assert-Equal -Actual (ConvertTo-LOAComparable (Get-LOAFakeUserState -UserPrincipalName 'jane.doe@yourdomain.com')) -Expected $before -Message 'WhatIf should not change any state.'
        Assert-MockCalled Invoke-LOAAddGroupMember -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-LOARemoveGroupMember -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-LOARevokeSignInSession -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
    }

    It 'fake tenant: without a block group Start warns about sync delay' {
        Initialize-FakeTenantTest
        $global:LOAFake.Config.SignInBlockGroupId = ''

        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false

        Assert-Equal -Actual $global:LOAFake.Entra.Revoked['jane.doe@yourdomain.com'] -Expected 1 -Message 'Sessions should still be revoked without a block group.'
        Assert-MockCalled Write-Host -ModuleName Manage-UserLOA -Scope It -ParameterFilter { "$Object" -like '*No SignInBlockGroupId configured*' }
    }

    It 'fake tenant: block-group removal failure on End is reported, not thrown' {
        Initialize-FakeTenantTest
        Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -Confirm:$false
        $global:LOAFake.Faults['RemoveGroupMember'] = { throw 'Request throttled.' }

        End-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com' -Confirm:$false

        Assert-Equal -Actual $global:LOAFake.ADUsers['jane.doe@yourdomain.com'].Enabled -Expected $true -Message 'End should still re-enable Jane.'
        Assert-MockCalled Write-Host -ModuleName Manage-UserLOA -Scope It -ParameterFilter { "$Object" -like '*Sign-in block group removal failed*Remove jane.doe@yourdomain.com from the group manually*' }
    }
}
