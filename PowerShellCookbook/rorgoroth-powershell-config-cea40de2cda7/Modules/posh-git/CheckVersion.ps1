$Global:GitMissing = $false

if (!(Get-Command git -TotalCount 1 -ErrorAction SilentlyContinue)) {
    Write-Warning "git command could not be found. Please create an alias or add it to your PATH."
    $Global:GitMissing = $true
    return
}

$requiredVersion = [Version]'2.6.2'
if ((git --version 2> $null) -match '(?<ver>\d+(?:\.\d+)+)') {
    $version = [Version]$Matches['ver']
}
if ($version -lt $requiredVersion) {
    Write-Warning "posh-git requires Git $requiredVersion or better. You have $version."
    $false
} else {
    $true
}
