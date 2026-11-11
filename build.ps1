<#
.SYNOPSIS
    Builds the Muon shader pack release archive.

.DESCRIPTION
    Runs the static validator and generator checks, then packages shaders/ into
    <workspace>/release/Muon-v<version>.zip. With -Archive the result is also
    frozen into <workspace>/archive/v<version>/ with a manifest and a SHA-256.

    The release and archive directories sit beside the repository, not inside
    it, so a clone never carries build output.

.EXAMPLE
    ./build.ps1
    ./build.ps1 -Archive
    ./build.ps1 -SkipChecks
#>
[CmdletBinding()]
param(
    [switch]$Archive,
    [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Find-Python {
    if ($env:MUON_PYTHON -and (Test-Path $env:MUON_PYTHON)) { return $env:MUON_PYTHON }
    foreach ($candidate in @('python', 'python3', 'py')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw 'Python 3 is required. Set MUON_PYTHON to an interpreter path.'
}

$python = Find-Python
Write-Host "Muon build - python: $python" -ForegroundColor Cyan

$arguments = @('tools/package.py')
if ($Archive)    { $arguments += '--archive' }
if ($SkipChecks) { $arguments += '--skip-checks' }

& $python @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Packaging failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'Done. Copy release/*.zip into .minecraft/shaderpacks/.' -ForegroundColor Green
