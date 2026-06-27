# Changelog

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
