Import-Module "$PSScriptRoot\..\src\Manage-UserLOA\Manage-UserLOA.psd1"

# Start with -WhatIf to validate the planned changes before touching AD or Exchange.
# Without -ConfigPath the module reads MANAGE_USERLOA_CONFIG, then
# $env:ProgramData\Manage-UserLOA\config.psd1.
Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -WhatIf

# Example with an explicit config file.
Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ConfigPath "$PSScriptRoot\config.local.psd1" -WhatIf

# Example with an explicit manager override and forced OOO replacement.
# Remove -WhatIf only after validating the config and expected impact.
Start-UserLOA `
    -UserPrincipalName 'jane.doe@yourdomain.com' `
    -ManagerUPN 'john.smith@yourdomain.com' `
    -ForceOOO `
    -WhatIf
