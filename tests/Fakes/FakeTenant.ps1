# Fake tenant for Manage-UserLOA tests.
# Holds sample AD and Exchange Online state in $global:LOAFake and mocks the
# module's Invoke-LOA* wrappers to read and change it, so workflow tests run
# the real Start-UserLOA / End-UserLOA logic and assert on resulting state.
# Helpers called from inside mocks are global because mock bodies run in the
# module scope, not the test file scope.

$Script:LOAFakeLeaveOU = 'OU=Users on Temporary Leave,OU=Corporate,DC=yourdomain,DC=com'
$Script:LOAFakeSalesOU = 'OU=Sales,OU=Corporate,DC=yourdomain,DC=com'
$Script:LOAFakeFinanceOU = 'OU=Finance,OU=Corporate,DC=yourdomain,DC=com'

function New-LOAFakeADUser {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$UserPrincipalName,
        [Parameter(Mandatory)][string]$ParentOU,
        [bool]$Enabled = $true,
        [bool]$Hidden = $false,
        [string]$Manager,
        [string]$Department = 'Sales',
        [string]$Stash
    )

    @{
        DistinguishedName          = "CN=$Name,$ParentOU"
        DisplayName                = $Name
        SamAccountName             = ($UserPrincipalName -split '@')[0]
        UserPrincipalName          = $UserPrincipalName
        EmailAddress               = $UserPrincipalName
        Enabled                    = $Enabled
        msExchHideFromAddressLists = $Hidden
        Manager                    = $Manager
        Department                 = $Department
        extensionAttribute10       = if ($Stash) { $Stash } else { $null }
    }
}

function New-LOAFakeMailbox {
    param(
        [string[]]$FullAccess = @(),
        [string[]]$SendAs = @(),
        [string]$OOOState = 'Disabled'
    )

    @{
        FullAccess = [System.Collections.ArrayList]@($FullAccess)
        SendAs     = [System.Collections.ArrayList]@($SendAs)
        OOO        = @{
            AutoReplyState   = $OOOState
            StartTime        = $null
            EndTime          = $null
            InternalMessage  = if ($OOOState -eq 'Disabled') { $null } else { 'Personal OOO set by the user' }
            ExternalMessage  = if ($OOOState -eq 'Disabled') { $null } else { 'Personal OOO set by the user' }
            ExternalAudience = 'All'
        }
    }
}

function New-LOAFakeTenant {
    $johnDN = "CN=John Smith,$Script:LOAFakeSalesOU"

    $global:LOAFake = @{
        Config    = @{
            LOAOUDistinguishedName = $Script:LOAFakeLeaveOU
            DomainController       = 'DC01.yourdomain.com'
            OUStashAttribute       = 'extensionAttribute10'
        }
        OUs       = @{
            $Script:LOAFakeSalesOU   = 'organizationalUnit'
            $Script:LOAFakeFinanceOU = 'organizationalUnit'
            $Script:LOAFakeLeaveOU   = 'organizationalUnit'
        }
        ADUsers   = @{
            'jane.doe@yourdomain.com'   = New-LOAFakeADUser -Name 'Jane Doe' -UserPrincipalName 'jane.doe@yourdomain.com' -ParentOU $Script:LOAFakeSalesOU -Manager $johnDN
            'bob.lee@yourdomain.com'    = New-LOAFakeADUser -Name 'Bob Lee' -UserPrincipalName 'bob.lee@yourdomain.com' -ParentOU $Script:LOAFakeSalesOU -Manager $johnDN -Hidden $true
            'ana.ruiz@yourdomain.com'   = New-LOAFakeADUser -Name 'Ana Ruiz' -UserPrincipalName 'ana.ruiz@yourdomain.com' -ParentOU $Script:LOAFakeLeaveOU -Manager $johnDN -Department 'Finance' -Enabled $false -Hidden $true -Stash $Script:LOAFakeFinanceOU
            'john.smith@yourdomain.com' = New-LOAFakeADUser -Name 'John Smith' -UserPrincipalName 'john.smith@yourdomain.com' -ParentOU $Script:LOAFakeSalesOU
        }
        Mailboxes = @{
            'jane.doe@yourdomain.com'   = New-LOAFakeMailbox
            'bob.lee@yourdomain.com'    = New-LOAFakeMailbox -FullAccess @('john.smith@yourdomain.com') -OOOState 'Enabled'
            'ana.ruiz@yourdomain.com'   = New-LOAFakeMailbox -FullAccess @('john.smith@yourdomain.com') -SendAs @('john.smith@yourdomain.com') -OOOState 'Enabled'
            'john.smith@yourdomain.com' = New-LOAFakeMailbox
        }
        Faults    = @{}
        Calls     = [System.Collections.ArrayList]@()
    }
}

