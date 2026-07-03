# am-u.ps1 - Update WSL and Podman while preserving images
# Usage: am-u.ps1 [-n] [-Debug]

param(
    [switch]$n,
    [switch]$Debug
)

. "$PSScriptRoot\amhelpers.ps1"

$isDryRun = $n.IsPresent
$isDebug = $Debug.IsPresent

# Paths for backup files
$amupaDir = Resolve-AmPath "am.amupa"
$backupDir = $amupaDir
$tarPath = "$backupDir\amu_backup.tar"
$imagesPath = "$backupDir\amu_backup_images.txt"
$metaPath = "$backupDir\amu_backup_meta.txt"
$playbook = Resolve-AmPath "am.amupa.machine.taml"
$versionsFile = Resolve-AmPath "am.amupa.versions"

Write-Host ""
if ($isDryRun) {
    Write-Host "--am u n--"
} else {
    Write-Host "--am u--"
}
Write-Host ""

# ========================================================================
# Step 0: Admin check (required for Add-AppxPackage sideloading)
# ========================================================================
Write-Step "administrator"
if ($isDryRun) {
    Write-N "Check for administrator privileges."
}
if (-not (Test-Admin)) {
    if ($isDryRun) {
        Write-Pass "Not admin. Would require admin for actual update."
    } else {
        Write-Status "FAIL"
        Write-Info "Must run as Administrator (required for WSL update)."
        Write-Host ""
        Write-InfoCont "=== How to open Admin PowerShell ==="
        Write-InfoCont ""
        Write-InfoCont "SUREFIRE (from any PowerShell or cmd):"
        Write-InfoCont "  Start-Process powershell -Verb RunAs"
        Write-InfoCont ""
        Write-InfoCont "Then run: cd ~; am -u"
        Write-Host ""
        Read-Confirm "understood"
        Write-Host ""
        exit 1
    }
} else {
    Write-Pass "Running as Administrator."
}
Write-Host ""

# ========================================================================
# Step 1: Check for running containers
# ========================================================================
Write-Step "running containers"
if ($isDryRun) {
    Write-N "Check for running containers."
}
$podman = Get-Command podman -ErrorAction SilentlyContinue
if ($podman) {
    $runningContainers = & podman ps --format "{{.Names}}" 2>&1
    if ($LASTEXITCODE -eq 0 -and $runningContainers) {
        $containers = $runningContainers -split "`n" | Where-Object { $_ -match '\S' }
        if ($containers) {
            Write-Fail "Running containers detected: $($containers -join ', ')"
            Write-InfoCont "Stop all containers before updating."
            Write-InfoCont "Run: gn"
            if (-not $isDryRun) {
                Write-Host ""
                exit 1
            }
        } else {
            Write-Pass "No running containers."
        }
    } else {
        Write-Pass "No running containers."
    }
} else {
    Write-Fail "Podman not installed. Run am upa first."
    if (-not $isDryRun) {
        Write-Host ""
        exit 1
    }
}
Write-Host ""

# ========================================================================
# Step 2: Check for re-run (existing backup) or read version pins
# ========================================================================
# Fresh runs read targets from amupa/versions.txt (prompting the user to
# edit it first), so target versions and URLs live in one file instead of
# being typed into Read-Host. Re-runs read the metadata snapshot saved
# during the previous (interrupted) run so the resume path is
# deterministic.
Write-Step "version input"
if ($isDryRun) {
    Write-N "Read target versions from versions.txt."
}
$targetWslVersion = $null
$targetPodmanVersion = $null
$pinnedWslUrl = $null
$pinnedPodmanUrl = $null
$isRerun = $false

