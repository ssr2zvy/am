# am.ps1 - Start existing podman machine and SSH
# Usage: am.ps1 [-n] [-Debug]

param(
    [switch]$n,
    [switch]$Debug
)

. "$PSScriptRoot\amhelpers.ps1"

$isDryRun = $n.IsPresent
$isDebug = $Debug.IsPresent

Write-Host ""
if ($isDryRun) {
    Write-Host "--am n--"
} else {
    Write-Host "--am--"
}
Write-Host ""

# === ammachine ===
Write-Step "ammachine"
if ($isDryRun) {
    Write-N "Begin ammachine (must exist)."
}

# Check podman installed
if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
    Write-Status "upa needed"
    Write-Info "Podman not installed. Run am upa first."
    Write-Host ""
    Write-Host $(if ($isDryRun) { "--am n--" } else { "--am--" })
    Write-Host ""
    exit 1
}

# Check machine exists
$inspect = & podman machine inspect ammachine 2>$null
if ($isDebug) { Write-Host "debug: inspect result: $inspect" }

if (-not $inspect -or $inspect -eq '[]') {
    Write-Fail "ammachine not found. Run am -pm to create."
    Write-Host ""
    Write-Host $(if ($isDryRun) { "--am n--" } else { "--am--" })
    Write-Host ""
    exit 1
}

# Check/start machine
$status = $inspect | ConvertFrom-Json
if ($isDebug) { Write-Host "debug: state: $($status.State)" }

if ($status.State -ne 'running') {
    if ($isDryRun) {
        Write-Pass "ammachine stopped. Would begin."
    } else {
        Write-Info "Beginning ammachine..."
        & podman machine start ammachine | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Failed to begin ammachine."
            Write-Host ""
            Write-Host "--am--"
            Write-Host ""
            exit 1
        }
        Write-Info "ammachine began."
    }
} else {
    if ($isDryRun) {
        Write-Pass "ammachine already running."
    } else {
        Write-Info "ammachine already running."
    }
}

if (-not $isDryRun) {
    Write-Status "pass"
}
Write-Host ""

# === ssh ===
Write-Step "ssh"
if ($isDryRun) {
    Write-N "SSH into ammachine."
    Write-Pass "Would SSH into ammachine."
    Write-Host ""
    Write-Host "--am n--"
    Write-Host ""
    exit 0
}

Write-Info "Connecting..."
Write-InfoCont "exit to leave ssh"
Write-InfoCont "upaupa for help"
Write-Status "pass"
Write-Host ""
Write-Host "--am--"
Write-Host ""

# SSH into machine - run amsetup.sh which handles first-run setup and sources ammachine.sh
$amSetupPath = Resolve-AmPath "am.amupa.machine.amsetup"
if ([string]::IsNullOrWhiteSpace($amSetupPath)) {
    Write-Fail "Failed to resolve am setup script path."
    Write-Host ""
    Write-Host "--am--"
    Write-Host ""
    exit 1
}
$amSetupPathForWsl = $amSetupPath -replace '\\','/'
$linuxAmSetupPathRaw = (& wsl wslpath -a "$amSetupPathForWsl")
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($linuxAmSetupPathRaw)) {
    Write-Fail "Failed to convert setup path for WSL: $amSetupPath"
    Write-Host ""
    Write-Host "--am--"
    Write-Host ""
    exit 1
}
$linuxAmSetupPath = $linuxAmSetupPathRaw.Trim()
& podman machine ssh ammachine -t "bash '$linuxAmSetupPath'"
