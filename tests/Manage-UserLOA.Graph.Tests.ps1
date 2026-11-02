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
$module = Import-Module $modulePath -Force -PassThru

Describe 'Manage-UserLOA Graph connection and revoke helpers' {
    It 'requests the block-group scope only when SignInBlockGroupId is set' {
        $without = & $module { $Script:Config = @{ SignInBlockGroupId = '' }; Get-LOAGraphScopes }
        $with = & $module { $Script:Config = @{ SignInBlockGroupId = '11111111-1111-1111-1111-111111111111' }; Get-LOAGraphScopes }

        Assert-Equal -Actual (@($without) -join ',') -Expected 'User.Read.All,User.RevokeSessions.All' -Message 'Without a block group only the read and revoke scopes are needed.'
        Assert-Equal -Actual (@($with) -join ',') -Expected 'User.Read.All,User.RevokeSessions.All,GroupMember.ReadWrite.All' -Message 'A block group adds GroupMember.ReadWrite.All.'
    }

    It 'reuses a Graph context that already has every scope, ignoring case' {
        InModuleScope Manage-UserLOA {
            Mock Invoke-LOAGetMgContext { [pscustomobject]@{ Account = 'operator@yourdomain.com'; Scopes = @('user.read.all', 'user.revokesessions.all', 'openid') } }
            Mock Invoke-LOAConnectGraph {}
        }

        & $module { Connect-LOAGraph -RequiredScopes @('User.Read.All', 'User.RevokeSessions.All') }

        Assert-MockCalled Invoke-LOAConnectGraph -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
    }

    It 'reconnects when a scope is missing' {
        InModuleScope Manage-UserLOA {
            Mock Invoke-LOAGetMgContext { [pscustomobject]@{ Account = 'operator@yourdomain.com'; Scopes = @('User.Read.All') } }
            Mock Invoke-LOAConnectGraph {}
        }

        & $module { Connect-LOAGraph -RequiredScopes @('User.Read.All', 'User.RevokeSessions.All') }

        Assert-MockCalled Invoke-LOAConnectGraph -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It -ParameterFilter { ($Scopes -join ',') -eq 'User.Read.All,User.RevokeSessions.All' }
    }

    It 'connects when there is no Graph context' {
        InModuleScope Manage-UserLOA {
            Mock Invoke-LOAGetMgContext { $null }
            Mock Invoke-LOAConnectGraph {}
        }

        & $module { Connect-LOAGraph -RequiredScopes @('User.Read.All') }

        Assert-MockCalled Invoke-LOAConnectGraph -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It
    }

    It 'accepts $true and an object whose Value is $true as revoke success' {
        $plain = & $module { Test-LOARevokeResult -Result $true }
        $wrapped = & $module { Test-LOARevokeResult -Result ([pscustomobject]@{ Value = $true }) }

        Assert-Equal -Actual $plain -Expected $true -Message '$true should count as revoke success.'
        Assert-Equal -Actual $wrapped -Expected $true -Message 'An object with Value = $true should count as revoke success.'
    }

    It 'rejects $false, Value=$false and $null as revoke success' {
        foreach ($result in @($false, [pscustomobject]@{ Value = $false }, $null)) {
            $actual = & $module { param($r) Test-LOARevokeResult -Result $r } $result
            Assert-Equal -Actual $actual -Expected $false -Message "Revoke result '$result' should count as failure."
        }
    }
}