if ((Test-Path $tarPath) -and (Test-Path $metaPath)) {
    # Re-run scenario: read target versions from metadata
    $isRerun = $true
    $metaContent = Get-Content $metaPath
    foreach ($line in $metaContent) {
        if ($line -match "^WSL=(.+)$") { $targetWslVersion = $Matches[1] }
        if ($line -match "^WSL_URL=(.+)$") { $pinnedWslUrl = $Matches[1] }
        if ($line -match "^Podman=(.+)$") { $targetPodmanVersion = $Matches[1] }
        if ($line -match "^Podman_URL=(.+)$") { $pinnedPodmanUrl = $Matches[1] }
    }
    Write-Info "Resuming previous update..."
    Write-InfoCont "Target WSL: $targetWslVersion"
    Write-InfoCont "Target Podman: $targetPodmanVersion"
    Write-Pass "Using existing backup."
} else {
    if ($isDryRun) {
        Write-Info "Current pins ($versionsFile):"
        $pins = Read-VersionsFile $versionsFile
        foreach ($k in @("WSL","WSL_URL","Podman","Podman_URL")) {
            $v = $pins[$k]
            if ([string]::IsNullOrWhiteSpace($v)) { $v = "<unset>" }
            Write-InfoCont "$k = $v"
        }
        Write-Pass "Pins displayed (dry run; not prompting for edit)."
    } else {
        $pins = Show-VersionsAndConfirm $versionsFile @("WSL","WSL_URL","Podman","Podman_URL")
        Write-Pass "Pins loaded."
    }
    $targetWslVersion = $pins["WSL"]
    $pinnedWslUrl = $pins["WSL_URL"]
    $targetPodmanVersion = $pins["Podman"]
    $pinnedPodmanUrl = $pins["Podman_URL"]

    if (-not $targetWslVersion -and -not $targetPodmanVersion) {
        Write-Fail "No versions in $versionsFile. Edit the file and re-run."
        Write-Host ""
        exit 1
    }
}
Write-Host ""

# Get current versions for comparison (as strings)
$currentWslVersion = $null
$currentPodmanVersion = $null

$wslVersionOutput = & wsl --version 2>&1
if ($LASTEXITCODE -eq 0 -and $wslVersionOutput) {
    # WSL is installed - extract version from first line that has one
    foreach ($line in ($wslVersionOutput -split "`n")) {
        if ($line -match "(\d+\.\d[\d.]*)") {
            $currentWslVersion = $Matches[1]
            break
        }
    }
}

$podmanVersionOutput = & podman --version 2>&1
if ($LASTEXITCODE -eq 0 -and $podmanVersionOutput -match "(\d+\.\d[\d.]*)") {
    $currentPodmanVersion = $Matches[1]
}

# ========================================================================
# Step 3: Version comparison (dry run shows what would happen)
# ========================================================================
Write-Step "version comparison"
if ($isDryRun) {
    Write-N "Compare current vs target versions."
}

# String comparison for versions (exact match)
if ($targetWslVersion) {
    if (-not $currentWslVersion) {
        Write-Info "WSL: not installed -> $targetWslVersion (install)"
    } elseif ($currentWslVersion -eq $targetWslVersion) {
        Write-Info "WSL: $currentWslVersion -> $targetWslVersion (same, skip)"
    } else {
        Write-Info "WSL: $currentWslVersion -> $targetWslVersion (change)"
    }
}

if ($targetPodmanVersion) {
    if (-not $currentPodmanVersion) {
        Write-Info "Podman: not installed -> $targetPodmanVersion (install)"
    } elseif ($currentPodmanVersion -eq $targetPodmanVersion) {
        Write-Info "Podman: $currentPodmanVersion -> $targetPodmanVersion (same, skip)"
    } else {
        Write-Info "Podman: $currentPodmanVersion -> $targetPodmanVersion (change)"
    }
}
Write-Pass "Comparison complete."
Write-Host ""

# ========================================================================
# Step 4: Disk space check
# ========================================================================
Write-Step "disk space"
if ($isDryRun) {
    Write-N "Check disk space for image backup."
}
if (-not $isRerun) {
    # Estimate image sizes
    $imageSizeOutput = & podman images --format "{{.Size}}" 2>&1
    $totalBytes = 0
    foreach ($size in ($imageSizeOutput -split "`n" | Where-Object { $_ -match '\S' })) {
        $size = $size.Trim()
        if ($size -match "^([\d.]+)\s*(GB|MB|KB|B)$") {
            $num = [double]$Matches[1]
            switch ($Matches[2]) {
                "GB" { $totalBytes += $num * 1GB }
                "MB" { $totalBytes += $num * 1MB }
                "KB" { $totalBytes += $num * 1KB }
                "B"  { $totalBytes += $num }
            }
        }
    }
    $requiredBytes = $totalBytes * 1.5  # 1.5x safety margin
    
    # Check free space on backup drive
    $drive = (Get-Item $backupDir).PSDrive.Name
    $freeSpace = (Get-PSDrive $drive).Free
    
    if ($freeSpace -lt $requiredBytes) {
        $requiredGB = [math]::Round($requiredBytes / 1GB, 2)
        $freeGB = [math]::Round($freeSpace / 1GB, 2)
        Write-Fail "Insufficient disk space."
        Write-InfoCont "Required: ~${requiredGB} GB (estimate with 1.5x margin)"
        Write-InfoCont "Available: ${freeGB} GB"
        if (-not $isDryRun) {
            Write-Host ""
            exit 1
        }
    } else {
        $freeGB = [math]::Round($freeSpace / 1GB, 2)
        Write-Pass "Sufficient disk space (${freeGB} GB free)."
    }
} else {
    Write-Pass "Skipped (re-run)."
}
Write-Host ""

