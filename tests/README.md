# Tests

This repository includes two offline Pester layers for the public module: deterministic helper tests and mocked workflow orchestration tests.

## Scope

- Helper and metadata tests are intended to run without a live Active Directory or Exchange Online connection.
- Mocked workflow tests validate the AD / Exchange orchestration path without requiring a live tenant.
- Together, the offline suites validate internal string handling, decision logic, confirmation behavior, and the main Start / End workflow command flow.
- Live workflow validation for AD, Exchange Online, and optional SaaS integrations remains manual and should be tracked in [docs/testing.md](../docs/testing.md).

## Running tests

If Pester is available:

```powershell
Invoke-Pester -Path .\tests\Manage-UserLOA.Tests.ps1
Invoke-Pester -Path .\tests\Manage-UserLOA.Workflow.Tests.ps1
```

If Pester is not installed, the repo still includes parser and manifest checks, but the helper test suite cannot be executed until Pester is added to your PowerShell environment.

## Test inventory

- [Manage-UserLOA.Tests.ps1](Manage-UserLOA.Tests.ps1): helper and metadata assertions
- [Manage-UserLOA.Workflow.Tests.ps1](Manage-UserLOA.Workflow.Tests.ps1): mocked Start / End workflow orchestration assertions
