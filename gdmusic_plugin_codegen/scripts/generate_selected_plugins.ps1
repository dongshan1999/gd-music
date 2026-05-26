$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$codegenRoot = Split-Path -Parent $scriptRoot
$projectRoot = Split-Path -Parent $codegenRoot

$sourceRoot = Join-Path $codegenRoot "source_plugins"
$outputRoot = Join-Path $codegenRoot ".generated"
$selectedPlugins = @("audiomack", "geciwang", "bilibili")
$pluginArg = $selectedPlugins -join ","

Push-Location $projectRoot
try {
    node ".\gdmusic_plugin_codegen\scripts\generate_gd_skeletons.js" $sourceRoot $outputRoot --plugins $pluginArg
}
finally {
    Pop-Location
}
