[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "reports"),
    [switch]$IncludeEnergyTrace,
    [ValidateRange(15, 300)]
    [int]$EnergyTraceSeconds = 60,
    [switch]$NoZip,
    [switch]$NoAdminRelaunch
)

$ErrorActionPreference = "Continue"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-Arg {
    param([string]$Value)
    '"' + ($Value -replace '"', '\"') + '"'
}

function Relaunch-AdminIfUseful {
    if ($NoAdminRelaunch -or (Test-IsAdministrator)) { return }

    Write-Host "Reopening as administrator for fuller diagnostics..." -ForegroundColor Yellow
    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-Arg $PSCommandPath),
        "-OutputRoot", (Quote-Arg $OutputRoot),
        "-EnergyTraceSeconds", $EnergyTraceSeconds
    )
    if ($IncludeEnergyTrace) { $args += "-IncludeEnergyTrace" }
    if ($NoZip) { $args += "-NoZip" }
    $args += "-NoAdminRelaunch"
    Start-Process $ps -Verb RunAs -ArgumentList $args
    exit
}

function Write-Section {
    param([string]$Title)
    "`r`n===== $Title =====`r`n"
}

function Save-Text {
    param(
        [string]$Name,
        [scriptblock]$Script
    )

    $path = Join-Path $ReportDir $Name
    try {
        & $Script 2>&1 | Out-String -Width 4096 | Set-Content -LiteralPath $path -Encoding UTF8
    } catch {
        "ERROR: $($_.Exception.Message)" | Set-Content -LiteralPath $path -Encoding UTF8
    }
}

function Save-Command {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    Save-Text $Name {
        Write-Section "$FilePath $($Arguments -join ' ')"
        if (Get-Command $FilePath -ErrorAction SilentlyContinue) {
            & $FilePath @Arguments
        } else {
            "$FilePath not found"
        }
    }
}

function Get-RecentEventsText {
    param(
        [string]$LogName,
        [int[]]$Ids,
        [string[]]$Providers,
        [int]$Days = 10,
        [int]$MaxEvents = 300
    )

    $start = (Get-Date).AddDays(-$Days)
    $filter = @{ LogName = $LogName; StartTime = $start }
    if ($Ids) { $filter.Id = $Ids }
    if ($Providers) { $filter.ProviderName = $Providers }

    Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue -MaxEvents $MaxEvents |
        Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message |
        Format-List
}

Relaunch-AdminIfUseful

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportDir = Join-Path $OutputRoot "computer-diagnostics-$stamp"
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

Save-Text "summary.txt" {
    Write-Section "Computer Recovery Toolkit Diagnostic Summary"
    "Generated: $(Get-Date -Format o)"
    "Administrator: $(Test-IsAdministrator)"
    "Computer: $env:COMPUTERNAME"
    "User: $env:USERNAME"
    "OS: $((Get-CimInstance Win32_OperatingSystem).Caption) $((Get-CimInstance Win32_OperatingSystem).Version)"
    "Model: $((Get-CimInstance Win32_ComputerSystem).Manufacturer) $((Get-CimInstance Win32_ComputerSystem).Model)"
    "BIOS: $((Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion)"
    "CPU: $((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)"
    "RAM GB: $([math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2))"
}

Save-Text "system-cim.txt" {
    Write-Section "Computer System"
    Get-CimInstance Win32_ComputerSystem | Format-List *
    Write-Section "Operating System"
    Get-CimInstance Win32_OperatingSystem | Format-List *
    Write-Section "BIOS"
    Get-CimInstance Win32_BIOS | Format-List *
    Write-Section "Processor"
    Get-CimInstance Win32_Processor | Format-List *
}

Save-Text "thermal-and-battery.txt" {
    Write-Section "Battery"
    Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Format-List *
    Write-Section "Battery Static Data"
    Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue | Format-List *
    Write-Section "Battery Full Charged Capacity"
    Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Format-List *
    Write-Section "Battery Status"
    Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue | Format-List *
    Write-Section "Thermal Zones"
    Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue |
        Select-Object InstanceName, CurrentTemperature, CriticalTripPoint |
        Format-Table -AutoSize
}

