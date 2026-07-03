# gn.ps1 - Stop ammachine
# Usage: gn.ps1 [-n] [-Debug]

param(
    [switch]$n,
    [switch]$Debug
)

. "$PSScriptRoot\amhelpers.ps1"

$isDryRun = $n.IsPresent
$isDebug = $Debug.IsPresent

Write-Host ""
if ($isDryRun) {
    Write-Host "--gn n--"
} else {
    Write-Host "--gn--"
}
Write-Host ""

# === ammachine ===
Write-Step "ammachine"
if ($isDryRun) {
    Write-N "Stop ammachine."
}

# Check podman installed
if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
    Write-Status "pass"
    Write-Info "Podman not installed."
    Write-Host ""
    Write-Host $(if ($isDryRun) { "--gn n--" } else { "--gn--" })
    Write-Host ""
    exit 0
}

# Check if machine exists
$inspect = & podman machine inspect ammachine 2>$null
if ($isDebug) { Write-Host "debug: inspect result: $inspect" }

if (-not $inspect -or $inspect -eq '[]') {
    Write-Status "pass"
    Write-Info "ammachine not found."
    Write-Host ""
    Write-Host $(if ($isDryRun) { "--gn n--" } else { "--gn--" })
    Write-Host ""
    exit 0
}

$status = $inspect | ConvertFrom-Json
if ($isDebug) { Write-Host "debug: state: $($status.State)" }

if ($status.State -ne 'running') {
    if ($isDryRun) {
        Write-Pass "ammachine already stopped."
    } else {
        Write-Status "pass"
        Write-Info "ammachine already stopped."
    }
} else {
    if ($isDryRun) {
        Write-Pass "ammachine running. Would stop."
    } else {
        Write-Info "Stopping ammachine..."
        & podman machine stop ammachine 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Failed to stop ammachine."
            Write-Host ""
            Write-Host "--gn--"
            Write-Host ""
            exit 1
        }
        Write-Info "ammachine stopped."
        Write-Status "pass"
    }
}

Write-Host ""
Write-Host $(if ($isDryRun) { "--gn n--" } else { "--gn--" })
Write-Host ""
