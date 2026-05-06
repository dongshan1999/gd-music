param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [Parameter(Position = 1)]
    [string]$Contains = "",

    [int]$Start = 1,

    [int]$End = 0,

    [switch]$LineNumbers
)

$env:PYTHONIOENCODING = "utf-8"

$scriptPath = Join-Path $PSScriptRoot "show_utf8.py"
$arguments = @($scriptPath, $Path, "--start", $Start)

if ($End -gt 0) {
    $arguments += @("--end", $End)
}
if (-not [string]::IsNullOrEmpty($Contains)) {
    $arguments += @("--contains", $Contains)
}
if ($LineNumbers) {
    $arguments += "--line-numbers"
}

python @arguments
