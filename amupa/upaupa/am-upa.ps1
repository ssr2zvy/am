# am-upa.ps1 - Setup WSL and Podman
# Usage: am-upa.ps1 [-n] [-Debug]

param(
    [switch]$n,
    [switch]$Debug
)

. "$PSScriptRoot\amhelpers.ps1"

$isDryRun = $n.IsPresent
$isDebug = $Debug.IsPresent
$amupaDir = Resolve-AmPath "am.amupa"
$versionsFile = Resolve-AmPath "am.amupa.versions"

Write-Host ""
if ($isDryRun) {
    Write-Host "--am upa n--"
} else {
    Write-Host "--am upa--"
}
Write-Host ""

# Admin check
Write-Step "administrator"
if ($isDryRun) {
    Write-N "Check for administrator privileges."
}
if (-not (Test-Admin)) {
    Write-Status "FAIL"
    Write-Info "Must run as Administrator."
    if (-not $isDryRun) {
        Show-AdminHelp "am upa"
        exit 1
    }
} else {
    Write-Pass "Running as Administrator."
}
Write-Host ""

# WSL features
# This runs before the version-pins prompt because it can exit early for
# a reboot (feature enable or stale-WSL cleanup). No point making the
# user review versions.txt if the script is about to bail.
Write-Step "WSL features"
if ($isDryRun) {
    Write-N "Check/enable Windows features for WSL."
}
try {
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction Stop
    $vmpFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop
    $wslEnabled = $wslFeature -and ($wslFeature.State -like "Enabled*")
    $vmpEnabled = $vmpFeature -and ($vmpFeature.State -like "Enabled*")

    if (-not $wslEnabled -or -not $vmpEnabled) {
        # Check for stale state: features off but WSL active
        $wslCheck = & wsl --status 2>&1
        if ($LASTEXITCODE -eq 0) {
            if ($isDryRun) {
                Write-Pass "WSL features not enabled but WSL active (stale). Would uninstall and restart."
                Write-Host ""
                Write-Host "--am upa n--"
                Write-Host ""
                exit 0
            } else {
                Write-Info "WSL features not enabled but WSL still active."
                Write-InfoCont "Cleaning up stale WSL install..."
                & wsl --uninstall 2>&1 | Out-Null
                Write-Pass "Stale WSL removed."
                Write-InfoCont "Restart required before reinstall."
                Write-InfoCont "After reboot, open Admin PowerShell: cd ~; am upa"
                Read-Confirm "understood"
                if (Read-Prompt "  Reboot now? (u/N)") {
                    Restart-Computer -Force
                }
                Write-Host ""
                exit 1
            }
        } else {
            # Features off, no stale WSL - enable features
            if ($isDryRun) {
                Write-Pass "Would enable WSL features and reboot."
                Write-InfoCont "After reboot, open Admin PowerShell: cd ~; am upa"
                Write-Host ""
                Write-Host "--am upa n--"
                Write-Host ""
                exit 0
            } else {
                Write-Info "Enabling VirtualMachinePlatform..."
                & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart 2>&1 | Out-Null
                Write-Info "Enabling Microsoft-Windows-Subsystem-Linux..."
                & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart 2>&1 | Out-Null
                Write-Pass "WSL features enabled."
                Write-InfoCont "Restart required to activate features."
                Write-InfoCont "After reboot, open Admin PowerShell: cd ~; am upa"
                Read-Confirm "understood"
                if (Read-Prompt "  Reboot now? (u/N)") {
                    Restart-Computer -Force
                }
                Write-Host ""
                exit 0
            }
        }
    } else {
        Write-Pass "WSL features enabled."
    }
} catch {
    Write-Pass "Cannot check features (continuing)."
}
Write-Host ""

# Version pins
# Read host pins from versions.txt and (in non-dry-run) prompt the user
# to edit the file before proceeding so they can adjust WSL / Podman
# versions or URLs without re-editing this script. Placed after the
# WSL features step because that step can exit early for a reboot.
Write-Step "version pins"
if ($isDryRun) {
    Write-N "Show host version pins from versions.txt."
}
if (-not (Test-Path $versionsFile)) {
    @(
        "# Host platform versions. Edit values, save, then continue.",
        "WSL=",
        "WSL_URL=",
        "",
        "Podman=",
        "Podman_URL="
    ) | Out-File -FilePath $versionsFile -Encoding UTF8
    Write-Info "Created $versionsFile (template)."
}
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
$pinnedWslVersion = $pins["WSL"]
$pinnedWslUrl = $pins["WSL_URL"]
$pinnedPodmanVersion = $pins["Podman"]
$pinnedPodmanUrl = $pins["Podman_URL"]
Write-Host ""

