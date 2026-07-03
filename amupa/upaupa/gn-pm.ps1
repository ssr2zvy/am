# gn-pm.ps1 - Stop and delete ammachine
# Usage: gn-pm.ps1 [-n] [-Debug]

param(
    [switch]$n,
    [switch]$Debug
)

. "$PSScriptRoot\amhelpers.ps1"

$isDryRun = $n.IsPresent
$isDebug = $Debug.IsPresent
$imagesDir = Resolve-AmPath "am.amupa.vinvin.images"

Write-Host ""
if ($isDryRun) {
    Write-Host "--gn pm n--"
} else {
    Write-Host "--gn pm--"
}
Write-Host ""

# === ammachine ===
Write-Step "ammachine"
if ($isDryRun) {
    Write-N "Stop and delete ammachine."
}

# Check podman installed
if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
    Write-Status "pass"
    Write-Info "Podman not installed."
    Write-Host ""
    Write-Host $(if ($isDryRun) { "--gn pm n--" } else { "--gn pm--" })
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
    Write-Host $(if ($isDryRun) { "--gn pm n--" } else { "--gn pm--" })
    Write-Host ""
    exit 0
}

$status = $inspect | ConvertFrom-Json
if ($isDebug) { Write-Host "debug: state: $($status.State)" }

# Require machine to be stopped first
if ($status.State -eq 'running') {
    Write-Fail "ammachine is running. Stop it first with: gn"
    Write-Host ""
    Write-Host $(if ($isDryRun) { "--gn pm n--" } else { "--gn pm--" })
    Write-Host ""
    exit 1
}

if ($isDryRun) {
    Write-Pass "ammachine stopped. Would delete (images will be lost)."
    Write-Info "To save images first: am, then upaupa vinvin images save, then exit"
    Write-Host ""
    Write-Host "--gn pm n--"
    Write-Host ""
    exit 0
}

# Prompt before deleting
Write-Host ""
Write-Host "WARNING: All container images will be lost when machine is deleted."
Write-Host "To save images first: am, then upaupa vinvin images save, then exit"
Write-Host ""
$confirm = Read-Host "Proceed? (u/N)"
if ($confirm -ne 'u' -and $confirm -ne 'U') {
    Write-Info "Aborted."
    Write-Host ""
    Write-Host "--gn pm--"
    Write-Host ""
    exit 0
}

# Delete machine
Write-Info "Deleting ammachine..."
& podman machine rm -f ammachine
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Failed to delete ammachine."
    Write-Host ""
    Write-Host "--gn pm--"
    Write-Host ""
    exit 1
}

Write-Status "pass"
Write-Info "ammachine deleted."

Write-Host ""
Write-Host "--gn pm--"
Write-Host ""
