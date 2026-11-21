#Requires -Version 7.0
Set-StrictMode -Version 3.0

$privateRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$publicRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$publicNames = [System.Collections.Generic.List[string]]::new()

foreach ($root in @($privateRoot, $publicRoot)) {
    $scripts = @(Get-ChildItem -Path $root -Filter '*.ps1' -File | Sort-Object -Property Name)
    foreach ($script in $scripts) {
        . $script.FullName
        if ($root -eq $publicRoot) {
            $publicNames.Add($script.BaseName)
        }
    }
}

Export-ModuleMember -Function ([string[]]$publicNames.ToArray())
