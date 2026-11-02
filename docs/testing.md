# Testing Notes

## Current status

- Offline helper, metadata, and mocked workflow orchestration tests passed with Pester on June 27, 2026.
- Mocked workflow orchestration tests cover the module's AD and Exchange command flow without requiring a live tenant.
- Live AD and Exchange Online validation has not been run in this workspace and remains manual.

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
| Existing or soon-scheduled OOO | Manual review warning shown |
| Invalid user | Script exits safely with clear error |
| Invalid target OU | Script exits before destructive changes |

## Offline test scope

The helper-focused Pester suite in [tests/Manage-UserLOA.Tests.ps1](../tests/Manage-UserLOA.Tests.ps1) covers deterministic logic only:

- confirmation metadata on the public commands
- parent OU extraction
- summary formatting
- delegate identity matching
- OOO decision logic
- OOO manual review text

The mocked workflow suite in [tests/Manage-UserLOA.Workflow.Tests.ps1](../tests/Manage-UserLOA.Workflow.Tests.ps1) covers:

- `Start-UserLOA` happy-path orchestration
- `End-UserLOA` happy-path orchestration
- `-WhatIf` protection for destructive workflow actions
- guarded failure when `End-UserLOA` has neither a supplied nor stashed return OU

## Recommended live validation order

1. Validate config values in a lab or test tenant.
2. Run `Start-UserLOA ... -WhatIf`.
3. Run `End-UserLOA ... -WhatIf`.
4. Execute against a non-production test user.
5. Verify AD state, mailbox permissions, and OOO state.
