# Operations Runbook

## Purpose

This runbook is for operators executing the leave-of-absence workflow in a hybrid Active Directory and Microsoft 365 environment. Use it to run `Start-UserLOA` and `End-UserLOA` safely, capture the ticket evidence, and recognize the cases that still need manual review.

## Scope

- Standard LOA start and return workflow
- Hybrid AD and Exchange Online environments

## Prerequisites

- PowerShell 5.1 or later
- `ActiveDirectory` module available
- `ExchangeOnlineManagement` module available
- A valid config `.psd1` (see the README Configuration section)
- AD rights to update the target user and move the object between OUs
- Exchange Online rights to manage mailbox delegation and automatic replies
- A non-production user for first-time validation

## Pre-Run Safety Checks

1. Confirm the target user is the correct person and not already mid-way through another identity change.
2. Review the config file for:
   - `LOAOUDistinguishedName`
   - `DomainController`
   - `OUStashAttribute`
3. Confirm the manager UPN is correct if you plan to override the AD manager.
4. Run the command with `-WhatIf` first.
5. Tell the ticket that mailbox delegation and OOO may need manual review if the user already has custom settings.

## Start-UserLOA

Run:

```powershell
Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com' -WhatIf
```

Then rerun without `-WhatIf` after review.

Expected workflow:

- original OU is stashed
- user is added to the sign-in block group, if configured
- AD account is disabled
- Microsoft 365 sign-in sessions are revoked
- GAL visibility is hidden
- user is moved into the LOA OU
- mailbox `FullAccess` and `SendAs` are granted to the manager when not already present
- OOO is set or flagged for manual review

Capture in the ticket:

- the BEFORE summary block
- the AFTER summary block
- the generated `End-UserLOA` command
- any warning or manual-review message shown during the run

## End-UserLOA

Run:

```powershell
End-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ManagerUPN 'john.smith@yourdomain.com' -WhatIf
```

Then rerun without `-WhatIf` after review.

Expected workflow:

- AD account is enabled
- user is removed from the sign-in block group, if configured
- GAL visibility is restored
- user is moved back to the stashed or supplied target OU
- stash attribute is cleared only after a successful move
- mailbox delegation is removed
- OOO is disabled

Capture in the ticket:

- the BEFORE summary block
- the AFTER summary block
- any fallback warning about delegation visibility or manual follow-up

## Common Failure Points

- `No manager set on user and no -ManagerUPN provided`
  - supply `-ManagerUPN` explicitly or fix the AD manager attribute first
- `No -TargetOU supplied and no original OU found`
  - investigate the missing stash and rerun with `-TargetOU`
- target OU validation failure
  - confirm the OU path and verify the configured domain controller can resolve it
- EXO delegation or OOO warnings
  - core AD work may still succeed; review the warning and validate manually in Exchange
- `Microsoft Graph pre-check failed`
  - nothing was changed; confirm the user is synced to Entra ID, `SignInBlockGroupId` is the group's object ID, and the operator has the Graph scopes, then rerun Start
- `Sign-in block group add failed`
  - nothing after the OU stash was changed; check the Graph permissions and the group ID, then rerun Start
- `Session revoke failed`
  - the account is disabled but not moved or delegated; fix the cause and rerun Start, which continues from here
- `Sign-in block group removal failed` on End
  - remove the user from the group by hand in Entra
- user already in the LOA OU with no stashed origin
  - stop and investigate before trying to force a normal return flow

## Manual Review Triggers

- OOO is already enabled or already scheduled
- mailbox delegation was already present before LOA started
- GAL hiding was already set before LOA started
- target return OU is intentionally different from the stashed OU
