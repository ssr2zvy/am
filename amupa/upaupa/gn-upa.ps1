# gn-upa.ps1 - Uninstall WSL and Podman
# Usage: gn-upa.ps1 [-n] [-Debug]

param(
    [switch]$n,
    [switch]$Debug
)

. "$PSScriptRoot\amhelpers.ps1"

$isDryRun = $n.IsPresent
$isDebug = $Debug.IsPresent

Write-Host ""
if ($isDryRun) {
    Write-Host "--gn upa n--"
} else {
    Write-Host "--gn upa--"
}
Write-Host ""

# Check for running containers
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
            Write-InfoCont "Stop all containers before uninstalling."
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
    Write-Pass "Podman not installed."
}
Write-Host ""

# Check for other podman machines (warning)
Write-Step "podman machines"
if ($isDryRun) {
    Write-N "Check for existing podman machines."
}
$podman = Get-Command podman -ErrorAction SilentlyContinue
if ($podman) {
    $machineOutput = & podman machine list --format "{{.Name}}" 2>&1
    if ($LASTEXITCODE -eq 0 -and $machineOutput) {
    $machines = $machineOutput -split "`n" | Where-Object { $_ -match '\S' }
        $otherMachines = $machines | Where-Object { ($_ -replace '\*$','') -ne "ammachine" }
        if ($otherMachines) {
            Write-Status "FAIL"
            Write-Info "Other podman machines detected: $($otherMachines -join ', ')"
            Write-InfoCont "These machines will be deleted if you proceed."
            if (-not $isDryRun) {
                if (-not (Read-Prompt "  Continue with uninstall? (u/N)")) {
                    Write-Host "Uninstall cancelled."
                    exit 0
                }
            }
        } elseif ($machines) {
            Write-Pass "Only ammachine found."
        } else {
            Write-Pass "No machines found."
        }
    } else {
        Write-Pass "No machines found."
    }
} else {
    Write-Pass "Podman not installed."
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
        Show-AdminHelp "gn upa"
        exit 1
    }
} else {
    Write-Pass "Running as Administrator."
}

Write-Host ""

# Remove podman machines
Write-Step "remove podman machines"
if ($isDryRun) {
    Write-N "Remove all podman machines."
}
$podman = Get-Command podman -ErrorAction SilentlyContinue
if ($podman) {
    $machineOutput = & podman machine list --format "{{.Name}}" 2>&1
    if ($LASTEXITCODE -eq 0 -and $machineOutput) {
        $machines = $machineOutput -split "`n" | Where-Object { $_ -match '\S' }
        if ($machines) {
            if ($isDryRun) {
                Write-N "Would remove machines: $($machines -join ', ')"
            } else {
                Write-Info "Found machines: $($machines -join ', ')"
                if (Read-Prompt "  Remove all podman machines? (u/N)") {
                    foreach ($m in $machines) {
                        $cleanName = $m -replace '\*$',''
                        Write-Info "Stopping $cleanName..."
                        & podman machine stop $cleanName 2>&1 | Out-Null
                        Write-Info "Removing $cleanName..."
                        & podman machine rm -f $cleanName 2>&1 | Out-Null
                        # podman machine rm does not reliably unregister
                        # the underlying WSL distro (named
                        # "podman-<machine>"). If it survives, the next
                        # `podman machine init` fails with "already
                        # exists on hypervisor". Clean it up explicitly.
                        $wslDistro = "podman-$cleanName"
                        $wslCheck = & wsl --list --quiet 2>&1
                        if ($LASTEXITCODE -eq 0 -and $wslCheck -match [regex]::Escape($wslDistro)) {
                            Write-Info "Unregistering orphaned WSL distro $wslDistro..."
                            & wsl --unregister $wslDistro 2>&1 | Out-Null
                        }
                    }
                    # Also run podman machine reset to clear any
                    # lingering provider-level state that rm missed.
                    & podman machine reset --force 2>&1 | Out-Null
                    Write-Pass "All machines removed."
                } else {
                    Write-Skip "Skipped machine removal."
                }
            }
        } else {
            Write-Pass "No machines found."
        }
    } else {
        Write-Pass "No machines found."
    }
} else {
    Write-Info "Podman not installed, skipping."
}

Write-Host ""

# Clean up orphaned Hyper-V VMs (in case podman machine rm missed them)
Write-Step "Hyper-V cleanup"
if ($isDryRun) {
    Write-N "Remove orphaned Hyper-V VMs."
}
try {
    Import-Module Hyper-V -ErrorAction Stop
    $hypervVMs = Get-VM | Where-Object { $_.Name -eq "ammachine" -or $_.Name -like "podman-*" }
    if ($hypervVMs) {
        if ($isDryRun) {
            Write-Pass "Would remove Hyper-V VMs: $($hypervVMs.Name -join ', ')"
        } else {
            foreach ($vm in $hypervVMs) {
                Write-Info "Removing Hyper-V VM: $($vm.Name)..."
                Stop-VM -Name $vm.Name -Force -ErrorAction SilentlyContinue
                Remove-VM -Name $vm.Name -Force -ErrorAction SilentlyContinue
            }
            Write-Pass "Hyper-V VMs removed."
        }
    } else {
        Write-Pass "No orphaned Hyper-V VMs found."
    }
} catch {
    Write-Pass "Hyper-V module not available (skipping)."
}

Write-Host ""

