BeforeAll {
    $script:moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\src\RepoHealth\RepoHealth.psd1'
    Import-Module -Name $script:moduleManifest -Force
}

Describe 'Get-RepoDependencyStatus' {
    BeforeEach {
        Mock Invoke-RestMethod -ModuleName RepoHealth { throw 'Live GitHub call' }
        Mock Invoke-WebRequest -ModuleName RepoHealth { throw 'Live GitHub call' }
        Mock Invoke-RepoHealthGitHubApi -ModuleName RepoHealth -MockWith {
            param(
                [string] $Path,
                [hashtable] $Query,
                [switch] $Paginate
            )

            function New-MockAlert {
                param(
                    [int] $Number,
                    [string] $Package,
                    [string] $Ecosystem,
                    [string] $Manifest,
                    [string] $Severity,
                    [string] $Summary
                )

                return [pscustomobject]@{
                    number     = $Number
                    state      = 'open'
                    html_url   = "https://github.com/octo/widgets/security/dependabot/$Number"
                    dependency = [pscustomobject]@{
                        package       = [pscustomobject]@{
                            name      = $Package
                            ecosystem = $Ecosystem
                        }
                        manifest_path = $Manifest
                    }
                    security_advisory = [pscustomobject]@{
                        severity = $Severity
                        summary  = $Summary
                    }
                }
            }

            return @(
                New-MockAlert -Number 2 -Package 'lodash' -Ecosystem 'npm' -Manifest 'package.json' -Severity 'high' -Summary 'Prototype pollution'
                New-MockAlert -Number 8 -Package 'rails' -Ecosystem 'rubygems' -Manifest 'Gemfile.lock' -Severity 'critical' -Summary 'Remote code execution'
                New-MockAlert -Number 3 -Package 'left-pad' -Ecosystem 'npm' -Manifest 'package.json' -Severity 'low' -Summary 'Unexpected behavior'
            )
        }
    }

    It 'has comment-based help' {
        $help = Get-Help -Name Get-RepoDependencyStatus
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.examples.example.Count | Should -BeGreaterOrEqual 1
    }

    It 'returns open alerts with the highest severity first' {
        $result = @(Get-RepoDependencyStatus -Owner 'octo' -Repository 'widgets')

        $result.Count | Should -Be 3
        $result[0].AlertNumber | Should -Be 8
        $result[0].PackageName | Should -Be 'rails'
        $result[0].Severity | Should -Be 'critical'
        $result[0].Ecosystem | Should -Be 'rubygems'
        $result[0].ManifestPath | Should -Be 'Gemfile.lock'
        $result[0].HtmlUrl | Should -Be 'https://github.com/octo/widgets/security/dependabot/8'
        $result[1].PackageName | Should -Be 'lodash'
        $result[2].PackageName | Should -Be 'left-pad'
        $result[0].PSObject.Properties.Name | Should -Not -Contain 'SeverityRank'
    }

    It 'keeps the minimum severity and everything above it' {
        $result = @(Get-RepoDependencyStatus -Owner 'octo' -Repository 'widgets' -MinimumSeverity 'high')

        ($result.PackageName -join ',') | Should -Be 'rails,lodash'
    }

    It 'passes the alert state to the GitHub API' {
        Get-RepoDependencyStatus -Owner 'octo' -Repository 'widgets' -State 'dismissed' | Out-Null

        Assert-MockCalled -CommandName Invoke-RepoHealthGitHubApi -ModuleName RepoHealth -Times 1 -ParameterFilter {
            $Path -eq 'repos/octo/widgets/dependabot/alerts' -and
            $Query['state'] -eq 'dismissed' -and
            $Paginate
        }
        Should -Invoke -CommandName Invoke-WebRequest -ModuleName RepoHealth -Times 0
    }

    It 'accepts owner and repository from the pipeline' {
        $result = @(
            [pscustomobject]@{ Owner = 'octo'; Repository = 'widgets' } |
                Get-RepoDependencyStatus -MinimumSeverity 'critical'
        )

        $result.PackageName | Should -Be 'rails'
    }
}

Describe 'Get-RepoDependencyStatus parameter validation' {
    It 'rejects an empty owner and unknown state or severity' {
        { Get-RepoDependencyStatus -Owner '' -Repository 'widgets' } | Should -Throw
        { Get-RepoDependencyStatus -Owner 'octo' -Repository '' } | Should -Throw
        { Get-RepoDependencyStatus -Owner 'octo' -Repository 'widgets' -State 'closed' } | Should -Throw
        { Get-RepoDependencyStatus -Owner 'octo' -Repository 'widgets' -MinimumSeverity 'urgent' } | Should -Throw
    }
}

Describe 'Get-RepoDependencyStatus single alert payload' {
    BeforeEach {
        Mock Invoke-RepoHealthGitHubApi -ModuleName RepoHealth -MockWith {
            return [pscustomobject]@{
                number            = 11
                state             = 'open'
                html_url          = 'https://github.com/octo/widgets/security/dependabot/11'
                dependency        = [pscustomobject]@{
                    package       = [pscustomobject]@{
                        name      = 'minimist'
                        ecosystem = 'npm'
                    }
                    manifest_path = 'package-lock.json'
                }
                security_vulnerability = [pscustomobject]@{
                    severity = 'MEDIUM'
                }
                security_advisory = [pscustomobject]@{
                    summary = 'Prototype pollution'
                }
            }
        }
    }

    It 'reads one alert object and falls back to the vulnerability severity' {
        $result = @(Get-RepoDependencyStatus -Owner 'octo' -Repository 'widgets')

        $result.Count | Should -Be 1
        $result[0].AlertNumber | Should -Be 11
        $result[0].PackageName | Should -Be 'minimist'
        $result[0].Severity | Should -Be 'medium'
        $result[0].Summary | Should -Be 'Prototype pollution'
    }
}
