# Testing Notes

## Current status

- v1.0 was tested against a production AD and Exchange Online environment.
- v1.1 and later are validated against a fake tenant in the test suite: sample AD, Exchange Online and Entra state that the mocked wrappers read and change. Nothing new in v1.1 has been run against a live tenant.
- Run the suite with Windows PowerShell 5.1 and Pester 3.4.0:

```powershell
powershell.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Path tests"
```

## Manual test matrix

These checks are still manual and have not been revalidated in a live lab or tenant from this published workspace.

| Test case | Expected result |
|---|---|
| Start LOA for test user | Account disabled, moved to LOA OU, hidden from GAL |
| End LOA using stashed OU | Account enabled, moved back, GAL restored |
| End LOA with supplied `TargetOU` | Account moved to supplied OU |
| Manager mailbox delegation added | Manager receives expected mailbox access |
| Delegation removed on return | Manager access removed |
| OOO configured when disabled | Default OOO applied |
| Existing enabled or scheduled OOO | Manual review warning shown |
| Invalid user | Script exits safely with clear error |
| Invalid target OU | Script exits before destructive changes |
| Invalid or missing config file | Command stops before connecting, listing every problem |
| Start with `SignInBlockGroupId` set | User added to the block group before the disable; sign-in blocked at once |
| Start without `SignInBlockGroupId` | Sessions revoked; sync-delay warning shown |
| Revoke fails | Start stops with user disabled, not moved or delegated; rerun completes |
| End with `SignInBlockGroupId` set | User removed from the block group |

## Offline test scope

Four Pester files run without a live Active Directory, Exchange Online or Graph connection.

The helper-focused Pester suite in [tests/Manage-UserLOA.Tests.ps1](../tests/Manage-UserLOA.Tests.ps1) covers deterministic logic only:

- confirmation metadata on the public commands
- parent OU extraction
- summary formatting
- delegate identity matching
- OOO decision logic
- OOO manual review text
- manifest version
- removal of the old Google / REST connectors

The mocked workflow suite in [tests/Manage-UserLOA.Workflow.Tests.ps1](../tests/Manage-UserLOA.Workflow.Tests.ps1) covers:

- `Start-UserLOA` happy-path orchestration
- `End-UserLOA` happy-path orchestration
- `-WhatIf` protection for destructive workflow actions
- guarded failure when `End-UserLOA` has neither a supplied nor stashed return OU

The config suite in [tests/Manage-UserLOA.Config.Tests.ps1](../tests/Manage-UserLOA.Config.Tests.ps1) uses real `.psd1` files and covers path resolution, every validation rule, syntax errors, missing files and unknown-key warnings.

The Graph suite in [tests/Manage-UserLOA.Graph.Tests.ps1](../tests/Manage-UserLOA.Graph.Tests.ps1) covers scope selection, session reuse and the accepted revoke result shapes.

The fake tenant suite in [tests/Manage-UserLOA.FakeTenant.Tests.ps1](../tests/Manage-UserLOA.FakeTenant.Tests.ps1) runs the real Start / End code against [tests/Fakes/FakeTenant.ps1](../tests/Fakes/FakeTenant.ps1) and checks the resulting state: the Start / End round trip, `-WhatIf`, OOO protection, the block / disable / revoke order, failure stops and safe reruns.

## Recommended live validation order

1. Validate config values in a lab or test tenant.
2. Run `Start-UserLOA ... -WhatIf`.
3. Run `End-UserLOA ... -WhatIf`.
4. Execute against a non-production test user.
5. Verify AD state, mailbox permissions, and OOO state.
