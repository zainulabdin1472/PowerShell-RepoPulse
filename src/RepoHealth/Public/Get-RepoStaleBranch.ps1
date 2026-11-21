<#
.SYNOPSIS
    Lists branches whose latest commit is older than a given number of days.

.DESCRIPTION
    Get-RepoStaleBranch reads branch tips from the GitHub REST API and returns
    the branches that have not been updated within OlderThanDays. The default
    branch is included when it is stale and is identified by IsDefault.

.PARAMETER Owner
    GitHub account or organization that owns the repository.

.PARAMETER Repository
    Repository name, without the owner.

.PARAMETER OlderThanDays
    Age, in days, after which a branch is returned. The default is 30.
    Valid values are 1 through 3650. A branch is returned only when its latest
    commit is older than this cutoff.

.EXAMPLE
    Get-RepoStaleBranch -Owner 'octocat' -Repository 'hello-world' -OlderThanDays 60

    Returns branches in octocat/hello-world whose latest commit is more than 60 days old.

.EXAMPLE
    [pscustomobject]@{ Owner = 'octocat'; Repository = 'hello-world' } | Get-RepoStaleBranch

    Accepts the owner and repository from pipeline input by property name.

.OUTPUTS
    System.Management.Automation.PSCustomObject

.LINK
    https://github.com/zainulabdin1472/PowerShell-RepoPulse
#>
function Get-RepoStaleBranch {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Owner,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository,

        [Parameter()]
        [ValidateRange(1, 3650)]
        [int] $OlderThanDays = 30
    )

    begin {
        $staleBranches = [System.Collections.Generic.List[object]]::new()
    }

    process {
        $ownerName = $Owner.Trim()
        $repositoryName = $Repository.Trim()
        $repositoryPath = "repos/$ownerName/$repositoryName"
        $repositoryInfo = Invoke-RepoHealthGitHubApi -Path $repositoryPath
        $defaultBranch = [string](Get-RepoHealthProperty -InputObject $repositoryInfo -Name @('default_branch'))
        $branches = @(
            Invoke-RepoHealthGitHubApi -Path "$repositoryPath/branches" -Paginate |
                Where-Object { $null -ne $_ }
        )
        $cutoff = [datetimeoffset]::UtcNow.AddDays(-1 * $OlderThanDays)
        $dateStyles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor `
            [System.Globalization.DateTimeStyles]::AdjustToUniversal

        foreach ($branchInfo in $branches) {
            $branchName = [string](Get-RepoHealthProperty -InputObject $branchInfo -Name @('name'))
            $sha = [string](Get-RepoHealthProperty -InputObject $branchInfo -Name @('commit', 'sha'))
            if ([string]::IsNullOrWhiteSpace($branchName) -or [string]::IsNullOrWhiteSpace($sha)) {
                Write-Error -Message "Branch name or commit SHA was missing for '$ownerName/$repositoryName'."
                continue
            }

            $commitResponse = Invoke-RepoHealthGitHubApi -Path "$repositoryPath/commits/$sha"
            $commitDateText = [string](Get-RepoHealthProperty -InputObject $commitResponse -Name @('commit', 'committer', 'date'))
            if ([string]::IsNullOrWhiteSpace($commitDateText)) {
                $commitDateText = [string](Get-RepoHealthProperty -InputObject $commitResponse -Name @('commit', 'author', 'date'))
            }

            if ([string]::IsNullOrWhiteSpace($commitDateText)) {
                Write-Error -Message "Commit date was not found for branch '$branchName'."
                continue
            }

            $lastCommitAt = [datetimeoffset]::Parse(
                $commitDateText,
                [System.Globalization.CultureInfo]::InvariantCulture,
                $dateStyles)
            if ($lastCommitAt -ge $cutoff) {
                continue
            }

            $ageDays = [int][math]::Floor(([datetimeoffset]::UtcNow - $lastCommitAt).TotalDays)
            $encodedBranch = @(
                $branchName.Split('/') | ForEach-Object { [uri]::EscapeDataString($_) }
            ) -join '/'
            $urlParts = @(
                [uri]::EscapeDataString($ownerName)
                [uri]::EscapeDataString($repositoryName)
                $encodedBranch
            )
            $htmlUrl = 'https://github.com/{0}/{1}/tree/{2}' -f $urlParts

            $staleBranches.Add([pscustomobject]@{
                    Branch       = $branchName
                    Sha          = $sha
                    LastCommitAt = $lastCommitAt
                    AgeDays      = $ageDays
                    IsDefault    = ($branchName -ceq $defaultBranch)
                    HtmlUrl      = $htmlUrl
                })
        }
    }

    end {
        $staleBranches |
            Sort-Object -Property @{ Expression = { $_.AgeDays }; Descending = $true }, @{ Expression = { $_.Branch }; Descending = $false }
    }
}
