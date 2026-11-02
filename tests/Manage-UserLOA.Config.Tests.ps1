function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message`nExpected: $Expected`nActual: $Actual"
    }
}

function Get-ThrownMessage {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock)

    try {
        & $ScriptBlock
    } catch {
        return $_.Exception.Message
    }
    $null
}

$modulePath = Join-Path $PSScriptRoot '..\src\Manage-UserLOA\Manage-UserLOA.psm1'
$module = Import-Module $modulePath -Force -PassThru

$validConfig = @'
@{
    LOAOUDistinguishedName = 'OU=Users on Temporary Leave,OU=Corporate,DC=yourdomain,DC=com'
    DomainController       = 'DC01.yourdomain.com'
    OUStashAttribute       = 'extensionAttribute10'
}
'@

Describe 'Manage-UserLOA config file' {
    function Write-TestConfig {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Content
        )

        $path = Join-Path $TestDrive $Name
        Set-Content -Path $path -Value $Content
        $path
    }

    function Invoke-ImportLOAConfig {
        param([string]$Path)

        & $module { param($p) Import-LOAConfig -ConfigPath $p } $Path
    }

    It 'resolves -ConfigPath first' {
        $saved = $env:MANAGE_USERLOA_CONFIG
        try {
            $env:MANAGE_USERLOA_CONFIG = 'C:\from-env.psd1'
            $actual = & $module { Resolve-LOAConfigPath -ConfigPath 'C:\explicit.psd1' }
            Assert-Equal -Actual $actual -Expected 'C:\explicit.psd1' -Message '-ConfigPath should win over the environment variable.'
        } finally {
            $env:MANAGE_USERLOA_CONFIG = $saved
        }
    }

    It 'falls back to MANAGE_USERLOA_CONFIG' {
        $saved = $env:MANAGE_USERLOA_CONFIG
        try {
            $env:MANAGE_USERLOA_CONFIG = 'C:\from-env.psd1'
            $actual = & $module { Resolve-LOAConfigPath -ConfigPath '' }
            Assert-Equal -Actual $actual -Expected 'C:\from-env.psd1' -Message 'The environment variable should be used when -ConfigPath is empty.'
        } finally {
            $env:MANAGE_USERLOA_CONFIG = $saved
        }
    }

    It 'falls back to ProgramData' {
        $saved = $env:MANAGE_USERLOA_CONFIG
        try {
            $env:MANAGE_USERLOA_CONFIG = $null
            $actual = & $module { Resolve-LOAConfigPath -ConfigPath '' }
            Assert-Equal -Actual $actual -Expected (Join-Path $env:ProgramData 'Manage-UserLOA\config.psd1') -Message 'ProgramData should be the final fallback.'
        } finally {
            $env:MANAGE_USERLOA_CONFIG = $saved
        }
    }

    It 'loads a valid config into Script:Config' {
        Invoke-ImportLOAConfig -Path (Write-TestConfig -Name 'valid.psd1' -Content $validConfig)

        $actual = & $module { $Script:Config.DomainController }
        Assert-Equal -Actual $actual -Expected 'DC01.yourdomain.com' -Message 'The file values should be loaded into Script:Config.'
    }

    It 'lists every missing required key at once' {
        $path = Write-TestConfig -Name 'empty.psd1' -Content '@{}'

        $message = Get-ThrownMessage { Invoke-ImportLOAConfig -Path $path }

        Assert-Equal -Actual ($message -like "Config file '$path' is invalid:*") -Expected $true -Message "Error should name the file. Got: $message"
        foreach ($key in @('LOAOUDistinguishedName', 'DomainController', 'OUStashAttribute')) {
            Assert-Equal -Actual ($message -like "*Missing required key '$key'*") -Expected $true -Message "Error should list $key. Got: $message"
        }
    }

    It 'rejects an OUStashAttribute outside 1-15' {
        $path = Write-TestConfig -Name 'stash16.psd1' -Content ($validConfig -replace 'extensionAttribute10', 'extensionAttribute16')

        $message = Get-ThrownMessage { Invoke-ImportLOAConfig -Path $path }

        Assert-Equal -Actual ($message -like "*OUStashAttribute must be extensionAttribute1 to extensionAttribute15 (found 'extensionAttribute16')*") -Expected $true -Message "Got: $message"
    }

    It 'rejects an OUStashAttribute that is an array' {
        $path = Write-TestConfig -Name 'stasharray.psd1' -Content ($validConfig -replace "'extensionAttribute10'", "@('extensionAttribute10')")

        $message = Get-ThrownMessage { Invoke-ImportLOAConfig -Path $path }

        Assert-Equal -Actual ($message -like '*OUStashAttribute must be extensionAttribute1 to extensionAttribute15*') -Expected $true -Message "Got: $message"
    }

    It 'rejects a non-DN LOA OU' {
        $path = Write-TestConfig -Name 'badou.psd1' -Content ($validConfig -replace "'OU=Users on Temporary Leave,OU=Corporate,DC=yourdomain,DC=com'", "'Users on Temporary Leave'")

        $message = Get-ThrownMessage { Invoke-ImportLOAConfig -Path $path }

        Assert-Equal -Actual ($message -like "*LOAOUDistinguishedName must be a distinguished name starting with OU= or CN= (found 'Users on Temporary Leave')*") -Expected $true -Message "Got: $message"
    }

    It 'names the file when the psd1 has a syntax error' {
        $path = Write-TestConfig -Name 'broken.psd1' -Content '@{ DomainController = '

        $message = Get-ThrownMessage { Invoke-ImportLOAConfig -Path $path }

        Assert-Equal -Actual ($message -like "Config file '$path' could not be read:*") -Expected $true -Message "Got: $message"
    }

    It 'names all three sources when no file exists' {
        $path = Join-Path $TestDrive 'missing.psd1'

        $message = Get-ThrownMessage { Invoke-ImportLOAConfig -Path $path }

        Assert-Equal -Actual ($message -like "Config file not found: $path.*") -Expected $true -Message "Got: $message"
        Assert-Equal -Actual ($message -like '*-ConfigPath*MANAGE_USERLOA_CONFIG*') -Expected $true -Message "Got: $message"
        Assert-Equal -Actual ($message -like "*$(Join-Path $env:ProgramData 'Manage-UserLOA\config.psd1')*") -Expected $true -Message "Got: $message"
    }

    It 'warns about unknown keys such as GoogleEnabled' {
        $path = Write-TestConfig -Name 'unknown.psd1' -Content ($validConfig -replace '\}\s*$', "    GoogleEnabled = `$false`n}")
        InModuleScope Manage-UserLOA {
            Mock Write-Warning {}
        }

        Invoke-ImportLOAConfig -Path $path

        Assert-MockCalled Write-Warning -ModuleName Manage-UserLOA -Times 1 -Exactly -Scope It -ParameterFilter { $Message -like "*Unknown config key 'GoogleEnabled'*" }
    }

    It 'Start-UserLOA validates config before connecting' {
        $path = Write-TestConfig -Name 'invalid-start.psd1' -Content '@{}'
        InModuleScope Manage-UserLOA {
            Mock Connect-LOAServices {}
        }

        $message = Get-ThrownMessage { Start-UserLOA -UserPrincipalName 'jane.doe@yourdomain.com' -ConfigPath $path -Confirm:$false }

        Assert-Equal -Actual ($message -like "Config file '*' is invalid:*") -Expected $true -Message "Got: $message"
        Assert-MockCalled Connect-LOAServices -ModuleName Manage-UserLOA -Times 0 -Exactly -Scope It
    }
}
