# am-pm.ps1 - Create podman machine
# Usage: am-pm.ps1 [-n] [-Debug]

param(
    [switch]$n,
    [switch]$Debug
)

. "$PSScriptRoot\amhelpers.ps1"

$isDryRun = $n.IsPresent
$isDebug = $Debug.IsPresent
$machineDir = Resolve-AmPath "am.amupa.machine"
$playbook = Resolve-AmPath "am.amupa.machine.taml"
$imagesDir = Resolve-AmPath "am.amupa.vinvin.images"

Write-Host ""
if ($isDryRun) {
    Write-Host "--am pm n--"
} else {
    Write-Host "--am pm--"
}
Write-Host ""

# === ammachine ===
Write-Step "ammachine"
if ($isDryRun) {
    Write-N "Create ammachine."
}

# Check podman installed
if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
    Write-Status "upa needed"
    Write-Info "Podman not installed. Run am upa first."
    Write-Host ""
    Write-Host $(if ($isDryRun) { "--am pm n--" } else { "--am pm--" })
    Write-Host ""
    exit 1
}

# Check if machine exists
$inspect = & podman machine inspect ammachine 2>$null
if ($isDebug) { Write-Host "debug: inspect result: $inspect" }

if (-not $inspect -or $inspect -eq '[]') {
    # Check if saved images exist
    $hasSavedImages = (Test-Path $imagesDir) -and ((Get-ChildItem -Path $imagesDir -Filter "*.tar" -ErrorAction SilentlyContinue).Count -gt 0)
    
    if ($isDryRun) {
        if ($hasSavedImages) {
            Write-Pass "ammachine not found. Would create (saved images available)."
            Write-Info "After creation: am, then upaupa vinvin images load"
        } else {
            Write-Pass "ammachine not found. Would create."
        }
    } else {
        # Cleanup orphaned WSL distro. podman machine rm does not
        # reliably unregister the underlying WSL distro (named
        # "podman-ammachine"). If it survives, podman machine init
        # fails with "already exists on hypervisor".
        $orphan = & wsl --list --quiet 2>$null | Where-Object { $_ -match 'podman-ammachine' }
        if ($isDebug) { Write-Host "debug: orphan check: $orphan" }
        if ($orphan) {
            Write-Info "Cleaning up orphaned WSL distro..."
            & wsl --unregister podman-ammachine 2>$null | Out-Null
        }

        # Cleanup ghost Hyper-V VMs (only reachable if Hyper-V module
        # is installed — otherwise the catch block skips silently).
        try {
            Import-Module Hyper-V -ErrorAction Stop
            $hvVm = Get-VM | Where-Object { $_.Name -eq 'ammachine' -or $_.Name -like 'podman-*' }
            if ($isDebug) { Write-Host "debug: hyper-v vms: $($hvVm.Name)" }
            if ($hvVm) {
                Write-Info "Cleaning up ghost Hyper-V VM..."
                $hvVm | Stop-VM -Force -ErrorAction SilentlyContinue
                $hvVm | Remove-VM -Force -ErrorAction SilentlyContinue
            }
        } catch {
            if ($isDebug) { Write-Host "debug: hyper-v not available" }
        }

        # Belt-and-suspenders: reset podman's own provider-level state
        # so any lingering metadata that survived rm + WSL unregister
        # is also cleared.
        & podman machine reset --force 2>$null | Out-Null

        # Create machine.
        #
        # --memory 8192 / --cpus 4 are not optional: the embedded LLM that
        # `am flow` runs (Phi-4-mini-instruct Q4_K_M, ~2.5 GB on disk,
        # ~3 GB peak working set at 4K ctx) does not fit in podman's 2 GB
        # default VM. 8 GB leaves room for both amdcc (Zig compile +
        # model) and amc (model + service overhead), plus podman service
        # and OS inside the WSL VM. Mirror this exact flag set in am-u.ps1
        # when the machine is recreated during an update.
        Write-Info "Creating ammachine..."
        if ($isDebug) { Write-Host "debug: playbook: $playbook" }
        & podman machine init --memory 8192 --cpus 4 --playbook $playbook ammachine
        if ($LASTEXITCODE -ne 0) {
            & wsl --unregister podman-ammachine 2>$null | Out-Null
            Write-Fail "Failed to create ammachine."
            Write-Host ""
            Write-Host "--am pm--"
            Write-Host ""
            exit 1
        }
        Write-Info "ammachine created."
        
        # Notify about saved images if available
        if ($hasSavedImages) {
            Write-Host ""
            Write-Info "Saved images found at: $imagesDir"
            Write-Info "To load: am, then upaupa vinvin images load"
        }
    }
} else {
    if ($isDryRun) {
        Write-Pass "ammachine already exists."
    } else {
        Write-Info "ammachine already exists."
        if ($loadImages) {
        Write-Info "Machine already exists. To load images into existing machine, begin it and run podman load manually."
        }
    }
}

if (-not $isDryRun) {
    Write-Status "pass"
    Write-Info "Run: am"
}
Write-Host ""
Write-Host $(if ($isDryRun) { "--am pm n--" } else { "--am pm--" })
Write-Host ""
