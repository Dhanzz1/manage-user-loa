# Tests

This repository includes offline Pester suites for the public module. None of them needs a live Active Directory, Exchange Online or Graph connection.

## Scope

- Helper and metadata tests cover string handling, decision logic and confirmation behaviour.
- Config tests load real `.psd1` files from Pester's `TestDrive:`.
- The fake tenant ([Fakes/FakeTenant.ps1](Fakes/FakeTenant.ps1)) holds sample AD, Exchange Online and Entra state in `$global:LOAFake` and mocks every `Invoke-LOA*` wrapper to read and change it. Fake tenant tests run the real Start / End code and assert on the resulting state. `$global:LOAFake.Faults` injects failures into named operations.
- v1.1 and later are validated only this way; see [docs/testing.md](../docs/testing.md).

## Running tests

The suites target Pester 3.4.0, the version that ships with Windows. From the repository root:

```powershell
powershell.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Path tests"
```

## Test inventory

- [Manage-UserLOA.Tests.ps1](Manage-UserLOA.Tests.ps1): helper and metadata assertions
- [Manage-UserLOA.Workflow.Tests.ps1](Manage-UserLOA.Workflow.Tests.ps1): mocked Start / End workflow orchestration assertions
- [Manage-UserLOA.Config.Tests.ps1](Manage-UserLOA.Config.Tests.ps1): config file loading and validation
- [Manage-UserLOA.Graph.Tests.ps1](Manage-UserLOA.Graph.Tests.ps1): Graph scopes, session reuse and revoke results
- [Manage-UserLOA.FakeTenant.Tests.ps1](Manage-UserLOA.FakeTenant.Tests.ps1): Start / End against the fake tenant
