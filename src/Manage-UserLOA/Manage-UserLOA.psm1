# Manage-UserLOA
# Leave-of-absence workflow module for hybrid AD / Microsoft 365 environments.
# Public commands: Start-UserLOA, End-UserLOA
# See README.md for prerequisites and usage.

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Environment-specific settings live in a .psd1 file, loaded by
# Import-LOAConfig at the start of each public command. See
# examples\config.example.psd1 for the keys.
$Script:Config = $null

# Keys Import-LOAConfig recognises. Anything else in the file is warned about,
# which catches settings left over from older versions.
$Script:LOAKnownConfigKeys = @('LOAOUDistinguishedName', 'DomainController', 'OUStashAttribute', 'SignInBlockGroupId')

# ---------------------------------------------------------------------------
# External command wrappers
# ---------------------------------------------------------------------------

function Invoke-LOAGetADUser {
    [CmdletBinding(DefaultParameterSetName = 'UserPrincipalName')]
    param(
        [Parameter(ParameterSetName = 'UserPrincipalName', Mandatory)][string]$UserPrincipalName,
        [Parameter(ParameterSetName = 'Identity', Mandatory)][string]$Identity,
        [string[]]$Properties,
        [string]$Server
    )

    if ($PSCmdlet.ParameterSetName -eq 'Identity') {
        Get-ADUser -Identity $Identity -Properties $Properties -Server $Server
        return
    }

    # Scriptblock filters bind variables safely through the AD provider and
    # avoid building a filter string by hand.
    Get-ADUser -Filter { UserPrincipalName -eq $UserPrincipalName } -Properties $Properties -Server $Server
}

function Invoke-LOAGetADObject {
    param(
        [Parameter(Mandatory)][string]$Identity,
        [string]$Server
    )

    Get-ADObject -Identity $Identity -Server $Server -ErrorAction Stop
}

function Invoke-LOASetADUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identity,
        [hashtable]$Replace,
        [string]$Clear,
        [string]$Server
    )

    $setParams = @{
        Identity = $Identity
        Server = $Server
        ErrorAction = 'Stop'
    }

    if ($Replace) {
        $setParams.Replace = $Replace
    }

    if ($Clear) {
        $setParams.Clear = $Clear
    }

    Set-ADUser @setParams
}

function Invoke-LOADisableADAccount {
    param(
        [Parameter(Mandatory)][string]$Identity,
        [string]$Server
    )

    Disable-ADAccount -Identity $Identity -Server $Server -ErrorAction Stop
}

function Invoke-LOAEnableADAccount {
    param(
        [Parameter(Mandatory)][string]$Identity,
        [string]$Server
    )

    Enable-ADAccount -Identity $Identity -Server $Server -ErrorAction Stop
}

function Invoke-LOAMoveADObject {
    param(
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][string]$TargetPath,
        [string]$Server
    )

    Move-ADObject -Identity $Identity -TargetPath $TargetPath -Server $Server -ErrorAction Stop
}

function Invoke-LOAGetMailboxPermission {
    param(
        [Parameter(Mandatory)][string]$Identity
    )

    Get-MailboxPermission -Identity $Identity -ErrorAction SilentlyContinue
}

function Invoke-LOAGetRecipientPermission {
    param(
        [Parameter(Mandatory)][string]$Identity
    )

    Get-RecipientPermission -Identity $Identity -ErrorAction SilentlyContinue
}

function Invoke-LOAGetMailboxAutoReplyConfiguration {
    param(
        [Parameter(Mandatory)][string]$Identity
    )

    Get-MailboxAutoReplyConfiguration -Identity $Identity -ErrorAction SilentlyContinue
}

function Invoke-LOAAddMailboxPermission {
    param(
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][string]$User
    )

    Add-MailboxPermission -Identity $Identity -User $User -AccessRights FullAccess -InheritanceType All -AutoMapping $false -ErrorAction Stop | Out-Null
}

function Invoke-LOAAddRecipientPermission {
    param(
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][string]$Trustee
    )

    Add-RecipientPermission -Identity $Identity -Trustee $Trustee -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
}

function Invoke-LOARemoveMailboxPermission {
    param(
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][string]$User
    )

    Remove-MailboxPermission -Identity $Identity -User $User -AccessRights FullAccess -Confirm:$false -ErrorAction Stop | Out-Null
}

function Invoke-LOARemoveRecipientPermission {
    param(
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][string]$Trustee
    )

    Remove-RecipientPermission -Identity $Identity -Trustee $Trustee -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
}

