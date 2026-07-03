# amhelpers.ps1 - Shared helper functions for am/gn scripts

function Write-Step { param([string]$msg) Write-Host "===$msg===" }
function Write-Status { param([string]$status) Write-Host "upa: $status" }
function Write-Pass { param([string]$msg) Write-Host "upa: pass"; Write-Host "info: $msg" }
function Write-Fail { param([string]$msg) Write-Host "upa: fail"; Write-Host "info: $msg" }
function Write-Skip { param([string]$msg) Write-Host "upa: skip"; Write-Host "info: $msg" }
function Write-Info { param([string]$msg) Write-Host "info: $msg" }
function Write-InfoCont { param([string]$msg) Write-Host "      $msg" }
function Write-N { param([string]$msg) Write-Host "n: $msg" }

$script:NgPathsScript = Join-Path (Split-Path -Parent $PSScriptRoot) "paths.ps1"

function Resolve-AmPath {
    param([Parameter(Mandatory = $true)][string]$Alias)
    if (-not (Test-Path $script:NgPathsScript)) {
        throw "paths.ps1 not found at $script:NgPathsScript"
    }
    $resolved = & $script:NgPathsScript $Alias 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolved)) {
        throw "Unknown or unresolved path alias '$Alias'"
    }
    return $resolved.Trim()
}

function Read-Prompt {
    param([string]$msg)
    while ($true) {
        $answer = Read-Host $msg
        if ($answer -match "^[uU]$") { return $true }
        if ($answer -match "^[nN]$") { return $false }
    }
}

function Read-Confirm {
    param([string]$word)
    while ($true) {
        $answer = Read-Host "  Type '$word' to continue"
        if ($answer -eq $word) { return }
    }
}

function Write-Countdown {
    param([int]$seconds, [string]$msg)
    for ($i = $seconds; $i -gt 0; $i--) {
        Write-Host "`r$msg $i seconds remaining..." -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host "`r$msg Done.                        "
}

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Parse a KEY=VALUE versions.txt into a hashtable. Blank lines and lines
# starting with '#' are ignored. Whitespace around key/value is trimmed.
function Read-VersionsFile {
    param([string]$path)
    $pins = @{}
    if (-not (Test-Path $path)) { return $pins }
    foreach ($line in (Get-Content $path)) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed.StartsWith("#")) { continue }
        $eq = $trimmed.IndexOf("=")
        if ($eq -lt 1) { continue }
        $key = $trimmed.Substring(0, $eq).Trim()
        $val = $trimmed.Substring($eq + 1).Trim()
        $pins[$key] = $val
    }
    return $pins
}

# Show the current pins for the listed keys, ask the user to edit the
# file (in their editor of choice) and save, then re-read and return the
# refreshed hashtable. am-upa.ps1 / am-u.ps1 use this so the host
# version pins live in versions.txt as the single source of truth.
function Show-VersionsAndConfirm {
    param([string]$path, [string[]]$keys)
    Write-Info "Current pins ($path):"
    $pins = Read-VersionsFile $path
    foreach ($k in $keys) {
        $v = $pins[$k]
        if ([string]::IsNullOrWhiteSpace($v)) { $v = "<unset>" }
        Write-InfoCont "$k = $v"
    }
    Write-Host ""
    Write-InfoCont "Edit $path in your editor now if you want to change any pin, then save."
    Read-Confirm "continue"
    return (Read-VersionsFile $path)
}

# Selectively update a single KEY=VALUE line in versions.txt, preserving
# every other line (comments, URLs, blank lines, and unrelated keys). If
# the key is absent, it is appended at the end. This replaces the older
# "wholesale two-line rewrite" approach which silently dropped the
# _URL companions and the CVE comment block.
function Set-VersionsKey {
    param([string]$path, [string]$key, [string]$value)
    $found = $false
    $lines = @()
    if (Test-Path $path) {
        foreach ($line in (Get-Content $path)) {
            if ($line -match "^\s*$([regex]::Escape($key))\s*=") {
                $lines += "$key=$value"
                $found = $true
            } else {
                $lines += $line
            }
        }
    }
    if (-not $found) {
        $lines += "$key=$value"
    }
    $lines | Out-File -FilePath $path -Encoding UTF8
}

function Show-AdminHelp {
    param([string]$command)
    Write-Host ""
    Write-InfoCont "=== How to open Admin PowerShell ==="
    Write-InfoCont ""
    Write-InfoCont "SUREFIRE (from any PowerShell or cmd):"
    Write-InfoCont "  Start-Process powershell -Verb RunAs"
    Write-InfoCont ""
    Write-InfoCont "OTHER WAYS:"
    Write-InfoCont "  1. Right-click PowerShell icon > Run as administrator"
    Write-InfoCont "  2. Win+X > Windows PowerShell (Admin)"
    Write-InfoCont "  3. Search 'PowerShell', right-click > Run as administrator"
    Write-InfoCont "  4. Task Manager > File > Run new task > powershell > check 'admin'"
    Write-InfoCont ""
    Write-InfoCont "Then run: cd ~; $command"
    Write-Host ""
    Read-Confirm "understood"
    Write-Host ""
}
