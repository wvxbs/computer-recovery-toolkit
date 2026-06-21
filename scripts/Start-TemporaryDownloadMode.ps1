[CmdletBinding()]
param(
    [switch]$Watchdog,
    [switch]$RestoreOnly,
    [int]$ParentPid,
    [string]$StatePath,
    [int]$CpuMaxPercent = 70,
    [int]$DisplayTimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"

$ProgramDataRoot = Join-Path $env:ProgramData "ComputerRecoveryToolkit"
$DefaultStatePath = Join-Path $ProgramDataRoot "temporary-download-mode-state.json"
$LogPath = Join-Path $ProgramDataRoot "temporary-download-mode-latest.log"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-OnAcPower {
    try {
        $battery = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $battery.PowerOnline) { return [bool]$battery.PowerOnline }
    } catch {}
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        return [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq "Online"
    } catch {
        return $false
    }
}

function Get-PowerSettingIndex {
    param([string]$Subgroup, [string]$Setting)
    $text = (& powercfg.exe /query SCHEME_CURRENT $Subgroup $Setting 2>&1 | Out-String)
    $match = [regex]::Match($text, "(?im)(?:AC|Correntes Alternadas).*?:\s*0x([0-9a-f]+)")
    if (-not $match.Success) { return $null }
    return [Convert]::ToInt32($match.Groups[1].Value, 16)
}

function Invoke-PowerCfgSafe {
    param([string[]]$Arguments)
    $out = & powercfg.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log ("Warning: powercfg {0} exited with {1}: {2}" -f ($Arguments -join " "), $LASTEXITCODE, (($out | Out-String).Trim()))
    }
}

function Save-CurrentState {
    param([string]$Path)
    $settings = @(
        @{ Name = "DisplayTimeoutAC"; Subgroup = "SUB_VIDEO"; Setting = "VIDEOIDLE"; Value = $DisplayTimeoutSeconds },
        @{ Name = "StandbyTimeoutAC"; Subgroup = "SUB_SLEEP"; Setting = "STANDBYIDLE"; Value = 0 },
        @{ Name = "HibernateTimeoutAC"; Subgroup = "SUB_SLEEP"; Setting = "HIBERNATEIDLE"; Value = 0 },
        @{ Name = "UnattendedSleepAC"; Subgroup = "SUB_SLEEP"; Setting = "UNATTENDSLEEP"; Value = 0 },
        @{ Name = "LidCloseAC"; Subgroup = "SUB_BUTTONS"; Setting = "LIDACTION"; Value = 0 },
        @{ Name = "ProcessorMinAC"; Subgroup = "SUB_PROCESSOR"; Setting = "PROCTHROTTLEMIN"; Value = 5 },
        @{ Name = "ProcessorMaxAC"; Subgroup = "SUB_PROCESSOR"; Setting = "PROCTHROTTLEMAX"; Value = $CpuMaxPercent },
        @{ Name = "WirelessPowerAC"; Subgroup = "19cbb8fa-5279-450e-9fac-8a3d5fedd0c1"; Setting = "12bbebe6-58d6-4636-95bb-3217ef867c1a"; Value = 0 },
        @{ Name = "ConnectivityStandbyAC"; Subgroup = "SUB_NONE"; Setting = "CONNECTIVITYINSTANDBY"; Value = 1 }
    )
    $saved = foreach ($item in $settings) {
        [pscustomobject]@{
            Name = $item.Name
            Subgroup = $item.Subgroup
            Setting = $item.Setting
            OldAC = Get-PowerSettingIndex -Subgroup $item.Subgroup -Setting $item.Setting
            NewAC = $item.Value
        }
    }
    [pscustomobject]@{
        CreatedAt = (Get-Date).ToString("o")
        ComputerName = $env:COMPUTERNAME
        ParentPid = $PID
        Settings = @($saved)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Apply-DownloadMode {
    param([string]$Path)
    $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($item in $state.Settings) {
        Invoke-PowerCfgSafe @("/setacvalueindex", "SCHEME_CURRENT", $item.Subgroup, $item.Setting, ([string]$item.NewAC))
    }
    Invoke-PowerCfgSafe @("/setactive", "SCHEME_CURRENT")
}

function Restore-DownloadMode {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($item in $state.Settings) {
        if ($null -eq $item.OldAC) { continue }
        Invoke-PowerCfgSafe @("/setacvalueindex", "SCHEME_CURRENT", $item.Subgroup, $item.Setting, ([string]$item.OldAC))
    }
    Invoke-PowerCfgSafe @("/setactive", "SCHEME_CURRENT")
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    Write-Log "Temporary download mode restored."
}

function Start-Watchdog {
    param([string]$Path)
    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-Watchdog", "-ParentPid", "$PID", "-StatePath", "`"$Path`"")
    Start-Process -FilePath $ps -ArgumentList $args -WindowStyle Hidden | Out-Null
}

function Set-ExecutionRequired {
    if (-not ("ComputerRecoveryToolkit.NativePower" -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
namespace ComputerRecoveryToolkit {
    public static class NativePower {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern uint SetThreadExecutionState(uint esFlags);
    }
}
"@
    }
    [void][ComputerRecoveryToolkit.NativePower]::SetThreadExecutionState(0x80000000 -bor 0x00000001)
}

function Clear-ExecutionRequired {
    if ("ComputerRecoveryToolkit.NativePower" -as [type]) {
        [void][ComputerRecoveryToolkit.NativePower]::SetThreadExecutionState(0x80000000)
    }
}

New-Item -ItemType Directory -Path $ProgramDataRoot -Force | Out-Null
if (-not $StatePath) { $StatePath = $DefaultStatePath }

if ($Watchdog) {
    while (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 5 }
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $StatePath) { Restore-DownloadMode -Path $StatePath }
    exit 0
}

if ($RestoreOnly) {
    Restore-DownloadMode -Path $StatePath
    exit 0
}

if (-not (Test-Admin)) {
    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit", "-File", "`"$PSCommandPath`"", "-CpuMaxPercent", "$CpuMaxPercent", "-DisplayTimeoutSeconds", "$DisplayTimeoutSeconds")
    Start-Process -FilePath $ps -Verb RunAs -ArgumentList $args | Out-Null
    exit 0
}