# WSL
Write-Step "WSL"
if ($isDryRun) {
    Write-N "Install WSL."
}
$wslInstalled = $false
$wslVersion = $null
$wslStatus = & wsl --status 2>&1
if ($LASTEXITCODE -eq 0) {
    $wslInstalled = $true
    $wslVersionOutput = & wsl --version 2>&1
    if ($wslVersionOutput -match "(\d+\.\d+\.\d+)") {
        $wslVersion = $Matches[1]
    }
}
if ($wslInstalled) {
    if ($wslVersion) {
        Write-Pass "WSL $wslVersion installed."
    } else {
        Write-Pass "WSL installed."
    }
} else {
    if ($isDryRun) {
        if ($pinnedWslVersion) {
            Write-Pass "WSL not installed. Would install (target pin: $pinnedWslVersion) and reboot."
        } else {
            Write-Pass "WSL not installed. Would install (latest, no pin set) and reboot."
        }
        Write-InfoCont "After reboot, open Admin PowerShell: cd ~; am upa"
    } else {
        Write-Info "Installing WSL..."
        Write-InfoCont "WSL may pause during download - press Enter if it stalls."
        & wsl --install --no-distribution
        if ($LASTEXITCODE -eq 0) {
            Write-Pass "WSL installed via Microsoft Store."
            if ($pinnedWslVersion) {
                Write-InfoCont "Pinned WSL version is $pinnedWslVersion. Run 'am -u' after reboot to align to the pin."
            }
            Write-InfoCont "Restart required for Virtual Machine Platform to activate."
            Write-InfoCont "After reboot, open Admin PowerShell: cd ~; am upa"
            Read-Confirm "understood"
            if (Read-Prompt "  Reboot now? (u/N)") {
                Restart-Computer -Force
            }
            Write-Host ""
            exit 0
        } elseif ($pinnedWslUrl) {
            Write-Info "Microsoft Store install failed. Falling back to URL: $pinnedWslUrl"
            $msixPath = "$amupaDir\wsl_pinned.msixbundle"
            try {
                Invoke-WebRequest -Uri $pinnedWslUrl -OutFile $msixPath -TimeoutSec 600 -UseBasicParsing -ErrorAction Stop
                Add-AppxPackage -Path $msixPath -ErrorAction Stop
                Remove-Item $msixPath -ErrorAction SilentlyContinue
                Write-Pass "WSL installed from pinned URL."
                Write-InfoCont "Restart required for Virtual Machine Platform to activate."
                Write-InfoCont "After reboot, open Admin PowerShell: cd ~; am upa"
                Read-Confirm "understood"
                if (Read-Prompt "  Reboot now? (u/N)") {
                    Restart-Computer -Force
                }
                Write-Host ""
                exit 0
            } catch {
                Write-Fail "WSL fallback install failed: $_"
                Remove-Item $msixPath -ErrorAction SilentlyContinue
                exit 1
            }
        } else {
            Write-Fail "WSL install failed and no WSL_URL pin set in versions.txt."
            exit 1
        }
    }
}
Write-Host ""

# Podman
Write-Step "Podman"
if ($isDryRun) {
    Write-N "Check/install Podman."
}
$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    Write-Fail "winget not available."
    if (-not $isDryRun) {
        Write-Info "Install App Installer from Microsoft Store."
        exit 1
    }
}

