param(
    [string]$SourceRoot = "",
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$codegenRoot = Split-Path -Parent $scriptDir

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $codegenRoot "source_plugins"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $codegenRoot ".generated"
}

Write-Host "Generating GDMusic plugin skeletons..."
Write-Host "SourceRoot: $SourceRoot"
Write-Host "OutputRoot: $OutputRoot"

node (Join-Path $scriptDir "generate_gd_skeletons.js") $SourceRoot $OutputRoot
