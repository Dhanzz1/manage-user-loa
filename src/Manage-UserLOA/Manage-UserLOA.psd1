@{
    RootModule        = 'Manage-UserLOA.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = 'cf970e8f-7d66-467f-9efd-a2e031370745'
    Author            = 'Dhanush'
    Description       = 'Leave of absence workflow module for hybrid Active Directory and Microsoft 365 environments.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Start-UserLOA'
        'End-UserLOA'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