if (-not (Test-OnAcPower)) {
    Write-Warning "Temporary download mode refused: connect AC power first."
    Write-Host "Press Enter to close."
    [void][Console]::ReadLine()
    exit 1
}

$cancelled = $false
[Console]::TreatControlCAsInput = $false
$cancelHandler = [ConsoleCancelEventHandler]{
    param($sender, $eventArgs)
    $script:cancelled = $true
    $eventArgs.Cancel = $true
}
[Console]::add_CancelKeyPress($cancelHandler)

try {
    if (Test-Path -LiteralPath $StatePath) {
        Write-Log "Pending state found; restoring before starting a new session."
        Restore-DownloadMode -Path $StatePath
    }
    Save-CurrentState -Path $StatePath
    Apply-DownloadMode -Path $StatePath
    Start-Watchdog -Path $StatePath
    Clear-Host
    Write-Host "Temporary download mode is active." -ForegroundColor Green
    Write-Host ""
    Write-Host "- Exists only while this window is open."
    Write-Host "- If AC power is removed, settings are restored and the script exits."
    Write-Host "- Display turns off quickly, lid close does not sleep on AC, CPU is capped at $CpuMaxPercent%."
    Write-Host "- Press Q, Enter, Esc, or Ctrl+C to restore and exit."
    Write-Host ""

    while (-not $cancelled) {
        if (-not (Test-OnAcPower)) {
            Write-Host "AC power removed. Restoring settings..." -ForegroundColor Yellow
            break
        }
        Set-ExecutionRequired
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -in @([ConsoleKey]::Q, [ConsoleKey]::Enter, [ConsoleKey]::Escape)) { break }
        }
        Start-Sleep -Seconds 5
    }
} finally {
    Clear-ExecutionRequired
    [Console]::remove_CancelKeyPress($cancelHandler)
    Restore-DownloadMode -Path $StatePath
}
