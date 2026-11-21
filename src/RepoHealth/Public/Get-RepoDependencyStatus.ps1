<#
.SYNOPSIS
    Lists Dependabot alerts for a GitHub repository.

.DESCRIPTION
    Get-RepoDependencyStatus reads Dependabot alerts from the GitHub REST API.
    Results can be limited to one alert state and to a minimum severity.
    MinimumSeverity keeps that severity and every severity above it.

.PARAMETER Owner
    GitHub account or organization that owns the repository.

.PARAMETER Repository
    Repository name, without the owner.

.PARAMETER State
    Dependabot alert state to read. The default is open.
    Valid values are open, dismissed, fixed, and auto_dismissed.

.PARAMETER MinimumSeverity
    Lowest advisory severity to return. Valid values are low, medium, high, and critical.
    When this parameter is omitted, every severity is returned.

.EXAMPLE
    Get-RepoDependencyStatus -Owner 'octocat' -Repository 'hello-world' -MinimumSeverity 'high'

    Returns open Dependabot alerts of high or critical severity.

.EXAMPLE
    [pscustomobject]@{ Owner = 'octocat'; Repository = 'hello-world' } | Get-RepoDependencyStatus -State 'fixed'

    Returns fixed alerts for a repository supplied by pipeline input.

.OUTPUTS
    System.Management.Automation.PSCustomObject

.LINK
    https://github.com/zainulabdin1472/PowerShell-RepoPulse
#>
function Get-RepoDependencyStatus {
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
        [ValidateSet('open', 'dismissed', 'fixed', 'auto_dismissed')]
        [string] $State = 'open',

        [Parameter()]
        [ValidateSet('low', 'medium', 'high', 'critical')]
        [string] $MinimumSeverity
    )

    begin {
        $severityRank = @{
            low      = 1
            medium   = 2
            high     = 3
            critical = 4
        }
        $alerts = [System.Collections.Generic.List[object]]::new()
    }

    process {
        $ownerName = $Owner.Trim()
        $repositoryName = $Repository.Trim()
        $payload = @(
            Invoke-RepoHealthGitHubApi -Path "repos/$ownerName/$repositoryName/dependabot/alerts" -Query @{ state = $State } -Paginate |
                Where-Object { $null -ne $_ }
        )
        $minimumRank = 0
        if ($PSBoundParameters.ContainsKey('MinimumSeverity')) {
            $minimumRank = $severityRank[$MinimumSeverity]
        }

        foreach ($alert in $payload) {
            $severity = [string](Get-RepoHealthProperty -InputObject $alert -Name @('security_advisory', 'severity'))
            if ([string]::IsNullOrWhiteSpace($severity)) {
                $severity = [string](Get-RepoHealthProperty -InputObject $alert -Name @('security_vulnerability', 'severity'))
            }

            $severity = $severity.ToLowerInvariant()
            $rank = 0
            if ($severityRank.ContainsKey($severity)) {
                $rank = $severityRank[$severity]
            }

            if ($minimumRank -gt 0 -and $rank -lt $minimumRank) {
                continue
            }

            $alertNumber = Get-RepoHealthProperty -InputObject $alert -Name @('number')
            if ($null -eq $alertNumber -or [string]::IsNullOrWhiteSpace([string]$alertNumber)) {
                Write-Error -Message "Dependabot alert number was missing for '$ownerName/$repositoryName'."
                continue
            }

            $alerts.Add([pscustomobject]@{
                    AlertNumber  = [int]$alertNumber
                    PackageName  = [string](Get-RepoHealthProperty -InputObject $alert -Name @('dependency', 'package', 'name'))
                    Ecosystem    = [string](Get-RepoHealthProperty -InputObject $alert -Name @('dependency', 'package', 'ecosystem'))
                    ManifestPath = [string](Get-RepoHealthProperty -InputObject $alert -Name @('dependency', 'manifest_path'))
                    Severity     = $severity
                    State        = [string](Get-RepoHealthProperty -InputObject $alert -Name @('state'))
                    Summary      = [string](Get-RepoHealthProperty -InputObject $alert -Name @('security_advisory', 'summary'))
                    HtmlUrl      = [string](Get-RepoHealthProperty -InputObject $alert -Name @('html_url'))
                    SeverityRank = $rank
                })
        }
    }

    end {
        $alerts |
            Sort-Object -Property @{ Expression = { $_.SeverityRank }; Descending = $true }, @{ Expression = { $_.AlertNumber }; Descending = $false } |
            Select-Object -Property AlertNumber, PackageName, Ecosystem, ManifestPath, Severity, State, Summary, HtmlUrl
    }
}
