[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$RadioRoot
)

$ErrorActionPreference = "Stop"

$resolvedRadioRoot = $RadioRoot.Trim('"')
if (-not (Test-Path -LiteralPath $resolvedRadioRoot)) {
    throw "Radio folder not found: $resolvedRadioRoot"
}

$destination = Join-Path $resolvedRadioRoot "WIDGETS\DBK_TX16KMK3"
New-Item -ItemType Directory -Force -Path $destination | Out-Null

Write-Host "Deploying $Source to $destination"

robocopy $Source $destination /MIR /XD .git .github .agents .vscode doc tools release-notes /XF *.code-workspace
$exitCode = $LASTEXITCODE

if ($exitCode -gt 7) {
    throw "robocopy deploy failed. Code: $exitCode"
}

Write-Host "Deploy finished successfully."