$podman = Get-Command podman -ErrorAction SilentlyContinue
if ($podman) {
    $currentVersion = & podman --version 2>&1
    if ($isDryRun) {
        Write-Pass "Podman installed: $currentVersion"
    } else {
        Write-Info "Current: $currentVersion"
        Write-Info "Checking for updates..."
        $upgradeOutput = & winget upgrade --id RedHat.Podman 2>&1
        if ($upgradeOutput -match "No applicable upgrade found") {
            Write-Pass "Podman is up to date."
        } else {
            if (Read-Prompt "  Update Podman? (u/N)") {
                Write-Info "Updating Podman..."
                winget upgrade --id RedHat.Podman --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -eq 0) {
                    $newVersion = & podman --version 2>&1
                    Write-Pass "Podman updated: $newVersion"
                } else {
                    Write-Info "Update failed."
                }
            } else {
                Write-Skip "Skipped Podman update."
            }
        }
    }
} else {
    if ($isDryRun) {
        if ($pinnedPodmanVersion) {
            Write-Pass "Podman not installed. Would install (target pin: $pinnedPodmanVersion)."
        } else {
            Write-Pass "Podman not installed. Would install (latest, no pin set)."
        }
    } else {
        if (Read-Prompt "  Install Podman? (u/N)") {
            Write-Info "Installing Podman..."
            if ($pinnedPodmanVersion) {
                winget install --id RedHat.Podman --version $pinnedPodmanVersion --accept-source-agreements --accept-package-agreements
            } else {
                winget install --id RedHat.Podman --accept-source-agreements --accept-package-agreements
            }
            if ($LASTEXITCODE -ne 0 -and $pinnedPodmanUrl) {
                Write-Info "winget install failed. Falling back to URL: $pinnedPodmanUrl"
                $setupPath = "$amupaDir\podman_pinned-setup.exe"
                try {
                    Invoke-WebRequest -Uri $pinnedPodmanUrl -OutFile $setupPath -TimeoutSec 600 -UseBasicParsing -ErrorAction Stop
                    Start-Process -FilePath $setupPath -ArgumentList "/quiet" -Wait -NoNewWindow
                    Remove-Item $setupPath -ErrorAction SilentlyContinue
                    $global:LASTEXITCODE = 0
                } catch {
                    Write-Fail "Podman fallback install failed: $_"
                    Remove-Item $setupPath -ErrorAction SilentlyContinue
                    exit 1
                }
            }
            if ($LASTEXITCODE -eq 0) {
                # Refresh PATH so podman is available immediately
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                Write-Pass "Podman installed."
                Write-Info "Waiting 120 seconds for Podman to settle before podman init..."
                Write-InfoCont "Press Enter to skip."
                $countdown = 120
                while ($countdown -gt 0) {
                    Write-Host "`r  $countdown seconds remaining..." -NoNewline
                    $waited = 0
                    while ($waited -lt 10 -and $countdown -gt 0) {
                        Start-Sleep -Milliseconds 100
                        $waited++
                        if ([Console]::KeyAvailable) {
                            $key = [Console]::ReadKey($true)
                            if ($key.Key -eq 'Enter') {
                                $countdown = 0
                                break
                            }
                        }
                    }
                    if ($countdown -gt 0) { $countdown-- }
                }
                Write-Host "`r                              `r" -NoNewline
                Write-Info "Ready. Run: am -pm"
            } else {
                Write-Fail "Podman install failed."
                exit 1
            }
        } else {
            Write-Skip "Skipped Podman install."
        }
    }
}

# Save versions to versions.txt. This script owns WSL and Podman value
# lines exclusively (container-build vendored archives live in a
# separate file at amupa/upaupaLocal/versions.txt). We use
# Set-VersionsKey to update only the WSL and Podman version lines so
# user-edited URLs and the CVE comment block above them survive intact.
if (-not $isDryRun) {
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

    if ($finalWslVersion) { Set-VersionsKey $versionsFile "WSL" $finalWslVersion }
    if ($finalPodmanVersion) { Set-VersionsKey $versionsFile "Podman" $finalPodmanVersion }

    if ($pinnedWslVersion -and $finalWslVersion -and ($pinnedWslVersion -ne $finalWslVersion)) {
        Write-Info "Installed WSL ($finalWslVersion) differs from pinned ($pinnedWslVersion). Run 'am -u' to align."
    }
    if ($pinnedPodmanVersion -and $finalPodmanVersion -and ($pinnedPodmanVersion -ne $finalPodmanVersion)) {
        Write-Info "Installed Podman ($finalPodmanVersion) differs from pinned ($pinnedPodmanVersion). Run 'am -u' to align."
    }
}

# End
Write-Host ""
if ($isDryRun) {
    Write-Host "--am upa n--"
} else {
    Write-Host "--am upa--"
}
Write-Host ""
