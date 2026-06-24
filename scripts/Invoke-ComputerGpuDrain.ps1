[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$NoRestart,
    [switch]$RestartExplorer,
    [switch]$ShowNvidiaProcesses
)

$ErrorActionPreference = "Continue"
$LogRoot = Join-Path $env:LOCALAPPDATA "ComputerRecoveryToolkit"
$LogPath = Join-Path $LogRoot "gpu-drain-latest.log"

function Write-DrainLog {
    param([string]$Message)
    if (-not (Test-Path -LiteralPath $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    Write-Host $line
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

function Test-ExternalMonitorActive {
    try {
        $internalTechnology = 2147483648
        $active = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction Stop |
            Where-Object { $_.Active -eq $true }
        foreach ($monitor in $active) {
            Write-DrainLog ("Monitor active: tech={0} instance={1}" -f $monitor.VideoOutputTechnology, $monitor.InstanceName)
        }
        return @(($active | Where-Object { [uint32]$_.VideoOutputTechnology -ne [uint32]$internalTechnology })).Count -gt 0
    } catch {
        Write-DrainLog "Could not query monitor connections: $($_.Exception.Message)"
        return $false
    }
}

function Resolve-AppPathCandidates {
    $candidates = @(
        "$env:SystemRoot\explorer.exe",
        "$env:SystemRoot\System32\ApplicationFrameHost.exe",
        "$env:SystemRoot\System32\RuntimeBroker.exe",
        "$env:SystemRoot\System32\SearchHost.exe",
        "$env:SystemRoot\SystemApps\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\StartMenuExperienceHost.exe",
        "$env:SystemRoot\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\TextInputHost.exe",
        "$env:ProgramFiles\WindowsApps\MicrosoftWindows.Client.WebExperience*\Dashboard\Widgets.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
        "$env:ProgramFiles\Microsoft VS Code\Code.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -like "*`**") {
            Get-ChildItem -Path (Split-Path -Parent $candidate) -Filter (Split-Path -Leaf $candidate) -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer } |
                ForEach-Object { $_.FullName }
        } elseif (Test-Path -LiteralPath $candidate -PathType Leaf) {
            (Resolve-Path -LiteralPath $candidate).Path
        }
    }
}

function Apply-CurrentUserGpuPreferences {
    $key = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
    Resolve-AppPathCandidates | Sort-Object -Unique | ForEach-Object {
        try {
            New-ItemProperty -LiteralPath $key -Name $_ -Value "GpuPreference=1;" -PropertyType String -Force | Out-Null
            Write-DrainLog "Preferred iGPU: $_"
        } catch {
            Write-DrainLog "Could not set iGPU preference for $_ - $($_.Exception.Message)"
        }
    }
}

function Restart-SafeShellProcesses {
    $safeNames = @(
        "ApplicationFrameHost",
        "SearchHost",
        "StartMenuExperienceHost",
        "TextInputHost",
        "Widgets",
        "WidgetService"
    )

    foreach ($name in $safeNames) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Write-DrainLog "Restarting safe shell process: $($_.ProcessName) pid=$($_.Id)"
                Stop-Process -Id $_.Id -Force -ErrorAction Stop
            } catch {
                Write-DrainLog "Could not restart $($_.ProcessName): $($_.Exception.Message)"
            }
        }
    }

    if ($RestartExplorer) {
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Process explorer.exe
    }
}

function Write-NvidiaSnapshot {
    $smiPath = Find-NvidiaSmi
    if ($smiPath) {
        & $smiPath 2>&1 | ForEach-Object { Write-DrainLog "  $_" }
    } else {
        Write-DrainLog "nvidia-smi not found in known NVIDIA locations."
    }
}

Write-DrainLog "Starting dGPU drain. Force=$Force NoRestart=$NoRestart RestartExplorer=$RestartExplorer"

if ((Test-ExternalMonitorActive) -and -not $Force) {
    Write-DrainLog "External monitor appears active; leaving processes alone."
    if ($ShowNvidiaProcesses) { Write-NvidiaSnapshot }
    exit 0
}

Apply-CurrentUserGpuPreferences
if (-not $NoRestart) { Restart-SafeShellProcesses }
if ($ShowNvidiaProcesses) { Write-NvidiaSnapshot }
Write-DrainLog "Done. Close/reopen user apps that still appear in NVIDIA GPU Activity."

