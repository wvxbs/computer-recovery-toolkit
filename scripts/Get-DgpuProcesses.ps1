[CmdletBinding()]
param(
    [switch]$Raw,
    [switch]$WaitOnExit
)

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Exit-Tool {
    param([int]$Code = 0)
    if ($WaitOnExit -and -not $Raw) {
        Write-Host ""
        Read-Host "Press Enter to exit"
    }
    exit $Code
}

function Find-NvidiaSmi {
    $candidates = @(
        (Join-Path $env:WINDIR "System32\nvidia-smi.exe"),
        "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
        "${env:ProgramFiles(x86)}\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $command = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    return $null
}

if (-not $Raw -and -not (Test-IsAdministrator)) {
    Start-Process powershell.exe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-WaitOnExit"
    ) -Verb RunAs
    exit
}

$smi = Find-NvidiaSmi
if (-not $smi) {
    if (-not $Raw) { Write-Host "nvidia-smi.exe not found. This is normal without NVIDIA GPUs." -ForegroundColor Yellow }
    Exit-Tool 0
}

try {
    $gpuApps = & $smi --query-compute-apps=pid,name --format=csv,noheader 2>$null
} catch {
    if (-not $Raw) { Write-Host "Failed to run nvidia-smi: $($_.Exception.Message)" -ForegroundColor Red }
    Exit-Tool 1
}

if (-not $gpuApps) {
    if (-not $Raw) { Write-Host "No process is using the NVIDIA dGPU compute context right now." -ForegroundColor Green }
    Exit-Tool 0
}

$protected = '^(dwm|csrss|winlogon|explorer|System|Registry|Idle)$'
$names = New-Object System.Collections.Generic.List[string]

foreach ($app in $gpuApps) {
    if ([string]::IsNullOrWhiteSpace($app)) { continue }
    $parts = $app -split ",", 2
    if ($parts.Count -lt 2) { continue }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($parts[1].Trim())
    if ($name -and ($name -notmatch $protected)) { [void]$names.Add($name) }
}

$unique = $names | Sort-Object -Unique

if ($Raw) {
    Write-Output ($unique -join ",")
    Exit-Tool 0
}

Write-Host "=== NVIDIA dGPU process diagnostic ===" -ForegroundColor Cyan
if (($unique | Measure-Object).Count -eq 0) {
    Write-Host "Only protected system processes were detected." -ForegroundColor Yellow
    Exit-Tool 0
}

Write-Host "Non-protected processes detected:" -ForegroundColor Magenta
foreach ($p in $unique) { Write-Host (" -> {0}" -f $p) }

$restartScript = Join-Path $PSScriptRoot "Restart-DgpuProcesses.ps1"
$list = $unique -join ","
$cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -List "{1}"' -f $restartScript, $list
Write-Host ""
Write-Host "Copy/paste this only if you want to restart those processes:" -ForegroundColor Yellow
Write-Host $cmd -ForegroundColor Green
Exit-Tool 0

