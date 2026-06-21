[CmdletBinding()]
param(
    [switch]$Apply,
    [ValidateRange(30, 1440)]
    [int]$BatteryHibernateAfterMinutes = 120,
    [ValidateSet("Enable", "Disable", "WindowsManaged")]
    [string]$AcModernStandbyConnectivity = "Enable",
    [ValidateSet("Enable", "Disable", "WindowsManaged")]
    [string]$BatteryModernStandbyConnectivity = "Disable",
    [switch]$SkipEnergySaverPolicy,
    [switch]$SkipIntelGraphicsPolicy,
    [switch]$InstallEnforcerTask,
    [switch]$NoAdminRelaunch
)

$ErrorActionPreference = "Continue"
$ProgramDataRoot = Join-Path $env:ProgramData "ComputerRecoveryToolkit"
$LogPath = Join-Path $ProgramDataRoot "power-policy-latest.log"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-Arg {
    param([string]$Value)
    '"' + ($Value -replace '"', '\"') + '"'
}

function Ensure-Admin {
    if (-not $Apply -or $NoAdminRelaunch -or (Test-IsAdministrator)) { return }
    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", (Quote-Arg $PSCommandPath),
        "-BatteryHibernateAfterMinutes", $BatteryHibernateAfterMinutes,
        "-AcModernStandbyConnectivity", $AcModernStandbyConnectivity,
        "-BatteryModernStandbyConnectivity", $BatteryModernStandbyConnectivity,
        "-Apply",
        "-NoAdminRelaunch"
    )
    if ($SkipEnergySaverPolicy) { $args += "-SkipEnergySaverPolicy" }
    if ($SkipIntelGraphicsPolicy) { $args += "-SkipIntelGraphicsPolicy" }
    if ($InstallEnforcerTask) { $args += "-InstallEnforcerTask" }
    Start-Process $ps -Verb RunAs -ArgumentList $args
    exit
}