# Uninstall Podman
Write-Step "uninstall Podman"
if ($isDryRun) {
    Write-N "Uninstall Podman via winget."
}
$podman = Get-Command podman -ErrorAction SilentlyContinue
if ($podman) {
    if ($isDryRun) {
        Write-Pass "Podman installed, would uninstall."
    } else {
        if (Read-Prompt "  Uninstall Podman? (u/N)") {
            Write-Info "Uninstalling Podman via winget..."
            winget uninstall --id RedHat.Podman
            if ($LASTEXITCODE -eq 0) {
                Write-Pass "Podman uninstalled."
            } else {
                Write-Fail "Podman uninstall failed."
            }
        } else {
            Write-Skip "Skipped Podman uninstall."
        }
    }
} else {
    Write-Pass "Podman not installed."
}

Write-Host ""

# Clean up Podman data folders
Write-Step "Podman data"
if ($isDryRun) {
    Write-N "Remove Podman data folders."
}
$podmanFolders = @(
    "$ENV:APPDATA\containers",
    "$ENV:LOCALAPPDATA\containers",
    "$ENV:USERPROFILE\.config\containers",
    "$ENV:USERPROFILE\.local\share\containers"
)
$existingFolders = $podmanFolders | Where-Object { Test-Path $_ }
if ($existingFolders) {
    if ($isDryRun) {
        Write-Pass "Would remove: $($existingFolders -join ', ')"
    } else {
        foreach ($folder in $existingFolders) {
            Write-Info "Removing $folder..."
            Remove-Item -Recurse -Force $folder -ErrorAction SilentlyContinue
        }
        Write-Pass "Podman data cleaned up."
    }
} else {
    Write-Pass "No Podman data folders found."
}

Write-Host ""

# Unregister WSL distros
Write-Step "WSL distros"
if ($isDryRun) {
    Write-N "Unregister all WSL distros."
}
$wslStatus = & wsl --status 2>&1
if ($LASTEXITCODE -eq 0) {
    # WSL is installed, safe to call wsl commands
    $distroOutput = & wsl --list --quiet 2>&1
    if ($LASTEXITCODE -eq 0 -and $distroOutput) {
        $distros = $distroOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and $_ -match '\S' }
        if ($distros) {
            if ($isDryRun) {
                Write-Pass "Would unregister: $($distros -join ', ')"
            } else {
                Write-Info "Found distros: $($distros -join ', ')"
                foreach ($d in $distros) {
                    Write-Info "Unregistering $d..."
                    & wsl --unregister $d 2>&1 | Out-Null
                }
                Write-Pass "All distros unregistered."
            }
        } else {
            Write-Pass "No WSL distros found."
        }
    } else {
        Write-Pass "No WSL distros found."
    }
} else {
    Write-Pass "WSL not installed, skipping."
}

Write-Host ""

# Uninstall WSL
Write-Step "uninstall WSL"
if ($isDryRun) {
    Write-N "Uninstall WSL package."
}
$wslCheck = & wsl --status 2>&1
if ($LASTEXITCODE -eq 0) {
    if ($isDryRun) {
        Write-Pass "WSL installed, would uninstall."
    } else {
        if (Read-Prompt "  Uninstall WSL? (u/N)") {
            Write-Info "Uninstalling WSL..."
            & wsl --uninstall 2>&1 | Out-Null
            Write-Pass "WSL uninstalled."
        } else {
            Write-Skip "Skipped WSL uninstall."
        }
    }
} else {
    Write-Pass "WSL not installed."
}

Write-Host ""

# Disable WSL features
Write-Step "WSL features"
if ($isDryRun) {
    Write-N "Disable Windows features for WSL."
}
try {
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction Stop
    $vmpFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop
} catch {
    Write-Fail "Cannot check Windows features (requires Administrator)."
    if (-not $isDryRun) {
        exit 1
    }
    $wslFeature = $null
    $vmpFeature = $null
}

$wslEnabled = $wslFeature -and ($wslFeature.State -like "Enabled*")
$vmpEnabled = $vmpFeature -and ($vmpFeature.State -like "Enabled*")

if ($wslFeature -and $vmpFeature) {
    if ($wslEnabled -or $vmpEnabled) {
        if ($isDryRun) {
            Write-Pass "Would disable WSL features."
        } else {
            if (Read-Prompt "  Disable WSL features? (u/N)") {
                if ($wslEnabled) {
                    Write-Info "Disabling Microsoft-Windows-Subsystem-Linux..."
                    & dism.exe /online /disable-feature /featurename:Microsoft-Windows-Subsystem-Linux /norestart 2>&1 | Out-Null
                }
                if ($vmpEnabled) {
                    Write-Info "Disabling VirtualMachinePlatform..."
                    & dism.exe /online /disable-feature /featurename:VirtualMachinePlatform /norestart 2>&1 | Out-Null
                }
                Write-Pass "WSL features disabled."
                Write-InfoCont "Restart required to complete feature removal."
                Write-InfoCont "After reboot, run as Administrator: gn upa"
                Read-Confirm "understood"
                if (Read-Prompt "  Reboot now? (u/N)") {
                    Restart-Computer -Force
                }
                Write-Host ""
                exit 0
            } else {
                Write-Skip "Skipped WSL feature disable."
            }
        }
    } else {
        Write-Pass "WSL features not enabled."
        if ($wslFeature) {
            Write-InfoCont "Microsoft-Windows-Subsystem-Linux: $($wslFeature.State)"
        }
        if ($vmpFeature) {
            Write-InfoCont "VirtualMachinePlatform: $($vmpFeature.State)"
        }
    }
}

# End
Write-Host ""
if ($isDryRun) {
    Write-Host "--gn upa n--"
} else {
    Write-Host "--gn upa--"
}
Write-Host ""