function global:Invoke-LOAFakeOperation {
    # Records the call and runs any injected fault before the fake operation.
    param([Parameter(Mandatory)][string]$Name)

    [void]$global:LOAFake.Calls.Add($Name)
    if ($global:LOAFake.Faults.ContainsKey($Name)) {
        & $global:LOAFake.Faults[$Name]
    }
}

function global:Find-LOAFakeADUser {
    param(
        [string]$UserPrincipalName,
        [string]$DistinguishedName
    )

    if ($UserPrincipalName) {
        return $global:LOAFake.ADUsers[$UserPrincipalName]
    }

    $global:LOAFake.ADUsers.Values | Where-Object { $_.DistinguishedName -eq $DistinguishedName } | Select-Object -First 1
}

function global:Get-LOAFakeADUserByDN {
    param([Parameter(Mandatory)][string]$DistinguishedName)

    $user = Find-LOAFakeADUser -DistinguishedName $DistinguishedName
    if (-not $user) { throw "Fake AD: no user with DN $DistinguishedName" }
    $user
}

function Register-LOAFakeTenantMocks {
    InModuleScope Manage-UserLOA {
        Mock Import-LOAConfig { $Script:Config = $global:LOAFake.Config }
        Mock Connect-LOAServices {}
        Mock Write-Host {}
        Mock Start-Sleep {}

        Mock Invoke-LOAGetADUser {
            Invoke-LOAFakeOperation 'GetADUser'
            $user = if ($UserPrincipalName) { Find-LOAFakeADUser -UserPrincipalName $UserPrincipalName } else { Find-LOAFakeADUser -DistinguishedName $Identity }
            if ($user) { [pscustomobject]$user.Clone() }
        }

        Mock Invoke-LOAGetADObject {
            Invoke-LOAFakeOperation 'GetADObject'
            if (-not $global:LOAFake.OUs.ContainsKey($Identity)) { throw "Fake AD: object not found: $Identity" }
            [pscustomobject]@{ DistinguishedName = $Identity; ObjectClass = $global:LOAFake.OUs[$Identity] }
        }

        Mock Invoke-LOASetADUser {
            Invoke-LOAFakeOperation 'SetADUser'
            $user = Get-LOAFakeADUserByDN -DistinguishedName $Identity
            if ($Replace) {
                foreach ($key in $Replace.Keys) { $user[$key] = $Replace[$key] }
            }
            if ($Clear) { $user[$Clear] = $null }
        }

        Mock Invoke-LOADisableADAccount {
            Invoke-LOAFakeOperation 'DisableADAccount'
            (Get-LOAFakeADUserByDN -DistinguishedName $Identity).Enabled = $false
        }

        Mock Invoke-LOAEnableADAccount {
            Invoke-LOAFakeOperation 'EnableADAccount'
            (Get-LOAFakeADUserByDN -DistinguishedName $Identity).Enabled = $true
        }

        Mock Invoke-LOAMoveADObject {
            Invoke-LOAFakeOperation 'MoveADObject'
            if (-not $global:LOAFake.OUs.ContainsKey($TargetPath)) { throw "Fake AD: target not found: $TargetPath" }
            $user = Get-LOAFakeADUserByDN -DistinguishedName $Identity
            $leadingCN = ($Identity -split '(?<!\\),', 2)[0]
            $user.DistinguishedName = "$leadingCN,$TargetPath"
        }

        Mock Invoke-LOAGetMailboxPermission {
            Invoke-LOAFakeOperation 'GetMailboxPermission'
            foreach ($grantee in $global:LOAFake.Mailboxes[$Identity].FullAccess) {
                [pscustomobject]@{ User = $grantee; AccessRights = @('FullAccess'); IsInherited = $false; Deny = $false }
            }
        }

        Mock Invoke-LOAGetRecipientPermission {
            Invoke-LOAFakeOperation 'GetRecipientPermission'
            foreach ($trustee in $global:LOAFake.Mailboxes[$Identity].SendAs) {
                [pscustomobject]@{ Trustee = $trustee; AccessRights = @('SendAs') }
            }
        }

        Mock Invoke-LOAGetMailboxAutoReplyConfiguration {
            Invoke-LOAFakeOperation 'GetMailboxAutoReplyConfiguration'
            [pscustomobject]$global:LOAFake.Mailboxes[$Identity].OOO.Clone()
        }

        Mock Invoke-LOAAddMailboxPermission {
            Invoke-LOAFakeOperation 'AddMailboxPermission'
            $grants = $global:LOAFake.Mailboxes[$Identity].FullAccess
            if ($grants -notcontains $User) { [void]$grants.Add($User) }
        }

        Mock Invoke-LOARemoveMailboxPermission {
            Invoke-LOAFakeOperation 'RemoveMailboxPermission'
            $global:LOAFake.Mailboxes[$Identity].FullAccess.Remove($User)
        }

        Mock Invoke-LOAAddRecipientPermission {
            Invoke-LOAFakeOperation 'AddRecipientPermission'
            $grants = $global:LOAFake.Mailboxes[$Identity].SendAs
            if ($grants -notcontains $Trustee) { [void]$grants.Add($Trustee) }
        }

        Mock Invoke-LOARemoveRecipientPermission {
            Invoke-LOAFakeOperation 'RemoveRecipientPermission'
            $global:LOAFake.Mailboxes[$Identity].SendAs.Remove($Trustee)
        }

        Mock Invoke-LOASetMailboxAutoReplyConfiguration {
            Invoke-LOAFakeOperation 'SetMailboxAutoReplyConfiguration'
            $ooo = $global:LOAFake.Mailboxes[$Identity].OOO
            if ($DisabledState) {
                $ooo.AutoReplyState = 'Disabled'
                return
            }
            $ooo.AutoReplyState = $AutoReplyState
            $ooo.InternalMessage = $InternalMessage
            $ooo.ExternalMessage = $ExternalMessage
            $ooo.ExternalAudience = $ExternalAudience
        }
    }
}

function Get-LOAFakeUserState {
    # A comparable slice of everything the workflow can change for one user.
    param([Parameter(Mandatory)][string]$UserPrincipalName)

    $user = $global:LOAFake.ADUsers[$UserPrincipalName]
    $mailbox = $global:LOAFake.Mailboxes[$UserPrincipalName]

    [ordered]@{
        Enabled       = $user.Enabled
        HiddenFromGAL = [bool]$user.msExchHideFromAddressLists
        ParentOU      = $user.DistinguishedName -replace '^CN=(?:[^,\\]|\\.)+,', ''
        StashedOU     = $user.extensionAttribute10
        FullAccess    = @($mailbox.FullAccess | Sort-Object)
        SendAs        = @($mailbox.SendAs | Sort-Object)
        OOOState      = $mailbox.OOO.AutoReplyState
    }
}

function ConvertTo-LOAComparable {
    param($InputObject)

    ConvertTo-Json -InputObject $InputObject -Depth 10 -Compress
}