Save-Text "processes-top-cpu.txt" {
    Get-Process | Sort-Object CPU -Descending |
        Select-Object -First 80 ProcessName, Id, CPU, WorkingSet, StartTime, Path |
        Format-Table -AutoSize
}

Save-Text "processes-top-memory.txt" {
    Get-Process | Sort-Object WorkingSet -Descending |
        Select-Object -First 80 ProcessName, Id, CPU, WorkingSet, StartTime, Path |
        Format-Table -AutoSize
}

Save-Text "processes-command-lines.txt" {
    Get-CimInstance Win32_Process |
        Select-Object Name, ProcessId, ParentProcessId, CommandLine, ExecutablePath |
        Sort-Object Name |
        Format-List
}

Save-Text "services.txt" {
    Get-CimInstance Win32_Service |
        Select-Object Name, DisplayName, State, StartMode, StartName, PathName |
        Sort-Object Name |
        Format-Table -AutoSize
}

Save-Text "startup.txt" {
    Write-Section "Win32_StartupCommand"
    Get-CimInstance Win32_StartupCommand | Sort-Object Name | Format-Table -AutoSize
    Write-Section "Run keys"
    Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue | Format-List
    Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue | Format-List
    Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue | Format-List
}

Save-Text "scheduled-tasks-wake.txt" {
    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.Settings.WakeToRun -eq $true -or $_.State -ne "Disabled" } |
        Select-Object TaskPath, TaskName, State, @{Name="WakeToRun";Expression={$_.Settings.WakeToRun}},
            @{Name="RunOnlyIfNetwork";Expression={$_.Settings.RunOnlyIfNetworkAvailable}},
            @{Name="DisallowStartIfOnBatteries";Expression={$_.Settings.DisallowStartIfOnBatteries}} |
        Sort-Object TaskPath, TaskName |
        Format-Table -AutoSize
}

Save-Text "drivers-display.txt" {
    Write-Section "Video Controllers"
    Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate, AdapterRAM, PNPDeviceID | Format-List
    Write-Section "Signed PnP Drivers - Display/System/Net/Bluetooth"
    Get-CimInstance Win32_PnPSignedDriver |
        Where-Object { $_.DeviceClass -match "DISPLAY|SYSTEM|NET|BLUETOOTH|MEDIA|HIDCLASS|USB" } |
        Select-Object DeviceName, DeviceClass, Manufacturer, DriverVersion, DriverDate, InfName, IsSigned |
        Sort-Object DeviceClass, DeviceName |
        Format-Table -AutoSize
}

Save-Text "devices.txt" {
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Select-Object Class, FriendlyName, Status, InstanceId |
        Sort-Object Class, FriendlyName |
        Format-Table -AutoSize
}

Save-Text "storage.txt" {
    Write-Section "Logical disks"
    Get-CimInstance Win32_LogicalDisk | Format-Table -AutoSize
    Write-Section "Physical disks"
    Get-PhysicalDisk -ErrorAction SilentlyContinue | Format-Table -AutoSize
    Write-Section "Volumes"
    Get-Volume -ErrorAction SilentlyContinue | Format-Table -AutoSize
}

Save-Text "network.txt" {
    Write-Section "Adapters"
    Get-NetAdapter -ErrorAction SilentlyContinue | Format-Table -AutoSize
    Write-Section "Power Management"
    Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue | Format-List
    Write-Section "IP Configuration"
    ipconfig /all
}

Save-Text "power-state.txt" {
    powercfg /a
    Write-Section "Active scheme"
    powercfg /getactivescheme
    Write-Section "Sleep settings"
    powercfg /query SCHEME_CURRENT SUB_SLEEP
    Write-Section "Battery settings"
    powercfg /query SCHEME_CURRENT SUB_BATTERY
}

