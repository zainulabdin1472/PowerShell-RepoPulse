@{
    RootModule           = 'RepoHealth.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'cebd0ce2-d8e5-4e3d-b551-330e6fb7e898'
    Author               = 'Zain Ul Abdin'
    Copyright            = '(c) 2026 Zain Ul Abdin. All rights reserved.'
    Description          = 'Reports stale GitHub branches and Dependabot dependency alerts.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'Get-RepoStaleBranch'
        'Get-RepoDependencyStatus'
        'New-RepoHealthReport'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('GitHub', 'Repository', 'Health', 'PowerShell')
            ProjectUri = 'https://github.com/zainulabdin1472/PowerShell-RepoPulse'
        }
    }
}