# ========================================================================
# Step 5: Network connectivity check
# ========================================================================
Write-Step "network"
if ($isDryRun) {
    Write-N "Check network connectivity."
}
$networkOk = $true

if ($targetWslVersion) {
    try {
        $null = Invoke-WebRequest -Uri "https://api.github.com" -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        Write-Info "GitHub: reachable"
    } catch {
        Write-Info "GitHub: unreachable"
        $networkOk = $false
    }
}

if ($targetPodmanVersion) {
    $wingetUpdate = & winget source update 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Info "winget: reachable"
    } else {
        Write-Info "winget: unreachable"
        $networkOk = $false
    }
}

if (-not $networkOk) {
    Write-Fail "Network connectivity required."
    if (-not $isDryRun) {
        Write-Host ""
        exit 1
    }
} else {
    Write-Pass "Network OK."
}
Write-Host ""

# ========================================================================
# Step 6: Validate versions exist
# ========================================================================
# WSL_URL from versions.txt is the source of truth when set; we only fall
# back to the GitHub releases API when no URL is pinned (e.g. the user
# left WSL_URL blank). This avoids brittle assumptions about asset names
# and keeps the script working even if GitHub rate-limits anonymous API
# calls.
Write-Step "validate versions"
if ($isDryRun) {
    Write-N "Validate target versions exist."
}
$wslAssetUrl = $null
$versionsValid = $true

if ($targetWslVersion) {
    Write-Info "Checking WSL ${targetWslVersion}..."
    if ($pinnedWslUrl) {
        $wslAssetUrl = $pinnedWslUrl
        Write-Info "WSL ${targetWslVersion}: using pinned WSL_URL"
    } else {
        try {
            $releaseUrl = "https://api.github.com/repos/microsoft/WSL/releases/tags/$targetWslVersion"
            $release = Invoke-RestMethod -Uri $releaseUrl -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
            $asset = $release.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
            if ($asset) {
                $wslAssetUrl = $asset.browser_download_url
                Write-Info "WSL ${targetWslVersion}: valid (found $($asset.name))"
            } else {
                Write-Fail "WSL ${targetWslVersion}: no .msixbundle found in release."
                $versionsValid = $false
            }
        } catch {
            Write-Fail "WSL ${targetWslVersion}: not found on GitHub (and no WSL_URL pinned)."
            Write-InfoCont "Set WSL_URL in $versionsFile or check https://github.com/microsoft/WSL/releases"
            $versionsValid = $false
        }
    }
}

if ($targetPodmanVersion) {
    Write-Info "Checking Podman ${targetPodmanVersion}..."
    $wingetShow = & winget show --id RedHat.Podman --version $targetPodmanVersion 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Info "Podman ${targetPodmanVersion}: valid"
    } else {
        Write-Fail "Podman ${targetPodmanVersion}: not found in winget."
        Write-InfoCont "Run: winget search RedHat.Podman --versions"
        $versionsValid = $false
    }
}

if (-not $versionsValid -and -not $isDryRun) {
    Write-Host ""
    exit 1
}
if ($versionsValid) {
    Write-Pass "Versions validated."
}
Write-Host ""

# ========================================================================
# Dry run ends here - show summary and exit
# ========================================================================
if ($isDryRun) {
    Write-Step "summary"
    Write-N "What would happen with actual run."
    
    # Count images
    $imageList = & podman images --format "{{.Repository}}:{{.Tag}}" 2>&1
    $images = $imageList -split "`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '<none>' }
    $imageCount = $images.Count
    
    Write-Info "Would backup $imageCount images to tar"
    
    if ($targetWslVersion -and $currentWslVersion -ne $targetWslVersion) {
        Write-Info "Would update WSL: $currentWslVersion -> $targetWslVersion"
    } elseif ($targetWslVersion) {
        Write-Info "Would skip WSL (already at $targetWslVersion)"
    }
    
    if ($targetPodmanVersion -and $currentPodmanVersion -ne $targetPodmanVersion) {
        if ($currentPodmanVersion -and ([version]$targetPodmanVersion -lt [version]$currentPodmanVersion)) {
            Write-Info "Would DOWNGRADE Podman: $currentPodmanVersion -> $targetPodmanVersion"
        } else {
            Write-Info "Would update Podman: $currentPodmanVersion -> $targetPodmanVersion"
        }
    } elseif ($targetPodmanVersion) {
        Write-Info "Would skip Podman (already at $targetPodmanVersion)"
    }
    
    Write-Info "Would recreate ammachine"
    Write-Info "Would restore $imageCount images from tar"
    Write-Info "Would cleanup backup files"
    
    Write-Pass "Dry run complete."
    Write-Host ""
    Write-Host "--am u n--"
    Write-Host ""
    exit 0
}