Save-Command "powercfg-requests.txt" "powercfg.exe" @("/requests")
Save-Command "powercfg-waketimers.txt" "powercfg.exe" @("/waketimers")
Save-Command "powercfg-lastwake.txt" "powercfg.exe" @("/lastwake")
Save-Command "powercfg-wake-armed.txt" "powercfg.exe" @("/devicequery", "wake_armed")
Save-Command "powercfg-all-devices-wake.txt" "powercfg.exe" @("/devicequery", "wake_from_any")

Save-Text "gpu-nvidia.txt" {
    if (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) {
        Write-Section "nvidia-smi"
        nvidia-smi.exe
        Write-Section "NVIDIA compute apps"
        nvidia-smi.exe --query-compute-apps=pid,name,used_gpu_memory --format=csv,noheader
        Write-Section "NVIDIA GPU metrics"
        nvidia-smi.exe --query-gpu=name,driver_version,temperature.gpu,power.draw,utilization.gpu,memory.used --format=csv
    } else {
        "nvidia-smi not found. This is normal on systems without NVIDIA GPUs."
    }
}

Save-Text "gpu-preferences.txt" {
    Get-ItemProperty "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences" -ErrorAction SilentlyContinue | Format-List
}

Save-Text "events-power.txt" {
    Get-RecentEventsText -LogName "System" -Providers @("Microsoft-Windows-Kernel-Power", "Microsoft-Windows-Power-Troubleshooter") -Days 14 -MaxEvents 400
}

Save-Text "events-crashes.txt" {
    Write-Section "BugCheck / Kernel-Power / unexpected shutdown"
    Get-RecentEventsText -LogName "System" -Ids @(41, 1001, 6008) -Days 30 -MaxEvents 200
    Write-Section "Application Error"
    Get-RecentEventsText -LogName "Application" -Providers @("Application Error", "Windows Error Reporting") -Days 14 -MaxEvents 200
}

Save-Text "events-whea.txt" {
    Get-RecentEventsText -LogName "System" -Providers @("Microsoft-Windows-WHEA-Logger") -Days 30 -MaxEvents 200
}

Save-Text "installed-programs.txt" {
    $keys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $programs = foreach ($key in $keys) {
        Get-ItemProperty $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, UninstallString
    }
    $programs | Sort-Object DisplayName | Format-Table -AutoSize
}

Save-Text "windows-features.txt" {
    Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq "Enabled" } |
        Sort-Object FeatureName |
        Format-Table -AutoSize
}

Save-Text "wsl-hyperv.txt" {
    Write-Section "WSL"
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        wsl.exe --status
        wsl.exe --list --verbose
    } else {
        "wsl.exe not found"
    }
    Write-Section "Hyper-V related features"
    Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.FeatureName -match "Hyper|VirtualMachine|Windows-Subsystem-Linux|Containers" } |
        Format-Table -AutoSize
}

$batteryReport = Join-Path $ReportDir "battery-report.html"
& powercfg.exe /batteryreport /output $batteryReport 2>&1 | Out-String | Set-Content -LiteralPath (Join-Path $ReportDir "battery-report-command.txt") -Encoding UTF8

$sleepReport = Join-Path $ReportDir "sleepstudy.html"
& powercfg.exe /sleepstudy /duration 14 /output $sleepReport 2>&1 | Out-String | Set-Content -LiteralPath (Join-Path $ReportDir "sleepstudy-command.txt") -Encoding UTF8

if ($IncludeEnergyTrace) {
    $energyReport = Join-Path $ReportDir "energy-report.html"
    & powercfg.exe /energy /duration $EnergyTraceSeconds /output $energyReport 2>&1 |
        Out-String | Set-Content -LiteralPath (Join-Path $ReportDir "energy-report-command.txt") -Encoding UTF8
}

Save-Text "manifest.txt" {
    Get-ChildItem -LiteralPath $ReportDir -Force |
        Select-Object Name, Length, LastWriteTime |
        Sort-Object Name |
        Format-Table -AutoSize
}

if (-not $NoZip) {
    $zipPath = "$ReportDir.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -LiteralPath $ReportDir -DestinationPath $zipPath -Force
    Write-Host "Created report: $ReportDir"
    Write-Host "Created zip:    $zipPath"
} else {
    Write-Host "Created report: $ReportDir"
}

