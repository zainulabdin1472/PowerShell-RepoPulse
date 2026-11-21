BeforeAll {
    $script:moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\src\RepoHealth\RepoHealth.psd1'
    Import-Module -Name $script:moduleManifest -Force
}

Describe 'Get-RepoStaleBranch' {
    Context 'when the repository has mixed branch ages' {
        BeforeEach {
            Mock Invoke-RestMethod -ModuleName RepoHealth { throw 'Live GitHub call' }
            Mock Invoke-WebRequest -ModuleName RepoHealth { throw 'Live GitHub call' }
            Mock Invoke-RepoHealthGitHubApi -ModuleName RepoHealth -MockWith {
                param(
                    [string] $Path,
                    [hashtable] $Query,
                    [switch] $Paginate
                )

                function New-MockCommit {
                    param([int] $DaysAgo)
                    $date = [datetimeoffset]::UtcNow.AddDays(-1 * $DaysAgo).ToString('yyyy-MM-ddTHH:mm:ssZ')
                    return [pscustomobject]@{
                        commit = [pscustomobject]@{
                            committer = [pscustomobject]@{ date = $date }
                            author    = [pscustomobject]@{ date = $date }
                        }
                    }
                }

                switch -Regex ($Path) {
                    '^repos/octo/widgets$' {
                        return [pscustomobject]@{ default_branch = 'main' }
                    }
                    '^repos/octo/widgets/branches$' {
                        return @(
                            [pscustomobject]@{ name = 'main'; commit = [pscustomobject]@{ sha = 'sha-main' } }
                            [pscustomobject]@{ name = 'feature/old'; commit = [pscustomobject]@{ sha = 'sha-old' } }
                            [pscustomobject]@{ name = 'feature/a b'; commit = [pscustomobject]@{ sha = 'sha-space' } }
                            [pscustomobject]@{ name = 'feature/fresh'; commit = [pscustomobject]@{ sha = 'sha-fresh' } }
                        )
                    }
                    'commits/sha-main$' { return (New-MockCommit -DaysAgo 45) }
                    'commits/sha-old$' { return (New-MockCommit -DaysAgo 80) }
                    'commits/sha-space$' { return (New-MockCommit -DaysAgo 50) }
                    'commits/sha-fresh$' { return (New-MockCommit -DaysAgo 2) }
                    default { throw "Unexpected GitHub path '$Path'." }
                }
            }
        }

        It 'has comment-based help' {
            $help = Get-Help -Name Get-RepoStaleBranch
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.examples.example.Count | Should -BeGreaterOrEqual 1
        }

        It 'returns only branches older than the cutoff, stalest first' {
            $result = @(Get-RepoStaleBranch -Owner 'octo' -Repository 'widgets' -OlderThanDays 30)

            $result.Count | Should -Be 3
            $result[0].Branch | Should -Be 'feature/old'
            $result[1].Branch | Should -Be 'feature/a b'
            $result[2].Branch | Should -Be 'main'
            $result.Branch | Should -Not -Contain 'feature/fresh'
            $result[0].AgeDays | Should -BeGreaterThan $result[1].AgeDays
            $result[1].AgeDays | Should -BeGreaterThan $result[2].AgeDays
            $result[0].LastCommitAt | Should -BeOfType [datetimeoffset]
            $result[2].IsDefault | Should -BeTrue
            $result[0].IsDefault | Should -BeFalse
            $result[0].Sha | Should -Be 'sha-old'
            $result[1].HtmlUrl | Should -Be 'https://github.com/octo/widgets/tree/feature/a%20b'
        }

        It 'requests the repository, the branch list, and each commit' {
            Get-RepoStaleBranch -Owner 'octo' -Repository 'widgets' | Out-Null

            Assert-MockCalled -CommandName Invoke-RepoHealthGitHubApi -ModuleName RepoHealth -Times 1 -ParameterFilter {
                $Path -eq 'repos/octo/widgets' -and -not $Paginate
            }
            Assert-MockCalled -CommandName Invoke-RepoHealthGitHubApi -ModuleName RepoHealth -Times 1 -ParameterFilter {
                $Path -eq 'repos/octo/widgets/branches' -and $Paginate
            }
            Assert-MockCalled -CommandName Invoke-RepoHealthGitHubApi -ModuleName RepoHealth -Times 4 -ParameterFilter {
                $Path -like 'repos/octo/widgets/commits/*'
            }
            Should -Invoke -CommandName Invoke-WebRequest -ModuleName RepoHealth -Times 0
        }

        It 'accepts owner and repository from the pipeline' {
            $result = @(
                [pscustomobject]@{ Owner = 'octo'; Repository = 'widgets' } |
                    Get-RepoStaleBranch -OlderThanDays 30
            )

            $result.Count | Should -Be 3
            $result[0].Branch | Should -Be 'feature/old'
        }
    }

    Context 'when the branch list contains one object' {
        BeforeEach {
            Mock Invoke-RepoHealthGitHubApi -ModuleName RepoHealth -MockWith {
                param([string] $Path)

                switch -Regex ($Path) {
                    '^repos/octo/widgets$' {
                        return [pscustomobject]@{ default_branch = 'dev' }
                    }
                    '^repos/octo/widgets/branches$' {
                        return [pscustomobject]@{ name = 'dev'; commit = [pscustomobject]@{ sha = 'sha-dev' } }
                    }
                    'commits/sha-dev$' {
                        $date = [datetimeoffset]::UtcNow.AddDays(-40).ToString('yyyy-MM-ddTHH:mm:ssZ')
                        return [pscustomobject]@{
                            commit = [pscustomobject]@{
                                committer = [pscustomobject]@{ date = $date }
                                author    = [pscustomobject]@{ date = $date }
                            }
                        }
                    }
                    default { throw "Unexpected GitHub path '$Path'." }
                }
            }
        }

        It 'still returns that stale default branch' {
            $result = @(Get-RepoStaleBranch -Owner 'octo' -Repository 'widgets')

            $result.Count | Should -Be 1
            $result[0].Branch | Should -Be 'dev'
            $result[0].IsDefault | Should -BeTrue
        }
    }

    Context 'when a commit date is missing' {
        BeforeEach {
            Mock Invoke-RepoHealthGitHubApi -ModuleName RepoHealth -MockWith {
                param([string] $Path)

                switch -Regex ($Path) {
                    '^repos/octo/widgets$' {
                        return [pscustomobject]@{ default_branch = 'main' }
                    }
                    '^repos/octo/widgets/branches$' {
                        return @(
                            [pscustomobject]@{ name = 'main'; commit = [pscustomobject]@{ sha = 'sha-main' } }
                            [pscustomobject]@{ name = 'feature/bad'; commit = [pscustomobject]@{ sha = 'sha-bad' } }
                        )
                    }
                    'commits/sha-main$' {
                        $date = [datetimeoffset]::UtcNow.AddDays(-45).ToString('yyyy-MM-ddTHH:mm:ssZ')
                        return [pscustomobject]@{
                            commit = [pscustomobject]@{
                                committer = [pscustomobject]@{ date = $date }
                                author    = [pscustomobject]@{ date = $date }
                            }
                        }
                    }
                    'commits/sha-bad$' { return [pscustomobject]@{ commit = [pscustomobject]@{} } }
                    default { throw "Unexpected GitHub path '$Path'." }
                }
            }
        }

        It 'skips the branch and writes an error' {
            $result = @(
                Get-RepoStaleBranch -Owner 'octo' -Repository 'widgets' -ErrorVariable branchErrors -ErrorAction SilentlyContinue
            )

            $result.Branch | Should -Be @('main')
            $branchErrors.Count | Should -BeGreaterThan 0
            $branchErrors[0].Exception.Message | Should -Match 'feature/bad'
        }
    }

    Context 'when parameters are invalid' {
        It 'rejects an empty owner, an empty repository, and an out-of-range age' {
            { Get-RepoStaleBranch -Owner '' -Repository 'widgets' } | Should -Throw
            { Get-RepoStaleBranch -Owner 'octo' -Repository '' } | Should -Throw
            { Get-RepoStaleBranch -Owner 'octo' -Repository 'widgets' -OlderThanDays 0 } | Should -Throw
            { Get-RepoStaleBranch -Owner 'octo' -Repository 'widgets' -OlderThanDays 3651 } | Should -Throw
        }
    }
}

