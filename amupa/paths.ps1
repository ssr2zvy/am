param(
    [Parameter(Position=0)]
    [string]$Alias,
    [switch]$List
)
function Resolve-AmRoot {
    param([string]$ScriptDir)

    if (-not [string]::IsNullOrWhiteSpace($env:AM_ROOT_OVERRIDE)) {
        $override = $env:AM_ROOT_OVERRIDE.Trim()
        if (Test-Path (Join-Path $override "amupa")) {
            return $override
        }
    }

    $hintFile = Join-Path $ScriptDir "am_root.path"
    if (Test-Path $hintFile) {
        $hint = (Get-Content $hintFile -TotalCount 1).Trim()
        if (-not [string]::IsNullOrWhiteSpace($hint) -and (Test-Path (Join-Path $hint "amupa"))) {
            return $hint
        }
    }

    if ((Split-Path -Leaf $ScriptDir) -ieq "amupa") {
        $parent = Split-Path -Parent $ScriptDir
        if (Test-Path (Join-Path $parent "amupa")) {
            return $parent
        }
    }

    $parentDir = Split-Path -Parent $ScriptDir
    if (Test-Path (Join-Path $parentDir "amupa")) {
        return $parentDir
    }

    $fallback = "C:\Users\vin\am"
    if (Test-Path (Join-Path $fallback "amupa")) {
        return $fallback
    }

    throw "paths.ps1: unable to resolve am root"
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AmRoot = Resolve-AmRoot -ScriptDir $ScriptDir
$Amupa = Join-Path $AmRoot "amupa"

$Map = @{
    "am.root" = $AmRoot
    "am.amupa" = $Amupa
    "am.amupa.paths.ps1" = (Join-Path $Amupa "paths.ps1")
    "am.amupa.upaupa" = (Join-Path $Amupa "upaupa")
    "am.amupa.machine" = (Join-Path $Amupa "machine")
    "am.amupa.machine.taml" = (Join-Path $Amupa "machine\ammachine.taml")
    "am.amupa.machine.amsetup" = (Join-Path $Amupa "machine\amsetup.sh")
    "am.amupa.machine.ammachine" = (Join-Path $Amupa "machine\ammachine.sh")
    "am.amupa.versions" = (Join-Path $Amupa "versions.txt")
    "am.amupa.vinvin" = (Join-Path $Amupa "vinvin")
    "am.amupa.vinvin.images" = (Join-Path $Amupa "vinvin\images")
    "am.amc" = (Join-Path $AmRoot "amc")
    "am.amdcc" = (Join-Path $AmRoot "amdcc")
    "am.amdcc.am-mount-host" = (Join-Path $AmRoot "amdcc\am-mount-host")
    "am.amdcc.am-mount-host.am" = (Join-Path $AmRoot "amdcc\am-mount-host\am")
    "am.amdcc.am-mount-host.am.build-output" = (Join-Path $AmRoot "amdcc\am-mount-host\am\build-output")
    "am.amdcc.build-output.host" = (Join-Path $AmRoot "amdcc\am-mount-host\am\build-output")
    "amdcc.build-output.host" = (Join-Path $AmRoot "amdcc\am-mount-host\am\build-output")
}

if ($List) {
    $Map.Keys | Sort-Object
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Alias)) {
    Write-Error "Usage: paths.ps1 <alias> or paths.ps1 -List"
    exit 1
}

if ($Map.ContainsKey($Alias)) {
    Write-Output $Map[$Alias]
    exit 0
}

Write-Error "paths.ps1: unknown alias '$Alias'"
exit 1
