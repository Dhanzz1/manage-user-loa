Import-Module "$PSScriptRoot\..\src\Manage-UserLOA\Manage-UserLOA.psd1"

# Start with -WhatIf to validate the planned changes before touching AD or Exchange.
Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -WhatIf

# Example with an explicit manager override and forced OOO replacement.
# Remove -WhatIf only after validating the config and expected impact.
Start-UserLOA `
    -UserPrincipalName 'jane.doe@yourdomain.com' `
    -ManagerUPN 'john.smith@yourdomain.com' `
    -ForceOOO `
    -WhatIf