Describe 'Invoke-RepoHealthGitHubApi' {
    BeforeEach {
        $script:previousGhToken = $env:GH_TOKEN
        $script:previousGithubToken = $env:GITHUB_TOKEN
        $env:GH_TOKEN = 'test-token'
        $env:GITHUB_TOKEN = 'other-token'
    }

    AfterEach {
        if ($null -eq $script:previousGhToken) {
            Remove-Item -Path Env:GH_TOKEN -ErrorAction SilentlyContinue
        }
        else {
            $env:GH_TOKEN = $script:previousGhToken
        }

        if ($null -eq $script:previousGithubToken) {
            Remove-Item -Path Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
        }
        else {
            $env:GITHUB_TOKEN = $script:previousGithubToken
        }
    }

    It 'sends GH_TOKEN and returns the JSON object' {
        Mock Invoke-WebRequest -ModuleName RepoHealth -MockWith {
            param(
                [string] $Uri,
                $Headers,
                $Method
            )

            $script:capturedUri = $Uri
            $script:capturedAuthorization = $Headers.Authorization
            $script:capturedUserAgent = $Headers['User-Agent']
            return [pscustomobject]@{
                Content = '{"default_branch":"main"}'
                Headers = @{}
            }
        }

        $result = InModuleScope RepoHealth {
            Invoke-RepoHealthGitHubApi -Path '/repos/octo/widgets'
        }

        $result.default_branch | Should -Be 'main'
        $script:capturedUri | Should -Be 'https://api.github.com/repos/octo/widgets'
        $script:capturedAuthorization | Should -Be 'Bearer test-token'
        $script:capturedUserAgent | Should -Be 'RepoHealth'
    }

    It 'follows next links when paginating' {
        Mock Invoke-WebRequest -ModuleName RepoHealth -MockWith {
            param(
                [string] $Uri,
                $Headers,
                $Method
            )

            if ($Uri -match 'page=2') {
                return [pscustomobject]@{
                    Content = '[{"name":"old"}]'
                    Headers = @{ Link = '' }
                }
            }

            return [pscustomobject]@{
                Content = '[{"name":"main"}]'
                Headers = @{ Link = '<https://api.github.com/repos/octo/widgets/branches?page=2>; rel="next"' }
            }
        }

        $names = @(
            InModuleScope RepoHealth {
                Invoke-RepoHealthGitHubApi -Path 'repos/octo/widgets/branches' -Paginate
            } | ForEach-Object { $_.name }
        )

        $names -join ',' | Should -Be 'main,old'
    }

    It 'wraps a failed request with the API path' {
        Mock Invoke-WebRequest -ModuleName RepoHealth { throw '404 Not Found' }

        {
            InModuleScope RepoHealth {
                Invoke-RepoHealthGitHubApi -Path 'repos/octo/missing'
            }
        } | Should -Throw -ExpectedMessage '*repos/octo/missing*'
    }
}
