<#
.SYNOPSIS
    Builds a Markdown health report for a GitHub repository.

.DESCRIPTION
    New-RepoHealthReport collects stale branches and Dependabot alerts, then
    returns the report as Markdown. When OutputPath is provided, the same
    Markdown is written to that file. WhatIf shows the write without creating
    the file.

.PARAMETER Owner
    GitHub account or organization that owns the repository.

.PARAMETER Repository
    Repository name, without the owner.

.PARAMETER OlderThanDays
    Age, in days, passed to Get-RepoStaleBranch. The default is 30.
    Valid values are 1 through 3650.

.PARAMETER DependencyState
    Dependabot alert state passed to Get-RepoDependencyStatus. The default is open.
    Valid values are open, dismissed, fixed, and auto_dismissed.

.PARAMETER OutputPath
    Optional file path for the Markdown report. Parent directories are created
    when the file is written.

.EXAMPLE
    New-RepoHealthReport -Owner 'octocat' -Repository 'hello-world' -OlderThanDays 45

    Returns a Markdown report for branches older than 45 days and open Dependabot alerts.

.EXAMPLE
    New-RepoHealthReport -Owner 'octocat' -Repository 'hello-world' -OutputPath '.\health.md'

    Writes the report to health.md and returns the same Markdown.

.OUTPUTS
    System.String

.LINK
    https://github.com/zainulabdin1472/PowerShell-RepoPulse
#>
function New-RepoHealthReport {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Owner,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Repository,

        [Parameter()]
        [ValidateRange(1, 3650)]
        [int] $OlderThanDays = 30,

        [Parameter()]
        [ValidateSet('open', 'dismissed', 'fixed', 'auto_dismissed')]
        [string] $DependencyState = 'open',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $OutputPath
    )

    $staleBranches = @(
        Get-RepoStaleBranch -Owner $Owner -Repository $Repository -OlderThanDays $OlderThanDays |
            Where-Object { $null -ne $_ }
    )
    $dependencies = @(
        Get-RepoDependencyStatus -Owner $Owner -Repository $Repository -State $DependencyState |
            Where-Object { $null -ne $_ }
    )
    $generatedAt = [datetimeoffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $titleOwner = Format-RepoHealthTableCell -Value $Owner
    $titleRepository = Format-RepoHealthTableCell -Value $Repository
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(('# Repo health: {0}/{1}' -f $titleOwner, $titleRepository))
    $lines.Add('')
    $lines.Add("Generated: $generatedAt")
    $lines.Add('')
    $lines.Add('## Stale branches')
    $lines.Add('')
    $lines.Add("Branches whose latest commit is more than $OlderThanDays days old.")
    $lines.Add('')

    if ($staleBranches.Count -eq 0) {
        $lines.Add('No stale branches were found.')
    }
    else {
        $lines.Add('| Branch | Last commit (UTC) | Age (days) | Default | Url |')
        $lines.Add('| --- | --- | --- | --- | --- |')
        foreach ($branch in $staleBranches) {
            $defaultText = 'No'
            if ($branch.IsDefault) {
                $defaultText = 'Yes'
            }

            $commitText = ([datetimeoffset]$branch.LastCommitAt).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $branchCells = @(
                Format-RepoHealthTableCell -Value $branch.Branch
                Format-RepoHealthTableCell -Value $commitText
                Format-RepoHealthTableCell -Value ([string]$branch.AgeDays)
                Format-RepoHealthTableCell -Value $defaultText
                Format-RepoHealthTableCell -Value $branch.HtmlUrl
            )
            $lines.Add(('| {0} | {1} | {2} | {3} | {4} |' -f $branchCells))
        }
    }

    $lines.Add('')
    $lines.Add('## Dependency alerts')
    $lines.Add('')
    $lines.Add("Dependabot alerts with state '$DependencyState'.")
    $lines.Add('')

    if ($dependencies.Count -eq 0) {
        $lines.Add('No dependency alerts were found.')
    }
    else {
        $lines.Add('| Alert | Package | Ecosystem | Severity | Manifest | Summary | Url |')
        $lines.Add('| --- | --- | --- | --- | --- | --- | --- |')
        foreach ($alert in $dependencies) {
            $alertCells = @(
                Format-RepoHealthTableCell -Value ([string]$alert.AlertNumber)
                Format-RepoHealthTableCell -Value $alert.PackageName
                Format-RepoHealthTableCell -Value $alert.Ecosystem
                Format-RepoHealthTableCell -Value $alert.Severity
                Format-RepoHealthTableCell -Value $alert.ManifestPath
                Format-RepoHealthTableCell -Value $alert.Summary
                Format-RepoHealthTableCell -Value $alert.HtmlUrl
            )
            $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f $alertCells))
        }
    }

    $lines.Add('')
    $markdown = ($lines.ToArray() -join "`n") + "`n"
    if ($PSBoundParameters.ContainsKey('OutputPath')) {
        if ($PSCmdlet.ShouldProcess($OutputPath, 'Write repo health report')) {
            $parentPath = Split-Path -Path $OutputPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($parentPath) -and -not (Test-Path -LiteralPath $parentPath)) {
                New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
            }

            Set-Content -LiteralPath $OutputPath -Value $markdown -Encoding utf8NoBOM -NoNewline
        }
    }

    return $markdown
}