# ========================================================================
# Step 6: Save images (skip if re-run)
# ========================================================================
Write-Step "save images"
if (-not $isRerun) {
    # Capture image list
    $imageList = & podman images --format "{{.Repository}}:{{.Tag}}" 2>&1
    $images = $imageList -split "`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '<none>' } | Sort-Object
    
    if ($images.Count -eq 0) {
        Write-Info "No images to backup."
    } else {
        Write-Info "Found $($images.Count) images to backup..."
        
        # Save image list to file
        $images | Out-File -FilePath $imagesPath -Encoding UTF8
        
        # Save target versions to metadata (include URLs so a resumed
        # run does not need to re-read versions.txt — which the user may
        # have edited again in the meantime).
        @(
            "WSL=$targetWslVersion",
            "WSL_URL=$pinnedWslUrl",
            "Podman=$targetPodmanVersion",
            "Podman_URL=$pinnedPodmanUrl"
        ) | Out-File -FilePath $metaPath -Encoding UTF8
        
        # Save images to tar
        Write-Info "Saving images to $tarPath..."
        Write-InfoCont "This may take several minutes."
        $saveArgs = @("save", "-o", $tarPath) + $images
        & podman @saveArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Failed to save images."
            Remove-Item $tarPath -ErrorAction SilentlyContinue
            Remove-Item $imagesPath -ErrorAction SilentlyContinue
            Remove-Item $metaPath -ErrorAction SilentlyContinue
            Write-Host ""
            exit 1
        }
    }
    Write-Pass "Images saved."
} else {
    Write-Pass "Using existing backup."
}
Write-Host ""

# ========================================================================
# Step 7: Verify tar
# ========================================================================
Write-Step "verify backup"
if (Test-Path $imagesPath) {
    $savedImages = Get-Content $imagesPath | Where-Object { $_ -match '\S' }
    if ($savedImages.Count -gt 0) {
        if (-not (Test-Path $tarPath)) {
            Write-Fail "Backup tar not found: $tarPath"
            Write-Host ""
            exit 1
        }
        $tarSize = (Get-Item $tarPath).Length
        if ($tarSize -eq 0) {
            Write-Fail "Backup tar is empty."
            Write-Host ""
            exit 1
        }
        $tarSizeMB = [math]::Round($tarSize / 1MB, 2)
        Write-Pass "Backup verified (${tarSizeMB} MB)."
    } else {
        Write-Pass "No images to verify."
    }
} else {
    Write-Pass "No images to verify."
}
Write-Host ""

