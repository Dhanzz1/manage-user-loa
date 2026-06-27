Import-Module "$PSScriptRoot\..\src\Manage-UserLOA\Manage-UserLOA.psd1"

# Start with -WhatIf to validate the return path before making changes.
End-UserLOA `
    -UserPrincipalName 'jane.doe@yourdomain.com' `
    -ManagerUPN 'john.smith@yourdomain.com' `
    -WhatIf

# Example using an explicit return OU instead of the stashed original OU.
End-UserLOA `
    -UserPrincipalName 'jane.doe@yourdomain.com' `
    -ManagerUPN 'john.smith@yourdomain.com' `
    -TargetOU 'OU=Sales,OU=Corporate,DC=yourdomain,DC=com' `
    -WhatIf
