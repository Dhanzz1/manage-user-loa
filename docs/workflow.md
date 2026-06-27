# Workflow

## Start-UserLOA

`Start-UserLOA` is the operator-driven entry point for placing a user on leave.

### Validation

- Confirms the configured domain controller is reachable.
- Loads the Active Directory and Exchange Online modules.
- Reuses an existing Exchange Online session when possible.
- Looks up the user and validates the configured LOA OU or container.
- Resolves the manager either from the supplied `ManagerUPN` or the user's AD manager.

### State capture

- Captures a before snapshot of AD state, GAL visibility, mailbox delegation, and OOO state.
- Prints the snapshot in a ticket-friendly format.
- Warns when pre-existing GAL hiding, mailbox permissions, or other state could make the return workflow non-symmetric.

### AD and Exchange changes

- Stashes the original parent OU in the configured AD attribute.
- Disables the AD account.
- Hides the user from the GAL.
- Moves the user to the configured LOA OU.
- Grants the manager `FullAccess` and `SendAs` when not already present.
- Applies the default OOO message when the OOO safety logic allows it.

### Optional SaaS behavior

- Runs any enabled SaaS connector patterns after the AD and Exchange actions.
- Connector failures are reported but do not stop the core LOA workflow.

### Final output

- Captures an after snapshot.
- Prints a ready-to-copy `End-UserLOA` command for the ticket.
- Keeps the ticket summary as the intended operator record.

## End-UserLOA

`End-UserLOA` is the return workflow for restoring the user's normal state.

### Validation

- Loads the same AD and Exchange dependencies as the Start workflow.
- Reads the stashed OU from the configured attribute unless a `TargetOU` override is supplied.
- Validates the return OU or container before moving the user.

### State capture

- Captures a before snapshot of the user's current LOA state.
- Uses that snapshot as a fallback when live Exchange permission reads lag.

### AD and Exchange changes

- Re-enables the AD account.
- Restores GAL visibility.
- Moves the user back to the stashed or supplied OU.
- Clears the stashed OU only after the move succeeds.
- Removes the manager's `FullAccess` and `SendAs`.
- Disables OOO.

### Optional SaaS behavior

- Runs any enabled SaaS reactivation connector patterns after the core return workflow.
- Connector failures are reported without blocking the AD or Exchange restoration path.

### Final output

- Captures an after snapshot.
- Prints the restored state in a ticket-friendly block.

## Operational notes

- Both public commands support `-WhatIf` and `-Confirm`.
- Both public commands use `ConfirmImpact = 'High'` because they make user-impacting identity changes.
- The workflow is reversible for the standard LOA path, but it does not promise perfect restoration of every pre-existing mailbox, GAL, or SaaS state.
