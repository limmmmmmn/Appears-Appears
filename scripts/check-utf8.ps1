param(
    [switch]$Staged
)

$ErrorActionPreference = "Stop"

function Get-TargetFiles {
    if ($Staged) {
        return git diff --cached --name-only --diff-filter=ACMR
    }
    return git ls-files
}

$targets = Get-TargetFiles
if (-not $targets) {
    exit 0
}

$allowedExt = @(".gd", ".tscn", ".tres", ".godot", ".cfg")
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$failures = New-Object System.Collections.Generic.List[string]

foreach ($path in $targets) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        continue
    }
    if (-not (Test-Path -LiteralPath $path)) {
        continue
    }

    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if (-not $allowedExt.Contains($ext)) {
        continue
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        [void]$utf8Strict.GetString($bytes)
    }
    catch {
        $failures.Add($path)
    }
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "[UTF-8 CHECK] Invalid encoding detected in:" -ForegroundColor Red
    foreach ($f in $failures) {
        Write-Host (" - " + $f) -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Fix: reopen and save as UTF-8, then recommit." -ForegroundColor Cyan
    exit 1
}

exit 0
