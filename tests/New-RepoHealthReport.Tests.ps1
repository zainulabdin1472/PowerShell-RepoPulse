BeforeAll {
    $script:moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\src\RepoHealth\RepoHealth.psd1'
    Import-Module -Name $script:moduleManifest -Force
}

Describe 'New-RepoHealthReport' {
    BeforeEach {
        Mock Invoke-RepoHealthGitHubApi -ModuleName RepoHealth -MockWith {
            throw 'GitHub API should not be called by New-RepoHealthReport.'
        }
        Mock Get-RepoStaleBranch -ModuleName RepoHealth -MockWith {
            param(
                [string] $Owner,
                [string] $Repository,
                [int] $OlderThanDays
            )

            return [pscustomobject]@{
                Branch       = 'feature/old'
                Sha          = 'abc123'
                LastCommitAt = [datetimeoffset]'2024-06-01T00:00:00Z'
                AgeDays      = 100
                IsDefault    = $false
                HtmlUrl      = 'https://github.com/octo/widgets/tree/feature/old'
            }
        }
        Mock Get-RepoDependencyStatus -ModuleName RepoHealth -MockWith {
            param(
                [string] $Owner,
                [string] $Repository,
                [string] $State
            )

            return [pscustomobject]@{
                AlertNumber  = 4
                PackageName  = 'lodash'
                Ecosystem    = 'npm'
                ManifestPath = 'package.json'
                Severity     = 'high'
                State        = 'open'
                Summary      = "Prototype`npollution | now"
                HtmlUrl      = 'https://github.com/octo/widgets/security/dependabot/4'
            }
        }
    }

    It 'has comment-based help' {
        $help = Get-Help -Name New-RepoHealthReport
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.examples.example.Count | Should -BeGreaterOrEqual 1
    }

    It 'returns Markdown for stale branches and dependency alerts' {
        $markdown = New-RepoHealthReport -Owner 'octo' -Repository 'widgets' -OlderThanDays 45 -DependencyState 'dismissed'

        $markdown | Should -Match '# Repo health: octo/widgets'
        $markdown | Should -Match 'Generated: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z'
        $markdown | Should -Match 'more than 45 days old'
        $markdown | Should -Match 'feature/old'
        $markdown | Should -Match '2024-06-01T00:00:00Z'
        $markdown.Contains('| No |') | Should -BeTrue
        $markdown | Should -Match "Dependabot alerts with state 'dismissed'"
        $markdown | Should -Match 'lodash'
        $markdown.Contains('Prototype pollution \| now') | Should -BeTrue
        Should -Invoke -CommandName Invoke-RepoHealthGitHubApi -ModuleName RepoHealth -Times 0
        Assert-MockCalled -CommandName Get-RepoStaleBranch -ModuleName RepoHealth -Times 1 -ParameterFilter {
            $Owner -eq 'octo' -and $Repository -eq 'widgets' -and $OlderThanDays -eq 45
        }
        Assert-MockCalled -CommandName Get-RepoDependencyStatus -ModuleName RepoHealth -Times 1 -ParameterFilter {
            $Owner -eq 'octo' -and $Repository -eq 'widgets' -and $State -eq 'dismissed'
        }
    }

    It 'writes the same Markdown to OutputPath and creates missing folders' {
        $path = Join-Path -Path $TestDrive -ChildPath 'out\health.md'
        $markdown = New-RepoHealthReport -Owner 'octo' -Repository 'widgets' -OutputPath $path
        $written = Get-Content -LiteralPath $path -Raw

        Test-Path -LiteralPath $path | Should -BeTrue
        $written | Should -Be $markdown
    }

    It 'skips the file write when WhatIf is set' {
        $path = Join-Path -Path $TestDrive -ChildPath 'skipped\health.md'
        $markdown = New-RepoHealthReport -Owner 'octo' -Repository 'widgets' -OutputPath $path -WhatIf

        Test-Path -LiteralPath $path | Should -BeFalse
        $markdown | Should -Match '# Repo health: octo/widgets'
    }
}

Describe 'New-RepoHealthReport empty results' {
    BeforeEach {
        Mock Invoke-RepoHealthGitHubApi -ModuleName RepoHealth { throw 'GitHub API should not be called.' }
        Mock Get-RepoStaleBranch -ModuleName RepoHealth { }
        Mock Get-RepoDependencyStatus -ModuleName RepoHealth { }
    }

    It 'says when nothing was found' {
        $markdown = New-RepoHealthReport -Owner 'octo' -Repository 'widgets'

        $markdown | Should -Match 'No stale branches were found\.'
        $markdown | Should -Match 'No dependency alerts were found\.'
    }
}

Describe 'New-RepoHealthReport module contract' {
    It 'exports only the three public functions' {
        $exported = @(Get-Command -Module RepoHealth -CommandType Function).Name | Sort-Object
        ($exported -join ',') | Should -Be 'Get-RepoDependencyStatus,Get-RepoStaleBranch,New-RepoHealthReport'
    }

    It 'lists those functions in the module manifest' {
        $manifest = Import-PowerShellDataFile -Path $script:moduleManifest
        $names = @($manifest.FunctionsToExport | Sort-Object)
        ($names -join ',') | Should -Be 'Get-RepoDependencyStatus,Get-RepoStaleBranch,New-RepoHealthReport'
        $manifest.PowerShellVersion | Should -Be '7.0'
    }

    It 'rejects invalid report parameters' {
        { New-RepoHealthReport -Owner '' -Repository 'widgets' } | Should -Throw
        { New-RepoHealthReport -Owner 'octo' -Repository 'widgets' -OlderThanDays 0 } | Should -Throw
        { New-RepoHealthReport -Owner 'octo' -Repository 'widgets' -DependencyState 'closed' } | Should -Throw
        { New-RepoHealthReport -Owner 'octo' -Repository 'widgets' -OutputPath '' } | Should -Throw
    }
}