# ========================================================================
# Step 8: Update WSL
# ========================================================================
if ($targetWslVersion) {
    Write-Step "update WSL"
    
    # Check current version
    $currentWslVersion = $null
    $wslVersionOutput = & wsl --version 2>&1
    if ($wslVersionOutput -match "WSL.*?(\d+\.\d+\.\d+)") {
        $currentWslVersion = $Matches[1]
    }
    
    if ($currentWslVersion -eq $targetWslVersion) {
        Write-Pass "WSL already at $targetWslVersion."
    } else {
        Write-Info "Current: $currentWslVersion -> Target: $targetWslVersion"
        
        # Download msixbundle
        $msixPath = "$backupDir\wsl_$targetWslVersion.msixbundle"
        if (-not (Test-Path $msixPath)) {
            Write-Info "Downloading WSL $targetWslVersion..."
            try {
                Invoke-WebRequest -Uri $wslAssetUrl -OutFile $msixPath -TimeoutSec 300
            } catch {
                Write-Fail "Failed to download WSL package."
                Write-Host ""
                exit 1
            }
        } else {
            Write-Info "Using cached download."
        }
        
        # Install via Add-AppxPackage
        Write-Info "Installing WSL $targetWslVersion..."
        try {
            Add-AppxPackage -Path $msixPath -ErrorAction Stop
        } catch {
            Write-Fail "Add-AppxPackage failed: $_"
            Write-InfoCont "You may need Developer Mode enabled or to run as Administrator."
            Write-Host ""
            exit 1
        }
        
        # Test WSL functionality
        Write-Info "Verifying WSL..."
        $wslStatus = & wsl --status 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Info "WSL requires reboot to complete installation."
            Write-InfoCont "After reboot, open Admin PowerShell: cd ~; am -u"
            Write-InfoCont "The update will resume automatically."
            Read-Confirm "understood"
            if (Read-Prompt "  Reboot now? (u/N)") {
                Restart-Computer -Force
            }
            Write-Host ""
            exit 0
        }
        
        # Verify version
        $newWslVersion = $null
        $wslVersionOutput = & wsl --version 2>&1
        if ($wslVersionOutput -match "WSL.*?(\d+\.\d+\.\d+)") {
            $newWslVersion = $Matches[1]
        }
        
        if ($newWslVersion -eq $targetWslVersion) {
            # Cleanup download
            Remove-Item $msixPath -ErrorAction SilentlyContinue
            Write-Pass "WSL updated to $targetWslVersion."
        } else {
            Write-Fail "WSL version mismatch after install."
            Write-InfoCont "Expected: $targetWslVersion, Got: $newWslVersion"
            Write-Host ""
            exit 1
        }
    }
    Write-Host ""
}

# ========================================================================
# Step 9: Update Podman
# ========================================================================
if ($targetPodmanVersion) {
    Write-Step "update Podman"
    
    # Check current version
    $currentPodmanVersion = $null
    $podmanVersionOutput = & podman --version 2>&1
    if ($podmanVersionOutput -match "(\d+\.\d+\.\d+)") {
        $currentPodmanVersion = $Matches[1]
    }
    
    if ($currentPodmanVersion -eq $targetPodmanVersion) {
        Write-Pass "Podman already at $targetPodmanVersion."
    } else {
        Write-Info "Current: $currentPodmanVersion -> Target: $targetPodmanVersion"
        
        # Handle downgrade: uninstall first
        if ($currentPodmanVersion -and ([version]$targetPodmanVersion -lt [version]$currentPodmanVersion)) {
            Write-Info "Downgrade detected. Uninstalling current version..."
            & winget uninstall --id RedHat.Podman --silent 2>&1 | Out-Null
        }
        
        # Install target version (winget first; fall back to pinned URL)
        Write-Info "Installing Podman $targetPodmanVersion..."
        & winget install --id RedHat.Podman --version $targetPodmanVersion --force --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0 -and $pinnedPodmanUrl) {
            Write-Info "winget install failed. Falling back to URL: $pinnedPodmanUrl"
            $setupPath = "$backupDir\podman_$targetPodmanVersion-setup.exe"
            try {
                Invoke-WebRequest -Uri $pinnedPodmanUrl -OutFile $setupPath -TimeoutSec 600 -UseBasicParsing -ErrorAction Stop
                Start-Process -FilePath $setupPath -ArgumentList "/quiet" -Wait -NoNewWindow
                Remove-Item $setupPath -ErrorAction SilentlyContinue
                $global:LASTEXITCODE = 0
            } catch {
                Write-Fail "Podman fallback install failed: $_"
                Remove-Item $setupPath -ErrorAction SilentlyContinue
                Write-Host ""
                exit 1
            }
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Podman install failed."
            Write-Host ""
            exit 1
        }
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Verify version
        $newPodmanVersion = $null
        $podmanVersionOutput = & podman --version 2>&1
        if ($podmanVersionOutput -match "(\d+\.\d+\.\d+)") {
            $newPodmanVersion = $Matches[1]
        }
        
        if ($newPodmanVersion -eq $targetPodmanVersion) {
            Write-Pass "Podman updated to $targetPodmanVersion."
        } else {
            Write-Fail "Podman version mismatch after install."
            Write-InfoCont "Expected: $targetPodmanVersion, Got: $newPodmanVersion"
            Write-Host ""
            exit 1
        }
    }
    Write-Host ""
}

# ========================================================================
# Step 10: Recreate machine
# ========================================================================
Write-Step "recreate machine"

# Stop machine if running
$inspect = & podman machine inspect ammachine 2>&1
if ($LASTEXITCODE -eq 0 -and $inspect -ne '[]') {
    Write-Info "Stopping ammachine..."
    & podman machine stop ammachine 2>&1 | Out-Null
    Write-Info "Removing ammachine..."
    & podman machine rm -f ammachine 2>&1 | Out-Null
}

