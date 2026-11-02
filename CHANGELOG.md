# Changelog

## v1.1.0 - 2026-11-02

Breaking changes:
- Removed the Google Workspace and Generic REST connector patterns and their config keys.
- Removed `OOOSchedulingThreshold`. Start never overwrites an enabled or scheduled OOO unless `-ForceOOO` is supplied.
- Config moved out of the module into a `.psd1` file. Editing `$Script:Config` in `Manage-UserLOA.psm1` no longer works; copy `examples/config.example.psd1` instead.

Added:
- `-ConfigPath` on `Start-UserLOA` and `End-UserLOA`, with `MANAGE_USERLOA_CONFIG` and `$env:ProgramData\Manage-UserLOA\config.psd1` as fallbacks.
- Config validation that reports every problem at once and warns about unknown keys.
- Delegated Microsoft Graph connection that reuses an existing session with the needed scopes.
- Session revoke after the AD disable. A revoke failure stops Start with the user disabled but not moved or delegated.
- Optional `SignInBlockGroupId`: Start adds the user to a Conditional Access block group before the disable, End removes them. The value must be the group's object ID.
- Graph pre-check: Start resolves the user in Entra ID, and reads the block group when set, before making any change.
- Fake tenant test harness. Workflow tests now run the real Start / End logic against sample AD, Exchange and Entra state.

Unchanged: `-ManagerUPN` behaviour on both commands.

## v1.0.1 - 2026-06-27
- Removed Okta connector (IdP, redundant with AD as the identity authority in a hybrid environment).
- Added `-not $_.Deny` filter to `Get-UserStateSnapshot` FullAccess block, making snapshot output consistent with the grant-checking helpers.
- Made the helper test suite compatible with older and newer Pester installs.
- Trimmed `$managerProps` in `Start-UserLOA` to only the properties the manager object actually uses.
- `End-UserLOA` OOO success message now surfaces that the disable is unconditional so operators can confirm with the returning user.
- Removed `RequiredModules` from the manifest; `Connect-LOAServices` already handles dependency loading with clear errors.

## v1.0.0 - 2026-06-16
- Initial release.
- Added `Start-UserLOA` and `End-UserLOA` workflows.
- Added AD disable/enable, OU movement, GAL visibility, mailbox delegation, OOO handling, and optional SaaS connector patterns.
- Added README, examples, tests, testing notes, and security guidance.
