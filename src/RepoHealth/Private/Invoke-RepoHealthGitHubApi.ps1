function Get-RepoHealthProperty {
    <#
    .SYNOPSIS
        Reads a nested property path without failing when a level is missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Name
    )

    $current = $InputObject
    foreach ($part in $Name) {
        if ($null -eq $current) {
            return $null
        }

        $property = $current.PSObject.Properties[$part]
        if ($null -eq $property) {
            return $null
        }

        $current = $property.Value
    }

    return $current
}

function Get-RepoHealthHeaderValue {
    <#
    .SYNOPSIS
        Reads a response header by name.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        $Headers,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if ($null -eq $Headers) {
        return $null
    }

    $keys = @($Headers.Keys)
    foreach ($key in $keys) {
        if ([string]$key.Equals($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $Headers[$key]
        }
    }

    return $null
}

function Format-RepoHealthTableCell {
    <#
    .SYNOPSIS
        Flattens a value so it can sit in a Markdown table cell.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    $singleLine = $Value -replace '\r?\n', ' '
    return ($singleLine -replace '\|', '\|')
}

function Get-RepoHealthAccessToken {
    <#
    .SYNOPSIS
        Resolves a GitHub token from the environment or GitHub CLI.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $token = [Environment]::GetEnvironmentVariable('GH_TOKEN')
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = [Environment]::GetEnvironmentVariable('GITHUB_TOKEN')
    }

    if ([string]::IsNullOrWhiteSpace($token)) {
        $ghCommand = Get-Command -Name 'gh' -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $ghCommand) {
            $token = & $ghCommand.Source auth token
            if ($token -is [System.Array]) {
                $token = $token | Select-Object -Last 1
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$token)) {
        $exception = [System.InvalidOperationException]::new(
            'GitHub authentication was not found. Set GH_TOKEN or sign in with GitHub CLI.')
        $record = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'RepoHealthMissingToken',
            [System.Management.Automation.ErrorCategory]::AuthenticationError,
            'github.com')
        $PSCmdlet.ThrowTerminatingError($record)
    }

    return ([string]$token).Trim()
}

function Invoke-RepoHealthGitHubApi {
    <#
    .SYNOPSIS
        Sends an authenticated GET request to the GitHub REST API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [hashtable] $Query,

        [Parameter()]
        [switch] $Paginate
    )

    $token = Get-RepoHealthAccessToken
    $normalizedPath = $Path.Trim().TrimStart('/')
    $queryValues = @{}
    if ($null -ne $Query) {
        foreach ($key in @($Query.Keys)) {
            $queryValues[$key] = $Query[$key]
        }
    }

    $headers = @{
        Authorization          = "Bearer $token"
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'RepoHealth'
    }

    $page = 1
    $collected = [System.Collections.Generic.List[object]]::new()

    do {
        if ($page -gt 1000) {
            $limitException = [System.InvalidOperationException]::new(
                "GitHub API pagination exceeded 1000 pages for '$normalizedPath'.")
            $limitRecord = [System.Management.Automation.ErrorRecord]::new(
                $limitException,
                'RepoHealthGitHubApiPageLimit',
                [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                $normalizedPath)
            $PSCmdlet.ThrowTerminatingError($limitRecord)
        }

        $pageQuery = @{}
        foreach ($key in @($queryValues.Keys)) {
            $pageQuery[$key] = $queryValues[$key]
        }

        if ($Paginate) {
            $pageQuery['per_page'] = 100
            $pageQuery['page'] = $page
        }

        $pairs = @(
            foreach ($key in @($pageQuery.Keys)) {
                '{0}={1}' -f [uri]::EscapeDataString([string]$key), [uri]::EscapeDataString([string]$pageQuery[$key])
            }
        )
        $queryString = $pairs -join '&'
        $uri = "https://api.github.com/$normalizedPath"
        if (-not [string]::IsNullOrEmpty($queryString)) {
            $uri = '{0}?{1}' -f $uri, $queryString
        }

        try {
            $response = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get
        }
        catch {
            $requestException = [System.InvalidOperationException]::new(
                "GitHub API request failed for '$normalizedPath'. $($_.Exception.Message)",
                $_.Exception)
            $requestRecord = [System.Management.Automation.ErrorRecord]::new(
                $requestException,
                'RepoHealthGitHubApiFailed',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $normalizedPath)
            $PSCmdlet.ThrowTerminatingError($requestRecord)
        }

        $payload = $null
        if ($null -ne $response -and -not [string]::IsNullOrWhiteSpace([string]$response.Content)) {
            $payload = $response.Content | ConvertFrom-Json
        }

        if (-not $Paginate) {
            return $payload
        }

        if ($null -ne $payload) {
            foreach ($item in @($payload)) {
                if ($null -ne $item) {
                    $collected.Add($item)
                }
            }
        }

        $linkHeader = Get-RepoHealthHeaderValue -Headers $response.Headers -Name 'Link'
        if ($linkHeader -is [System.Array]) {
            $linkHeader = $linkHeader -join ','
        }

        $hasNext = [string]$linkHeader -match 'rel="next"'
        $page++
    } while ($hasNext)

    return @($collected.ToArray())
}