function Invoke-LOASetMailboxAutoReplyConfiguration {
    [CmdletBinding(DefaultParameterSetName = 'Enable')]
    param(
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(ParameterSetName = 'Enable', Mandatory)][string]$InternalMessage,
        [Parameter(ParameterSetName = 'Enable', Mandatory)][string]$ExternalMessage,
        [Parameter(ParameterSetName = 'Enable', Mandatory)][string]$ExternalAudience,
        [Parameter(ParameterSetName = 'Enable', Mandatory)][ValidateSet('Enabled')][string]$AutoReplyState,
        [Parameter(ParameterSetName = 'Disable', Mandatory)][ValidateSet('Disabled')][string]$DisabledState
    )

    if ($PSCmdlet.ParameterSetName -eq 'Disable') {
        Set-MailboxAutoReplyConfiguration -Identity $Identity -AutoReplyState $DisabledState -ErrorAction Stop
        return
    }

    Set-MailboxAutoReplyConfiguration -Identity $Identity `
        -AutoReplyState $AutoReplyState `
        -InternalMessage $InternalMessage `
        -ExternalMessage $ExternalMessage `
        -ExternalAudience $ExternalAudience `
        -ErrorAction Stop
}

function Invoke-LOAGetMgContext {
    Get-MgContext
}

function Invoke-LOAConnectGraph {
    param(
        [Parameter(Mandatory)][string[]]$Scopes
    )

    Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
}

function Invoke-LOAGetMgUser {
    param(
        [Parameter(Mandatory)][string]$UserId
    )

    Get-MgUser -UserId $UserId -Property Id,AccountEnabled -ErrorAction Stop
}

function Invoke-LOARevokeSignInSession {
    param(
        [Parameter(Mandatory)][string]$UserId
    )

    Revoke-MgUserSignInSession -UserId $UserId -ErrorAction Stop
}

function Invoke-LOAGetGroupMember {
    param(
        [Parameter(Mandatory)][string]$GroupId
    )

    Get-MgGroupMember -GroupId $GroupId -All -ErrorAction Stop
}

function Invoke-LOAAddGroupMember {
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$DirectoryObjectId
    )

    New-MgGroupMember -GroupId $GroupId -DirectoryObjectId $DirectoryObjectId -ErrorAction Stop
}

function Invoke-LOARemoveGroupMember {
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$DirectoryObjectId
    )

    Remove-MgGroupMemberByRef -GroupId $GroupId -DirectoryObjectId $DirectoryObjectId -ErrorAction Stop
}

function Invoke-LOAGetUserStateSnapshot {
    param(
        [Parameter(Mandatory)][string]$UserPrincipalName
    )

    Get-UserStateSnapshot -UserPrincipalName $UserPrincipalName
}

# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

function Resolve-LOAConfigPath {
    param([string]$ConfigPath)

    # Explicit parameter, then environment variable, then the machine-wide
    # default. Existence is checked by Import-LOAConfig.
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { return $ConfigPath }
    if (-not [string]::IsNullOrWhiteSpace($env:MANAGE_USERLOA_CONFIG)) { return $env:MANAGE_USERLOA_CONFIG }
    Join-Path $env:ProgramData 'Manage-UserLOA\config.psd1'
}

function Test-LOAConfig {
    param([Parameter(Mandatory)][hashtable]$Config)

    # Collect every problem so the operator can fix the file in one pass.
    $problems = @()
    foreach ($key in @('LOAOUDistinguishedName', 'DomainController', 'OUStashAttribute')) {
        if (-not $Config.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$Config[$key])) {
            $problems += "Missing required key '$key'"
        }
    }

    $stash = $Config['OUStashAttribute']
    if ($null -ne $stash -and -not ($stash -is [string] -and $stash -match '^extensionAttribute([1-9]|1[0-5])$')) {
        $problems += "OUStashAttribute must be extensionAttribute1 to extensionAttribute15 (found '$stash')"
    }

    $loaOU = $Config['LOAOUDistinguishedName']
    if (-not [string]::IsNullOrWhiteSpace([string]$loaOU) -and -not ($loaOU -is [string] -and $loaOU -match '^(OU|CN)=')) {
        $problems += "LOAOUDistinguishedName must be a distinguished name starting with OU= or CN= (found '$loaOU')"
    }

    $dc = $Config['DomainController']
    if ($null -ne $dc -and $dc -isnot [string]) {
        $problems += 'DomainController must be a string'
    }

    # A group name instead of its object ID is an easy mistake and would only
    # surface as a Graph error after Start had begun.
    $blockGroup = $Config['SignInBlockGroupId']
    if ($null -ne $blockGroup -and -not ($blockGroup -is [string] -and ($blockGroup -eq '' -or $blockGroup -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'))) {
        $problems += "SignInBlockGroupId must be the group's object ID (a GUID) or empty (found '$blockGroup')"
    }

    $problems
}

function Import-LOAConfig {
    param([string]$ConfigPath)

    $path = Resolve-LOAConfigPath -ConfigPath $ConfigPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $defaultPath = Join-Path $env:ProgramData 'Manage-UserLOA\config.psd1'
        throw "Config file not found: $path. Pass -ConfigPath, set MANAGE_USERLOA_CONFIG, or create $defaultPath."
    }

    try {
        $config = Import-PowerShellDataFile -Path $path -ErrorAction Stop
    } catch {
        throw "Config file '$path' could not be read: $($_.Exception.Message)"
    }

    $problems = @(Test-LOAConfig -Config $config)
    if ($problems.Count -gt 0) {
        throw ("Config file '$path' is invalid:" + (($problems | ForEach-Object { "`n - $_" }) -join ''))
    }

    foreach ($key in $config.Keys) {
        if ($Script:LOAKnownConfigKeys -notcontains $key) {
            Write-Warning "Unknown config key '$key' in $path is ignored."
        }
    }

    $Script:Config = $config
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Connect-LOAServices {
    # Fail early if the target DC is not reachable. Most of the script depends
    # on AD, so this gives a clearer error than several later command failures.
    if (-not (Test-Connection -ComputerName $Script:Config.DomainController -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        throw "Domain controller '$($Script:Config.DomainController)' is not reachable. Check connectivity or update DomainController in the config file."
    }

    # Load the modules only if they are not already available in the session.
    if (-not (Get-Module ActiveDirectory)) {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    if (-not (Get-Module ExchangeOnlineManagement)) {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
    }
    foreach ($graphModule in @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Users.Actions', 'Microsoft.Graph.Groups')) {
        if (-not (Get-Module $graphModule)) {
            Import-Module $graphModule -ErrorAction Stop
        }
    }

    # Reuse an existing EXO session if one is already connected. -DisableWAM
    # avoids Windows Account Manager choosing the wrong cached Microsoft account.
    $exo = Get-ConnectionInformation -ErrorAction SilentlyContinue | Where-Object State -eq 'Connected'
    if (-not $exo) {
        Connect-ExchangeOnline -ShowBanner:$false -DisableWAM -ErrorAction Stop
    }

    # Graph is used to cut off Microsoft 365 sign-in after the AD disable.
    Connect-LOAGraph -RequiredScopes (Get-LOAGraphScopes)
}

function Get-LOAGraphScopes {
    # Delegated scopes the operator consents to. GroupMember.ReadWrite.All is
    # only requested when the sign-in block group is configured.
    $scopes = @('User.Read.All', 'User.RevokeSessions.All')
    if (-not [string]::IsNullOrWhiteSpace($Script:Config.SignInBlockGroupId)) {
        $scopes += 'GroupMember.ReadWrite.All'
    }
    $scopes
}

function Connect-LOAGraph {
    param([Parameter(Mandatory)][string[]]$RequiredScopes)

    # Reuse the operator's existing Graph session when it already carries every
    # scope we need. Graph can report scopes in a different case, so compare
    # case-insensitively.
    $context = Invoke-LOAGetMgContext
    if ($context) {
        $granted = @($context.Scopes | ForEach-Object { "$_".ToLowerInvariant() })
        $missing = @($RequiredScopes | Where-Object { $granted -notcontains $_.ToLowerInvariant() })
        if ($missing.Count -eq 0) { return }
    }

    Invoke-LOAConnectGraph -Scopes $RequiredScopes
}

function Get-LOAEntraUserId {
    param([Parameter(Mandatory)][string]$UserPrincipalName)

    (Invoke-LOAGetMgUser -UserId $UserPrincipalName).Id
}

function Test-LOARevokeResult {
    param([AllowNull()]$Result)

    # Revoke-MgUserSignInSession returns $true, or an object wrapping it in
    # Value, depending on the Graph SDK version.
    if ($Result -is [bool]) { return $Result }
    if ($null -ne $Result -and $Result.PSObject.Properties['Value']) { return ($Result.Value -eq $true) }
    $false
}

function Test-LOABlockGroupMember {
    param([Parameter(Mandatory)][string]$UserId)

    @(Invoke-LOAGetGroupMember -GroupId $Script:Config.SignInBlockGroupId | Where-Object { $_.Id -eq $UserId }).Count -gt 0
}

function Add-LOASignInBlock {
    param(
        [Parameter(Mandatory)][string]$UserPrincipalName,
        [Parameter(Mandatory)][string]$UserId
    )

    # Membership of this cloud-only group is targeted by a Conditional Access
    # "Block access" policy, so it stops new sign-ins without waiting for
    # Entra Connect to sync the AD disable.
    try {
        if (Test-LOABlockGroupMember -UserId $UserId) {
            Write-Host '  [SKIP] Already in sign-in block group' -ForegroundColor Yellow
            return
        }
        Invoke-LOAAddGroupMember -GroupId $Script:Config.SignInBlockGroupId -DirectoryObjectId $UserId
    } catch {
        throw "Sign-in block group add failed for ${UserPrincipalName}: $($_.Exception.Message.TrimEnd('.')). No account changes were made after the OU stash; fix the cause and rerun Start-UserLOA."
    }
    Write-Host '  [OK] Added to sign-in block group' -ForegroundColor Green
}

function Remove-LOASignInBlock {
    param([Parameter(Mandatory)][string]$UserPrincipalName)

    # The user is returning, so a failure here is reported for manual follow-up
    # instead of stopping the rest of the return workflow.
    try {
        $userId = Get-LOAEntraUserId -UserPrincipalName $UserPrincipalName
        if (-not (Test-LOABlockGroupMember -UserId $userId)) {
            Write-Host '  [SKIP] Not in sign-in block group' -ForegroundColor Yellow
            return
        }
        Invoke-LOARemoveGroupMember -GroupId $Script:Config.SignInBlockGroupId -DirectoryObjectId $userId
        Write-Host '  [OK] Removed from sign-in block group' -ForegroundColor Green
    } catch {
        Write-Host "  [ERR] Sign-in block group removal failed: $($_.Exception.Message.TrimEnd('.')). Remove $UserPrincipalName from the group manually." -ForegroundColor Red
    }
}

function Invoke-LOASessionRevoke {
    param(
        [Parameter(Mandatory)][string]$UserPrincipalName,
        [Parameter(Mandatory)][string]$UserId
    )

    # Revoking refresh tokens forces every client to sign in again, which the
    # AD disable (once synced) or the block group then refuses.
    $result = $null
    $failure = $null
    try {
        $result = Invoke-LOARevokeSignInSession -UserId $UserId
    } catch {
        $failure = $_.Exception.Message.TrimEnd('.')
    }

    if (-not $failure -and -not (Test-LOARevokeResult -Result $result)) {
        $failure = 'unexpected result'
    }
    if ($failure) {
        throw "Session revoke failed for ${UserPrincipalName}: $failure. The AD account is disabled but the user has not been moved or delegated; fix the cause and rerun Start-UserLOA."
    }
    Write-Host '  [OK] Microsoft 365 sign-in sessions revoked' -ForegroundColor Green
}

function Get-LOAUser {
    param([Parameter(Mandatory)][string]$UserPrincipalName)

    $props = @('DisplayName', 'EmailAddress', 'Manager', 'msExchHideFromAddressLists', $Script:Config.OUStashAttribute)
    $adUser = Invoke-LOAGetADUser -UserPrincipalName $UserPrincipalName -Properties $props -Server $Script:Config.DomainController
    if (-not $adUser) { throw "User $UserPrincipalName not found in AD" }
    if (@($adUser).Count -gt 1) { throw "Multiple AD users found for $UserPrincipalName" }

    $adUser
}

function Get-ParentOU {
    param([Parameter(Mandatory)][string]$DistinguishedName)

    # Removes only the leading CN portion. The regex handles escaped commas in
    # names, for example CN=Doe\, Jane,OU=Users,...
    $DistinguishedName -replace '^CN=(?:[^,\\]|\\.)+,', ''
}

function Get-LOAStashedOU {
    param([Parameter(Mandatory)]$ADUser)

    # The stash attribute name is configurable, so read it dynamically from the
    # AD object instead of hardcoding extensionAttribute10 here.
    $stashProperty = $ADUser.PSObject.Properties[$Script:Config.OUStashAttribute]
    if ($stashProperty) { $stashProperty.Value }
}

function Format-LOASummaryValue {
    param($Value)

    # Console summaries should be easy to scan. Empty values are printed as
    # (none) instead of blank space.
    if ($null -eq $Value) { return '(none)' }
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return '(none)' }
    $Value
}

function Test-LOADelegateIdentityMatch {
    param(
        [AllowNull()]$Identity,
        [Parameter(Mandatory)][string]$DelegateUPN
    )

    if ($null -eq $Identity -or [string]::IsNullOrWhiteSpace($DelegateUPN)) {
        return $false
    }

    # Exchange may report permission principals as UPN, alias, or DOMAIN\alias.
    # Normalize enough of those forms so tests and removals do not skip a real grant.
    $identityText = $Identity.ToString().Trim()
    $delegateText = $DelegateUPN.Trim()
    $delegateAlias = ($delegateText -split '@', 2)[0]

    if ([string]::Equals($identityText, $delegateText, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($delegateAlias)) {
        return $false
    }

    if ([string]::Equals($identityText, $delegateAlias, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $identityText.EndsWith("\$delegateAlias", [StringComparison]::OrdinalIgnoreCase)
}

function Wait-LOAUserStateSnapshot {
    param(
        [Parameter(Mandatory)][string]$UserPrincipalName,
        [Parameter(Mandatory)][scriptblock]$IsSatisfied,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 2,
        [string]$WarningMessage = 'Mailbox state did not converge before the summary snapshot.'
    )

    $latestSnapshot = $null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $latestSnapshot = Invoke-LOAGetUserStateSnapshot -UserPrincipalName $UserPrincipalName
        if (& $IsSatisfied $latestSnapshot) {
            return $latestSnapshot
        }

        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    Write-Host "  [WARN] $WarningMessage" -ForegroundColor Yellow
    $latestSnapshot
}

function Get-UserStateSnapshot {
    param([Parameter(Mandatory)][string]$UserPrincipalName)

    # A snapshot is the script's audit-friendly view of the user at a point in
    # time. Operators copy these blocks into tickets before and after changes.
    $adUser = Get-LOAUser -UserPrincipalName $UserPrincipalName

    # Mailbox delegations: only user-set, not inherited or system.
    $fullAccess = Invoke-LOAGetMailboxPermission -Identity $UserPrincipalName |
        Where-Object {
            -not $_.IsInherited -and
            -not $_.Deny -and
            $_.User -notlike 'NT AUTHORITY\*' -and
            $_.User -notlike 'S-1-5-*' -and
            $_.AccessRights -contains 'FullAccess'
        } | Select-Object -ExpandProperty User

    $sendAs = Invoke-LOAGetRecipientPermission -Identity $UserPrincipalName |
        Where-Object {
            $_.Trustee -notlike 'NT AUTHORITY\*' -and
            $_.AccessRights -contains 'SendAs'
        } | Select-Object -ExpandProperty Trustee

    $ooo = Invoke-LOAGetMailboxAutoReplyConfiguration -Identity $UserPrincipalName

    # PSCustomObject keeps the summary fields ordered and easy to print.
    [PSCustomObject]@{
        DisplayName       = $adUser.DisplayName
        SamAccountName    = $adUser.SamAccountName
        UserPrincipalName = $adUser.UserPrincipalName
        DistinguishedName = $adUser.DistinguishedName
        Enabled           = $adUser.Enabled
        HiddenFromGAL     = [bool]$adUser.msExchHideFromAddressLists
        StashedOU         = Get-LOAStashedOU -ADUser $adUser
        FullAccessGrants  = @($fullAccess)
        SendAsGrants      = @($sendAs)
        OOOState          = if ($ooo) { $ooo.AutoReplyState } else { 'Unavailable' }
        OOOStartTime      = if ($ooo) { $ooo.StartTime } else { $null }
        OOOEndTime        = if ($ooo) { $ooo.EndTime } else { $null }
        Timestamp         = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
}

function Assert-LOAOrganizationalUnit {
    param(
        [Parameter(Mandatory)][string]$DistinguishedName,
        [Parameter(Mandatory)][string]$Purpose
    )

    # Validate target OUs before moving users. Some default AD locations are
    # containers rather than OUs, so accept both object classes.
    try {
        $target = Invoke-LOAGetADObject -Identity $DistinguishedName -Server $Script:Config.DomainController
    } catch {
        throw "$Purpose OU/container not found or unreachable on $($Script:Config.DomainController): $DistinguishedName. $($_.Exception.Message)"
    }

    if ($target.ObjectClass -notin @('organizationalUnit', 'container')) {
        throw "$Purpose is not an OU or container: $DistinguishedName"
    }
}

function Get-LOAFullAccessGrantIdentities {
    param(
        [Parameter(Mandatory)][string]$MailboxUPN,
        [Parameter(Mandatory)][string]$DelegateUPN
    )

    # Pull the full ACL and filter locally. The EXO -User filtered view can lag
    # immediately after permission changes, while the full ACL is more reliable.
    Invoke-LOAGetMailboxPermission -Identity $MailboxUPN |
        Where-Object {
            -not $_.IsInherited -and
            -not $_.Deny -and
            $_.AccessRights -contains 'FullAccess' -and
            (Test-LOADelegateIdentityMatch -Identity $_.User -DelegateUPN $DelegateUPN)
        } |
        ForEach-Object { $_.User.ToString() } |
        Sort-Object -Unique
}

function Test-LOAFullAccessGrant {
    param(
        [Parameter(Mandatory)][string]$MailboxUPN,
        [Parameter(Mandatory)][string]$DelegateUPN
    )

    # Boolean wrapper used by Start to decide whether it needs to add a grant.
    $permission = @(Get-LOAFullAccessGrantIdentities -MailboxUPN $MailboxUPN -DelegateUPN $DelegateUPN)

    $permission.Count -gt 0
}

function Get-LOASendAsGrantIdentities {
    param(
        [Parameter(Mandatory)][string]$MailboxUPN,
        [Parameter(Mandatory)][string]$DelegateUPN
    )

    # Same pattern as FullAccess: read all SendAs permissions and filter in
    # PowerShell so Exchange indexing delays do not hide a fresh permission.
    Invoke-LOAGetRecipientPermission -Identity $MailboxUPN |
        Where-Object {
            $_.AccessRights -contains 'SendAs' -and
            (Test-LOADelegateIdentityMatch -Identity $_.Trustee -DelegateUPN $DelegateUPN)
        } |
        ForEach-Object { $_.Trustee.ToString() } |
        Sort-Object -Unique
}

function Test-LOASendAsGrant {
    param(
        [Parameter(Mandatory)][string]$MailboxUPN,
        [Parameter(Mandatory)][string]$DelegateUPN
    )

    # Boolean wrapper used by Start to avoid adding duplicate SendAs permission.
    $permission = @(Get-LOASendAsGrantIdentities -MailboxUPN $MailboxUPN -DelegateUPN $DelegateUPN)

    $permission.Count -gt 0
}

function Resolve-OOOAction {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [switch]$ForceOOO
    )

    # Decide whether Start should overwrite OOO. Any enabled or scheduled OOO
    # may be personal/user-managed, so only -ForceOOO replaces it.
    if ($ForceOOO)                            { return 'Set' }
    if ($Snapshot.OOOState -eq 'Disabled')    { return 'Set' }
    if ($Snapshot.OOOState -eq 'Unavailable') { return 'Skip' }
    'ManualReview'
}

function Get-OOOManualReviewContext {
    param([Parameter(Mandatory)]$Snapshot)

    # Builds the human-readable reason shown when OOO needs operator review.
    if ($Snapshot.OOOState -eq 'Enabled') {
        return 'OOO is already enabled'
    }

    if ($Snapshot.OOOState -eq 'Scheduled') {
        if ($Snapshot.OOOStartTime) {
            return "OOO is scheduled to start at $($Snapshot.OOOStartTime)"
        }
        return 'OOO is scheduled'
    }

    "OOO is in state '$($Snapshot.OOOState)'"
}

function Show-LOAPreExistingWarnings {
    param(
        [Parameter(Mandatory)]$Before,
        [Parameter(Mandatory)][string]$ManagerUPN
    )

    # These warnings are about state that existed before LOA. The script can
    # perform the standard workflow, but the operator should note these cases.
    Write-Host ''
    Write-Host 'Pre-existing state checks:' -ForegroundColor Yellow
    $warningCount = 0

    if ($Before.HiddenFromGAL -eq $true) {
        Write-Host '  [PRE-EXISTING] User was already hidden from GAL before LOA. End-UserLOA will unhide them on return - verify this is intended and note in the ticket.' -ForegroundColor Yellow
        $warningCount++
    }

    $fullAccessInBeforeSnapshot = @($Before.FullAccessGrants | Where-Object { Test-LOADelegateIdentityMatch -Identity $_ -DelegateUPN $ManagerUPN }).Count -gt 0
    if ($fullAccessInBeforeSnapshot) {
        Write-Host "  [PRE-EXISTING] Manager $ManagerUPN already had FullAccess on this mailbox before LOA started. Confirm with the manager that losing access at LOA end is acceptable. Default behavior is to remove on End." -ForegroundColor Yellow
        $warningCount++
    }

    $sendAsInBeforeSnapshot = @($Before.SendAsGrants | Where-Object { Test-LOADelegateIdentityMatch -Identity $_ -DelegateUPN $ManagerUPN }).Count -gt 0
    if ($sendAsInBeforeSnapshot) {
        Write-Host "  [PRE-EXISTING] Manager $ManagerUPN already had SendAs on this mailbox before LOA started. Confirm with the manager that losing access at LOA end is acceptable. Default behavior is to remove on End." -ForegroundColor Yellow
        $warningCount++
    }

    if ($warningCount -eq 0) {
        Write-Host '  (none)' -ForegroundColor Green
    }
    Write-Host ''
}

function Show-UserSummary {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)]$Snapshot
    )

    # This is intentionally console-first output. The ticket is the long-term
    # record, so the block is formatted for easy copy/paste.
    $line = '-' * 60
    Write-Host ''
    Write-Host $line -ForegroundColor Cyan
    Write-Host " $Label  ($($Snapshot.Timestamp))" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("  Display Name      : {0}" -f $Snapshot.DisplayName)
    Write-Host ("  UPN               : {0}" -f $Snapshot.UserPrincipalName)
    Write-Host ("  OU / DN           : {0}" -f $Snapshot.DistinguishedName)
    Write-Host ("  Stashed Return OU : {0}" -f (Format-LOASummaryValue $Snapshot.StashedOU))
    Write-Host ("  Enabled           : {0}" -f $Snapshot.Enabled)
    Write-Host ("  Hidden from GAL   : {0}" -f $Snapshot.HiddenFromGAL)
    Write-Host ("  Mailbox FullAccess: {0}" -f (Format-LOASummaryValue (@($Snapshot.FullAccessGrants) -join ', ')))
    Write-Host ("  Mailbox SendAs    : {0}" -f (Format-LOASummaryValue (@($Snapshot.SendAsGrants) -join ', ')))
    Write-Host ("  Out-of-Office     : {0}" -f $Snapshot.OOOState)
    Write-Host ("  OOO Start         : {0}" -f (Format-LOASummaryValue $Snapshot.OOOStartTime))
    Write-Host ("  OOO End           : {0}" -f (Format-LOASummaryValue $Snapshot.OOOEndTime))
    Write-Host $line -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Start LOA
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Starts the leave-of-absence workflow for a user.

.DESCRIPTION
    Disables the on-premises AD account, hides the user from the GAL, moves
    the user into the configured LOA OU, grants mailbox access to the user's
    manager, optionally sets the default OOO message, and prints before/after
    ticket summaries.

.PARAMETER UserPrincipalName
    The UPN of the user entering leave.

.PARAMETER ManagerUPN
    Optional manager UPN. If omitted, the script uses the user's AD manager.

.PARAMETER ForceOOO
    Overrides the OOO safety check and applies the default OOO message.

.PARAMETER ConfigPath
    Path to the config .psd1. Defaults to $env:MANAGE_USERLOA_CONFIG, then
    $env:ProgramData\Manage-UserLOA\config.psd1.

.EXAMPLE
    Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -WhatIf

.EXAMPLE
    Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com' -ForceOOO
#>
function Start-UserLOA {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')][string]$UserPrincipalName,
        [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')][string]$ManagerUPN,
        [switch]$ForceOOO,
        [string]$ConfigPath
    )

    # Load and validate config before connecting, so a bad file fails fast.
    Import-LOAConfig -ConfigPath $ConfigPath

    # Connect to AD and Exchange before doing any lookups or changes.
    Connect-LOAServices

    # Get the AD user once up front, then validate the LOA destination OU before
    # changing account state.
    $adUser = Get-LOAUser -UserPrincipalName $UserPrincipalName
    Assert-LOAOrganizationalUnit -DistinguishedName $Script:Config.LOAOUDistinguishedName -Purpose 'LOA target'

    # Resolve the manager used for mailbox delegation and the OOO message.
    # If -ManagerUPN is omitted, use the manager currently recorded on the AD user.
    $managerProps = @('DisplayName', 'EmailAddress')
    if (-not $ManagerUPN) {
        if (-not $adUser.Manager) { throw 'No manager set on user and no -ManagerUPN provided' }
        $managerObj = Invoke-LOAGetADUser -Identity $adUser.Manager -Properties $managerProps -Server $Script:Config.DomainController
        $ManagerUPN = $managerObj.UserPrincipalName
    } else {
        $managerObj = Invoke-LOAGetADUser -UserPrincipalName $ManagerUPN -Properties $managerProps -Server $Script:Config.DomainController
        if (-not $managerObj) { throw "Manager $ManagerUPN not found in AD" }
    }

    $managerDisplayName = $managerObj.DisplayName

    # Graph pre-check. Resolve the Entra user, and read the block group when
    # one is configured, before anything is written. A user who is not synced
    # to Entra, a wrong group ID or missing consent then stops Start with the
    # account untouched instead of after the OU stash or the AD disable.
    $hasBlockGroup = -not [string]::IsNullOrWhiteSpace($Script:Config.SignInBlockGroupId)
    try {
        $entraUserId = Get-LOAEntraUserId -UserPrincipalName $UserPrincipalName
        if ($hasBlockGroup) {
            [void](Test-LOABlockGroupMember -UserId $entraUserId)
        }
    } catch {
        throw "Microsoft Graph pre-check failed for ${UserPrincipalName}: $($_.Exception.Message.TrimEnd('.')). No changes were made; check the user exists in Entra ID, the SignInBlockGroupId and your Graph permissions, then rerun Start-UserLOA."
    }
    $managerEmail = if ($managerObj.EmailAddress) { $managerObj.EmailAddress } else { $ManagerUPN }

    # ---- BEFORE snapshot ----
    # Capture and print current state before changes. This is the operator's
    # evidence of what the script found before touching the account.
    $before = Invoke-LOAGetUserStateSnapshot -UserPrincipalName $UserPrincipalName
    Show-UserSummary -Label 'BEFORE - Pre-LOA state' -Snapshot $before
    Show-LOAPreExistingWarnings -Before $before -ManagerUPN $ManagerUPN

    Write-Host "Manager for delegation/OOO: $managerDisplayName <$managerEmail>" -ForegroundColor Yellow
    Write-Host ''

    # 0. Stash original OU for End-UserLOA auto-restore.
    # Store only the parent OU, not the full CN. End uses this to return the
    # user without requiring the operator to remember the original location.
    $existingStash = Get-LOAStashedOU -ADUser $adUser
    $originalParentOU = Get-ParentOU -DistinguishedName $adUser.DistinguishedName

    if (-not $existingStash -and $originalParentOU -eq $Script:Config.LOAOUDistinguishedName) {
        throw 'User is already in the LOA OU with no stashed origin. Investigate, then use End-UserLOA -TargetOU for the return.'
    }

    $shouldWaitForExchangeConvergence = -not $WhatIfPreference
    $expectedOOOState = $null

    try {
    if ($existingStash) {
        Write-Host "  [SKIP] Stash already set: $existingStash" -ForegroundColor Yellow
    } elseif ($PSCmdlet.ShouldProcess($UserPrincipalName, "Stash original OU in $($Script:Config.OUStashAttribute)")) {
        $stashReplace = @{}
        $stashReplace[$Script:Config.OUStashAttribute] = $originalParentOU
        Invoke-LOASetADUser -Identity $adUser.DistinguishedName -Replace $stashReplace -Server $Script:Config.DomainController
        Write-Host "  [OK] Original OU stashed: $originalParentOU" -ForegroundColor Green
    }

    # 1. Block Microsoft 365 sign-in (optional).
    # Runs before the AD disable so a Graph failure stops Start while the
    # account is still untouched.
    if ($hasBlockGroup -and $PSCmdlet.ShouldProcess($UserPrincipalName, 'Add to sign-in block group')) {
        Add-LOASignInBlock -UserPrincipalName $UserPrincipalName -UserId $entraUserId
    }

    # 2. Disable account.
    # Disabling the AD account prevents sign-in while Entra Connect syncs the
    # authoritative on-prem state to Microsoft 365.
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Disable AD account')) {
        Invoke-LOADisableADAccount -Identity $adUser.DistinguishedName -Server $Script:Config.DomainController
        Write-Host '  [OK] AD account disabled' -ForegroundColor Green
    }

    # 3. Revoke sign-in sessions.
    # A failure here stops Start: the user is disabled but not yet moved or
    # delegated, and a rerun picks up from this point.
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Revoke Microsoft 365 sign-in sessions')) {
        Invoke-LOASessionRevoke -UserPrincipalName $UserPrincipalName -UserId $entraUserId
        if (-not $hasBlockGroup) {
            Write-Host '  [WARN] No SignInBlockGroupId configured. The user can sign in to Microsoft 365 again until Entra Connect syncs the AD disable (about 30 minutes by default).' -ForegroundColor Yellow
        }
    }

    # 4. Hide from GAL.
    # This sets the on-prem Exchange attribute that controls GAL visibility in
    # hybrid environments.
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Hide from GAL')) {
        Invoke-LOASetADUser -Identity $adUser.DistinguishedName -Replace @{ msExchHideFromAddressLists = $true } -Server $Script:Config.DomainController
        Write-Host '  [OK] Hidden from GAL' -ForegroundColor Green
    }

    # 5. Move to LOA OU.
    # Refresh $adUser after the move because the distinguishedName changes.
    if ((Get-ParentOU -DistinguishedName $adUser.DistinguishedName) -eq $Script:Config.LOAOUDistinguishedName) {
        Write-Host '  [SKIP] Already in LOA OU' -ForegroundColor Yellow
    } elseif ($PSCmdlet.ShouldProcess($UserPrincipalName, "Move to $($Script:Config.LOAOUDistinguishedName)")) {
        Invoke-LOAMoveADObject -Identity $adUser.DistinguishedName -TargetPath $Script:Config.LOAOUDistinguishedName -Server $Script:Config.DomainController
        Write-Host "  [OK] Moved to $($Script:Config.LOAOUDistinguishedName)" -ForegroundColor Green
        $adUser = Get-LOAUser -UserPrincipalName $UserPrincipalName
    }

    # 6. Delegate mailbox to manager.
    # Permissions are checked before adding so reruns are mostly idempotent and
    # do not create duplicate grant attempts.
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Delegate mailbox to $ManagerUPN")) {
        try {
            if (Test-LOAFullAccessGrant -MailboxUPN $UserPrincipalName -DelegateUPN $ManagerUPN) {
                Write-Host "  [SKIP] FullAccess already granted to $ManagerUPN" -ForegroundColor Yellow
            } else {
                Invoke-LOAAddMailboxPermission -Identity $UserPrincipalName -User $ManagerUPN
                Write-Host "  [OK] FullAccess granted to $ManagerUPN" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [ERR] FullAccess delegation failed: $($_.Exception.Message)" -ForegroundColor Red
        }

        try {
            if (Test-LOASendAsGrant -MailboxUPN $UserPrincipalName -DelegateUPN $ManagerUPN) {
                Write-Host "  [SKIP] SendAs already granted to $ManagerUPN" -ForegroundColor Yellow
            } else {
                Invoke-LOAAddRecipientPermission -Identity $UserPrincipalName -Trustee $ManagerUPN
                Write-Host "  [OK] SendAs granted to $ManagerUPN" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [ERR] SendAs delegation failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # 7. OOO decision.
    # Resolve-OOOAction protects user-scheduled or already-enabled OOO messages
    # from being overwritten unless the operator explicitly uses -ForceOOO.
    switch (Resolve-OOOAction -Snapshot $before -ForceOOO:$ForceOOO) {
        'Set' {
            $expectedOOOState = 'Enabled'
            if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Configure Out-of-Office')) {
                # The same message is used internally and externally; ExternalAudience
                # remains All per the established workflow.
                $oooMessage = @"
Hello,

I am currently on leave. For any urgent matters, please contact my manager $managerDisplayName at $managerEmail.

Regards,
$($before.DisplayName)
"@
                try {
                    Invoke-LOASetMailboxAutoReplyConfiguration -Identity $UserPrincipalName `
                        -AutoReplyState Enabled `
                        -InternalMessage $oooMessage `
                        -ExternalMessage $oooMessage `
                        -ExternalAudience All
                    Write-Host '  [OK] OOO configured (default message)' -ForegroundColor Green
                } catch {
                    Write-Host "  [WARN] OOO setup failed: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        'ManualReview' {
            $context = Get-OOOManualReviewContext -Snapshot $before
            $expectedOOOState = $before.OOOState
            Write-Host "  [ACTION REQUIRED] $context. Verify OOO manually and rerun with -ForceOOO if the LOA default should replace it." -ForegroundColor Yellow
        }
        'Skip' {
            $expectedOOOState = $before.OOOState
            Write-Host '  [WARN] OOO state could not be read; leaving OOO unchanged.' -ForegroundColor Yellow
        }
    }
    } finally {

    # ---- AFTER snapshot ----
    if ($shouldWaitForExchangeConvergence) {
        $after = Wait-LOAUserStateSnapshot `
            -UserPrincipalName $UserPrincipalName `
            -IsSatisfied {
                param($snapshot)

                $hasFullAccess = @($snapshot.FullAccessGrants | Where-Object { Test-LOADelegateIdentityMatch -Identity $_ -DelegateUPN $ManagerUPN }).Count -gt 0
                $hasSendAs = @($snapshot.SendAsGrants | Where-Object { Test-LOADelegateIdentityMatch -Identity $_ -DelegateUPN $ManagerUPN }).Count -gt 0
                $oooMatches = if ($null -eq $expectedOOOState) { $true } else { $snapshot.OOOState -eq $expectedOOOState }

                $hasFullAccess -and $hasSendAs -and $oooMatches
            } `
            -WarningMessage 'Mailbox delegation or OOO state did not converge before the post-LOA summary snapshot.'
    } else {
        $after = Invoke-LOAGetUserStateSnapshot -UserPrincipalName $UserPrincipalName
    }
    Show-UserSummary -Label 'AFTER - Post-LOA state' -Snapshot $after

    # Print the exact End command with the same UPNs used in this run so the
    # return process is easy for a future operator.
    $line = '=' * 60
    Write-Host ''
    Write-Host $line -ForegroundColor Cyan
    Write-Host 'For when the user returns, save this command to the ticket:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "  End-UserLOA -UserPrincipalName $UserPrincipalName -ManagerUPN $ManagerUPN" -ForegroundColor Cyan
    Write-Host ''
    Write-Host $line -ForegroundColor Cyan

    Write-Host ''
    Write-Host 'Copy both blocks above into the ticket.' -ForegroundColor Cyan
    Write-Host ''
    }
}

# ---------------------------------------------------------------------------
# End LOA
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Ends the leave-of-absence workflow for a user.

.DESCRIPTION
    Re-enables the on-premises AD account, restores GAL visibility, moves the
    user back to the stashed or supplied OU, removes manager mailbox access,
    disables OOO, and prints before/after ticket summaries.

.PARAMETER UserPrincipalName
    The UPN of the user returning from leave.

.PARAMETER ManagerUPN
    The manager whose mailbox permissions should be removed during return.

.PARAMETER TargetOU
    Optional override OU for the return move. If omitted, the stashed original
    OU is used.

.PARAMETER ConfigPath
    Path to the config .psd1. Defaults to $env:MANAGE_USERLOA_CONFIG, then
    $env:ProgramData\Manage-UserLOA\config.psd1.

.EXAMPLE
    End-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com' -WhatIf

.EXAMPLE
    End-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com' -TargetOU 'OU=Sales,OU=Corporate,DC=yourdomain,DC=com'
#>
function End-UserLOA {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')][string]$UserPrincipalName,
        [Parameter(Mandatory)][ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')][string]$ManagerUPN,
        [string]$TargetOU,
        [string]$ConfigPath
    )

    Import-LOAConfig -ConfigPath $ConfigPath

    # End needs the same AD and EXO connections as Start because it reverses
    # both directory and mailbox changes.
    Connect-LOAServices

    $adUser = Get-LOAUser -UserPrincipalName $UserPrincipalName
    $stashedOU = Get-LOAStashedOU -ADUser $adUser

    # TargetOU is optional in normal use. The script prefers the stashed original
    # OU, but an operator can override it when a user should return elsewhere.
    if (-not $TargetOU) {
        if (-not $stashedOU) {
            throw "No -TargetOU supplied and no original OU found in $($Script:Config.OUStashAttribute). Supply -TargetOU manually."
        }
        $TargetOU = $stashedOU
    } elseif ($stashedOU -and ($TargetOU -ne $stashedOU)) {
        Write-Host "  [NOTE] TargetOU supplied differs from stashed original OU." -ForegroundColor Yellow
        Write-Host "         Supplied TargetOU: $TargetOU" -ForegroundColor Yellow
        Write-Host "         Stashed OU      : $stashedOU" -ForegroundColor Yellow
    }

    Assert-LOAOrganizationalUnit -DistinguishedName $TargetOU -Purpose 'Return target'

    # ---- BEFORE snapshot ----
    # Capture the LOA state before reversing it. This also gives End a snapshot
    # fallback if Exchange permission tests disagree with the displayed state.
    $before = Invoke-LOAGetUserStateSnapshot -UserPrincipalName $UserPrincipalName
    Show-UserSummary -Label 'BEFORE - Current LOA state' -Snapshot $before

    Write-Host ''

    $shouldWaitForExchangeConvergence = -not $WhatIfPreference

    try {
    # 1. Enable account.
    # Re-enable the AD account first so the user can sign in once sync completes.
    if ($adUser.Enabled -eq $true) {
        Write-Host '  [SKIP] AD account already enabled' -ForegroundColor Yellow
    } elseif ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Enable AD account')) {
        Invoke-LOAEnableADAccount -Identity $adUser.DistinguishedName -Server $Script:Config.DomainController
        Write-Host '  [OK] AD account enabled' -ForegroundColor Green
    }

    # 2. Remove from the sign-in block group (optional).
    if (-not [string]::IsNullOrWhiteSpace($Script:Config.SignInBlockGroupId) -and $PSCmdlet.ShouldProcess($UserPrincipalName, 'Remove from sign-in block group')) {
        Remove-LOASignInBlock -UserPrincipalName $UserPrincipalName
    }

    # 3. Unhide from GAL.
    # Clearing the attribute restores default GAL visibility.
    if (-not $adUser.msExchHideFromAddressLists) {
        Write-Host '  [SKIP] GAL visibility already restored' -ForegroundColor Yellow
    } elseif ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Restore GAL visibility')) {
        Invoke-LOASetADUser -Identity $adUser.DistinguishedName -Clear msExchHideFromAddressLists -Server $Script:Config.DomainController
        Write-Host '  [OK] GAL visibility restored' -ForegroundColor Green
    }

    # 4. Move to target OU.
    # Move back to the stashed or supplied OU, then refresh $adUser because the
    # distinguishedName changes after Move-ADObject.
    $moveCompleted = $false
    if ((Get-ParentOU -DistinguishedName $adUser.DistinguishedName) -eq $TargetOU) {
        Write-Host "  [SKIP] Already in target OU: $TargetOU" -ForegroundColor Yellow
        $moveCompleted = $true
    } elseif ($PSCmdlet.ShouldProcess($UserPrincipalName, "Move to $TargetOU")) {
        Invoke-LOAMoveADObject -Identity $adUser.DistinguishedName -TargetPath $TargetOU -Server $Script:Config.DomainController
        Write-Host "  [OK] Moved to $TargetOU" -ForegroundColor Green
        $adUser = Get-LOAUser -UserPrincipalName $UserPrincipalName
        $moveCompleted = $true
    }

    # Clear the stash only after a successful move so a failed End run can still
    # try again without losing the original OU.
    if ($moveCompleted -and $PSCmdlet.ShouldProcess($UserPrincipalName, "Clear original OU stash in $($Script:Config.OUStashAttribute)")) {
        Invoke-LOASetADUser -Identity $adUser.DistinguishedName -Clear $Script:Config.OUStashAttribute -Server $Script:Config.DomainController
        Write-Host "  [OK] Cleared $($Script:Config.OUStashAttribute)" -ForegroundColor Green
    }

    # 5. Remove mailbox delegation.
    # End removes the manager delegation that Start added. It uses full ACL reads
    # and the BEFORE snapshot fallback because EXO filtered permission lookups
    # can lag behind the visible ACL.
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Remove delegation from $ManagerUPN")) {
        try {
            $fullAccessIdentities = @(Get-LOAFullAccessGrantIdentities -MailboxUPN $UserPrincipalName -DelegateUPN $ManagerUPN)
            $fullAccessInBeforeSnapshot = @($before.FullAccessGrants | Where-Object { Test-LOADelegateIdentityMatch -Identity $_ -DelegateUPN $ManagerUPN }).Count -gt 0
            if ($fullAccessIdentities.Count -eq 0 -and $fullAccessInBeforeSnapshot) {
                Write-Host '  [WARN] FullAccess was visible in the BEFORE snapshot but not in the live permission test; attempting removal anyway.' -ForegroundColor Yellow
                $fullAccessIdentities = @($ManagerUPN)
            }

            if ($fullAccessIdentities.Count -gt 0) {
                foreach ($fullAccessIdentity in $fullAccessIdentities) {
                    Invoke-LOARemoveMailboxPermission -Identity $UserPrincipalName -User $fullAccessIdentity
                    Write-Host "  [OK] FullAccess removed from $fullAccessIdentity" -ForegroundColor Green
                }
            } else {
                Write-Host "  [SKIP] FullAccess was not granted to $ManagerUPN" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [ERR] FullAccess removal failed: $($_.Exception.Message)" -ForegroundColor Red
        }

        try {
            $sendAsIdentities = @(Get-LOASendAsGrantIdentities -MailboxUPN $UserPrincipalName -DelegateUPN $ManagerUPN)
            $sendAsInBeforeSnapshot = @($before.SendAsGrants | Where-Object { Test-LOADelegateIdentityMatch -Identity $_ -DelegateUPN $ManagerUPN }).Count -gt 0
            if ($sendAsIdentities.Count -eq 0 -and $sendAsInBeforeSnapshot) {
                Write-Host '  [WARN] SendAs was visible in the BEFORE snapshot but not in the live permission test; attempting removal anyway.' -ForegroundColor Yellow
                $sendAsIdentities = @($ManagerUPN)
            }

            if ($sendAsIdentities.Count -gt 0) {
                foreach ($sendAsIdentity in $sendAsIdentities) {
                    Invoke-LOARemoveRecipientPermission -Identity $UserPrincipalName -Trustee $sendAsIdentity
                    Write-Host "  [OK] SendAs removed from $sendAsIdentity" -ForegroundColor Green
                }
            } else {
                Write-Host "  [SKIP] SendAs was not granted to $ManagerUPN" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [ERR] SendAs removal failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # 6. Disable OOO.
    # Unconditional: clears both the LOA auto-reply and any user-managed OOO that may
    # be active. Confirm with the returning user if they had a personal OOO set.
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Disable Out-of-Office')) {
        try {
            Invoke-LOASetMailboxAutoReplyConfiguration -Identity $UserPrincipalName -DisabledState Disabled
            Write-Host '  [OK] OOO disabled (unconditional - also clears any active user-managed OOO; verify with the returning user if needed)' -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] OOO disable failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    } finally {

    # ---- AFTER snapshot ----
    if ($shouldWaitForExchangeConvergence) {
        $after = Wait-LOAUserStateSnapshot `
            -UserPrincipalName $UserPrincipalName `
            -IsSatisfied {
                param($snapshot)

                $hasFullAccess = @($snapshot.FullAccessGrants | Where-Object { Test-LOADelegateIdentityMatch -Identity $_ -DelegateUPN $ManagerUPN }).Count -gt 0
                $hasSendAs = @($snapshot.SendAsGrants | Where-Object { Test-LOADelegateIdentityMatch -Identity $_ -DelegateUPN $ManagerUPN }).Count -gt 0

                (-not $hasFullAccess) -and (-not $hasSendAs) -and ($snapshot.OOOState -eq 'Disabled')
            } `
            -WarningMessage 'Mailbox delegation removal or OOO disablement did not converge before the restored-state summary snapshot.'
    } else {
        $after = Invoke-LOAGetUserStateSnapshot -UserPrincipalName $UserPrincipalName
    }
    Show-UserSummary -Label 'AFTER - Restored state' -Snapshot $after

    Write-Host ''
    Write-Host 'Copy both blocks above into the ticket.' -ForegroundColor Cyan
    Write-Host ''
    }
}

Export-ModuleMember -Function Start-UserLOA, End-UserLOA
