# Workflow

## Start-UserLOA

`Start-UserLOA` is the operator-driven entry point for placing a user on leave.

### Validation

- Confirms the configured domain controller is reachable.
- Loads and validates the config file before connecting to anything.
- Loads the Active Directory, Exchange Online and Microsoft Graph modules.
- Reuses an existing Exchange Online session, and an existing Graph session that already has the needed scopes.
- Looks up the user and validates the configured LOA OU or container.
- Resolves the manager either from the supplied `ManagerUPN` or the user's AD manager.

### State capture

- Captures a before snapshot of AD state, GAL visibility, mailbox delegation, and OOO state.
- Prints the snapshot in a ticket-friendly format.
- Warns when pre-existing GAL hiding, mailbox permissions, or other state could make the return workflow non-symmetric.

### AD and Exchange changes

- Stashes the original parent OU in the configured AD attribute.
- Adds the user to the sign-in block group when `SignInBlockGroupId` is set. A failure stops Start before the account is touched.
- Disables the AD account.
- Revokes the user's Microsoft 365 sign-in sessions. A failure stops Start with the user disabled but not moved or delegated; rerun after fixing the cause. Without a block group, a warning notes the user can sign in again until Entra Connect syncs the disable.
- Hides the user from the GAL.
- Moves the user to the configured LOA OU.
- Grants the manager `FullAccess` and `SendAs` when not already present.
- Applies the default OOO message when the OOO safety logic allows it.

### Final output

- Captures an after snapshot.
- Prints a ready-to-copy `End-UserLOA` command for the ticket.
- Keeps the ticket summary as the intended operator record.

## End-UserLOA

`End-UserLOA` is the return workflow for restoring the user's normal state.

### Validation

- Loads and validates the config, then the same AD, Exchange and Graph dependencies as the Start workflow.
- Reads the stashed OU from the configured attribute unless a `TargetOU` override is supplied.
- Validates the return OU or container before moving the user.

### State capture

- Captures a before snapshot of the user's current LOA state.
- Uses that snapshot as a fallback when live Exchange permission reads lag.

### AD and Exchange changes

- Re-enables the AD account.
- Removes the user from the sign-in block group when configured. A failure is reported for manual follow-up and does not stop End.
- Restores GAL visibility.
- Moves the user back to the stashed or supplied OU.
- Clears the stashed OU only after the move succeeds.
- Removes the manager's `FullAccess` and `SendAs`.
- Disables OOO.

### Final output

- Captures an after snapshot.
- Prints the restored state in a ticket-friendly block.

## Operational notes

- Both public commands support `-WhatIf` and `-Confirm`.
- Both public commands use `ConfirmImpact = 'High'` because they make user-impacting identity changes.
- The workflow is reversible for the standard LOA path, but it does not promise perfect restoration of every pre-existing mailbox or GAL state.