# Cleanup orphaned WSL distro
$orphan = & wsl --list --quiet 2>&1 | Where-Object { $_ -match 'podman-ammachine' }
if ($orphan) {
    Write-Info "Cleaning up orphaned WSL distro..."
    & wsl --unregister podman-ammachine 2>&1 | Out-Null
}

# Create new machine.
#
# --memory 8192 / --cpus 4 are not optional — see the same comment in
# am-pm.ps1. The embedded LLM that `am flow` runs (Phi-4-mini-instruct
# Q4_K_M, ~2.5 GB on disk, ~3 GB peak working set at 4K ctx) does not
# fit in podman's 2 GB default VM.
Write-Info "Creating ammachine..."
& podman machine init --memory 8192 --cpus 4 --playbook $playbook ammachine
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Failed to create ammachine."
    & wsl --unregister podman-ammachine 2>&1 | Out-Null
    Write-Host ""
    exit 1
}

# Start machine
Write-Info "Beginning ammachine..."
& podman machine start ammachine
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Failed to begin ammachine."
    Write-Host ""
    exit 1
}
Write-Pass "Machine recreated."
Write-Host ""

# ========================================================================
# Step 11: Reload and verify images
# ========================================================================
Write-Step "reload images"

if ((Test-Path $tarPath) -and (Test-Path $imagesPath)) {
    $savedImages = Get-Content $imagesPath | Where-Object { $_ -match '\S' } | Sort-Object
    
    if ($savedImages.Count -gt 0) {
        Write-Info "Loading images from backup..."
        & podman load -i $tarPath
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Failed to load images."
            Write-InfoCont "Backup preserved at: $tarPath"
            Write-Host ""
            exit 1
        }
        
        # Verify images
        Write-Info "Verifying images..."
        $currentImages = & podman images --format "{{.Repository}}:{{.Tag}}" 2>&1
        $loadedImages = $currentImages -split "`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '<none>' } | Sort-Object
        
        # Compare lists
        $missing = @()
        foreach ($img in $savedImages) {
            if ($loadedImages -notcontains $img) {
                $missing += $img
            }
        }
        
        if ($missing.Count -gt 0) {
            Write-Fail "Some images failed to reload:"
            foreach ($m in $missing) {
                Write-InfoCont "  - $m"
            }
            Write-InfoCont "Backup preserved at: $tarPath"
            Write-Host ""
            exit 1
        }
        Write-Pass "All $($savedImages.Count) images restored."
    } else {
        Write-Pass "No images to restore."
    }
} else {
    Write-Pass "No backup to restore."
}
Write-Host ""

# ========================================================================
# Step 12: Save versions
# ========================================================================
Write-Step "save versions"
$finalWslVersion = $null
$finalPodmanVersion = $null

$wslOut = & wsl --version 2>&1
if ($LASTEXITCODE -eq 0 -and $wslOut) {
    foreach ($line in ($wslOut -split "`n")) {
        if ($line -match "(\d+\.\d[\d.]*)") {
            $finalWslVersion = $Matches[1]
            break
        }
    }
}

$podmanOut = & podman --version 2>&1
if ($LASTEXITCODE -eq 0 -and $podmanOut -match "(\d+\.\d[\d.]*)") {
    $finalPodmanVersion = $Matches[1]
}

# Selective rewrite — only the WSL and Podman version lines are
# overwritten with the installed-on-disk values. Pinned URLs and the
# CVE comment block above them are preserved. Container-build vendored
# archives live in a separate file at amupa/upaupaLocal/versions.txt
# and are not touched here.
if ($finalWslVersion) { Set-VersionsKey $versionsFile "WSL" $finalWslVersion }
if ($finalPodmanVersion) { Set-VersionsKey $versionsFile "Podman" $finalPodmanVersion }
Write-Pass "Versions saved to versions.txt."
Write-Host ""

# ========================================================================
# Step 13: Cleanup
# ========================================================================
Write-Step "cleanup"
Remove-Item $tarPath -ErrorAction SilentlyContinue
Remove-Item $imagesPath -ErrorAction SilentlyContinue
Remove-Item $metaPath -ErrorAction SilentlyContinue
# Also clean up any cached WSL downloads
Get-ChildItem "$backupDir\wsl_*.msixbundle" -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
Write-Pass "Backup files removed."

# End
Write-Host ""
Write-Host "--am u--"
Write-Host ""
Write-Info "Update complete. Run: am"