function Write-Log {
    param([string]$Message)
    if (-not (Test-Path -LiteralPath $ProgramDataRoot)) { New-Item -ItemType Directory -Path $ProgramDataRoot -Force | Out-Null }
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Convert-ConnectivityValue {
    param([string]$Value)
    switch ($Value) {
        "Disable" { "0" }
        "Enable" { "1" }
        "WindowsManaged" { "2" }
    }
}

function Invoke-PowerCfgChange {
    param(
        [string]$Label,
        [string[]]$PowerArgs
    )

    if (-not $Apply) {
        Write-Host "[DRY RUN] powercfg $($PowerArgs -join ' ')    # $Label"
        return
    }

    Write-Log "powercfg $($PowerArgs -join ' ')    # $Label"
    & powercfg.exe @PowerArgs 2>&1 | ForEach-Object { Write-Log "  $_" }
}

Ensure-Admin

$dcHibernateSeconds = $BatteryHibernateAfterMinutes * 60
$acConnectivity = Convert-ConnectivityValue $AcModernStandbyConnectivity
$dcConnectivity = Convert-ConnectivityValue $BatteryModernStandbyConnectivity

if ($Apply) {
    Remove-Item -LiteralPath $LogPath -Force -ErrorAction SilentlyContinue
    Write-Log "Applying Computer Recovery Toolkit power policy"
} else {
    Write-Host "Preview mode. Add -Apply to change the machine." -ForegroundColor Yellow
}

Invoke-PowerCfgChange "keep hibernation available" @("/hibernate", "on")
Invoke-PowerCfgChange "AC Modern Standby connectivity" @("/setacvalueindex", "SCHEME_CURRENT", "SUB_NONE", "CONNECTIVITYINSTANDBY", $acConnectivity)
Invoke-PowerCfgChange "Battery Modern Standby connectivity" @("/setdcvalueindex", "SCHEME_CURRENT", "SUB_NONE", "CONNECTIVITYINSTANDBY", $dcConnectivity)
Invoke-PowerCfgChange "AC wake timers allowed" @("/setacvalueindex", "SCHEME_CURRENT", "SUB_SLEEP", "RTCWAKE", "1")
Invoke-PowerCfgChange "Battery wake timers disabled" @("/setdcvalueindex", "SCHEME_CURRENT", "SUB_SLEEP", "RTCWAKE", "0")
Invoke-PowerCfgChange "AC never hibernate by idle timer" @("/setacvalueindex", "SCHEME_CURRENT", "SUB_SLEEP", "HIBERNATEIDLE", "0")
Invoke-PowerCfgChange "Battery hibernate after standby/idle window" @("/setdcvalueindex", "SCHEME_CURRENT", "SUB_SLEEP", "HIBERNATEIDLE", "$dcHibernateSeconds")
if (-not $SkipEnergySaverPolicy) {
    Invoke-PowerCfgChange "AC Energy Saver off" @("/setacvalueindex", "SCHEME_CURRENT", "de830923-a562-41af-a086-e3a2c6bad2da", "e69653ca-cf7f-4f05-aa73-cb833fa90ad4", "0")
    Invoke-PowerCfgChange "Battery Energy Saver always on" @("/setdcvalueindex", "SCHEME_CURRENT", "de830923-a562-41af-a086-e3a2c6bad2da", "e69653ca-cf7f-4f05-aa73-cb833fa90ad4", "100")
    Invoke-PowerCfgChange "AC Energy Saver policy normal" @("/setacvalueindex", "SCHEME_CURRENT", "de830923-a562-41af-a086-e3a2c6bad2da", "5c5bb349-ad29-4ee2-9d0b-2b25270f7a81", "0")
    Invoke-PowerCfgChange "Battery Energy Saver policy aggressive" @("/setdcvalueindex", "SCHEME_CURRENT", "de830923-a562-41af-a086-e3a2c6bad2da", "5c5bb349-ad29-4ee2-9d0b-2b25270f7a81", "1")
}
if (-not $SkipIntelGraphicsPolicy) {
    Invoke-PowerCfgChange "AC Intel Graphics maximum performance" @("/setacvalueindex", "SCHEME_CURRENT", "44f3beca-a7c0-460e-9df2-bb8b99e0cba6", "3619c3f2-afb2-4afc-b0e9-e7fef372de36", "2")
    Invoke-PowerCfgChange "Battery Intel Graphics maximum battery life" @("/setdcvalueindex", "SCHEME_CURRENT", "44f3beca-a7c0-460e-9df2-bb8b99e0cba6", "3619c3f2-afb2-4afc-b0e9-e7fef372de36", "0")
}
Invoke-PowerCfgChange "Critical battery hibernates on AC" @("/setacvalueindex", "SCHEME_CURRENT", "SUB_BATTERY", "BATACTIONCRIT", "2")
Invoke-PowerCfgChange "Critical battery hibernates on battery" @("/setdcvalueindex", "SCHEME_CURRENT", "SUB_BATTERY", "BATACTIONCRIT", "2")
Invoke-PowerCfgChange "Critical battery level AC" @("/setacvalueindex", "SCHEME_CURRENT", "SUB_BATTERY", "BATLEVELCRIT", "2")
Invoke-PowerCfgChange "Critical battery level DC" @("/setdcvalueindex", "SCHEME_CURRENT", "SUB_BATTERY", "BATLEVELCRIT", "2")
Invoke-PowerCfgChange "Reactivate current plan" @("/setactive", "SCHEME_CURRENT")

if ($Apply) {
    $wakeDevices = @(& powercfg.exe /devicequery wake_armed 2>$null) | Where-Object { $_ -and ($_ -notmatch "NONE|NENHUM") }
    foreach ($device in $wakeDevices) {
        Write-Log "Disabling wake device: $device"
        & powercfg.exe /devicedisablewake "$device" 2>&1 | ForEach-Object { Write-Log "  $_" }
    }

    try {
        $maintenance = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance"
        if (-not (Test-Path -LiteralPath $maintenance)) { New-Item -Path $maintenance -Force | Out-Null }
        New-ItemProperty -LiteralPath $maintenance -Name WakeUp -Value 0 -PropertyType DWord -Force | Out-Null
        Write-Log "Disabled automatic maintenance wake"
    } catch {
        Write-Log "Could not change automatic maintenance wake: $($_.Exception.Message)"
    }
}

if ($Apply -and $InstallEnforcerTask) {
    $installed = Join-Path $ProgramDataRoot "Apply-ComputerPowerPolicy.ps1"
    Copy-Item -LiteralPath $PSCommandPath -Destination $installed -Force
    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $skipEnergy = if ($SkipEnergySaverPolicy) { " -SkipEnergySaverPolicy" } else { "" }
    $skipIntel = if ($SkipIntelGraphicsPolicy) { " -SkipIntelGraphicsPolicy" } else { "" }
    $taskRun = "$ps -NoProfile -ExecutionPolicy Bypass -File `"$installed`" -Apply -NoAdminRelaunch -BatteryHibernateAfterMinutes $BatteryHibernateAfterMinutes -AcModernStandbyConnectivity $AcModernStandbyConnectivity -BatteryModernStandbyConnectivity $BatteryModernStandbyConnectivity$skipEnergy$skipIntel"
    & schtasks.exe /Create /TN "\ComputerRecoveryToolkit_PowerPolicy" /SC MINUTE /MO 15 /RU SYSTEM /RL HIGHEST /TR $taskRun /F 2>&1 |
        ForEach-Object { Write-Log "schtasks: $_" }
}

if ($Apply) {
    Write-Log "Done. Log: $LogPath"
}

