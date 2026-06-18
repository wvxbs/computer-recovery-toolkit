<#
.SYNOPSIS
    Alterna a taxa de atualizacao da tela interna conforme tomada/bateria.

.DESCRIPTION
    Nao usa QRes, nao faz polling e nao depende de monitor principal.
    O script identifica a tela interna por WMI (VideoOutputTechnology = Internal)
    e cruza esse identificador com a API Win32 EnumDisplayDevices.

    Use -Mode InstallTask para criar a tarefa agendada acionada por eventos de
    troca de energia. A tarefa roda escondida e chama o script em -Mode Auto.
#>

[CmdletBinding()]
param(
    [ValidateSet("Auto", "AC", "DC", "List", "InstallTask", "UninstallTask")]
    [string]$Mode = "Auto",

    [ValidateRange(24, 360)]
    [int]$BatteryHz = 60,

    [ValidateRange(24, 360)]
    [int]$AcHz = 120,

    [string]$TaskName = "Computer_InternalDisplayRefresh_ACDC",

    [switch]$KeepLegacyQResTask,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$LogRoot = Join-Path $env:LOCALAPPDATA "ComputerRecoveryToolkit"
$LogPath = Join-Path $LogRoot "internal-display-refresh-latest.log"

function Write-RefreshLog {
    param([string]$Message)

    if (-not (Test-Path -LiteralPath $LogRoot)) {
        New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    }

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    if (-not $Quiet) { Write-Host $line }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-Argument {
    param([object]$Value)
    '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Invoke-SelfElevated {
    if (Test-IsAdministrator) { return }

    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-Argument $PSCommandPath),
        "-Mode", $Mode,
        "-BatteryHz", $BatteryHz,
        "-AcHz", $AcHz,
        "-TaskName", (Quote-Argument $TaskName)
    )
    if ($KeepLegacyQResTask) { $args += "-KeepLegacyQResTask" }
    if ($Quiet) { $args += "-Quiet" }

    Start-Process -FilePath $ps -ArgumentList $args -Verb RunAs
    exit
}

function Add-DisplayRefreshNativeType {
    $nativeType = [System.Management.Automation.PSTypeName]'DisplayRefreshNative'
    if ($nativeType.Type) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class DisplayRefreshNative
{
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int ENUM_REGISTRY_SETTINGS = -2;
    public const int DM_DISPLAYFREQUENCY = 0x00400000;
    public const int DISP_CHANGE_SUCCESSFUL = 0;
    public const int CDS_UPDATEREGISTRY = 0x00000001;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    public sealed class DisplayInfo
    {
        public string AdapterName;
        public string AdapterString;
        public int AdapterStateFlags;
        public string MonitorString;
        public string MonitorDeviceId;
        public string MonitorPnpId;
    }

    public sealed class DisplayMode
    {
        public int Width;
        public int Height;
        public int Frequency;
        public int BitsPerPel;
    }

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);

    private static string ExtractPnpId(string deviceId)
    {
        if (String.IsNullOrWhiteSpace(deviceId)) return "";
        string[] parts = deviceId.Split('\\');
        if (parts.Length >= 2) return parts[1].ToUpperInvariant();
        return deviceId.ToUpperInvariant();
    }

    public static List<DisplayInfo> GetDisplays()
    {
        var result = new List<DisplayInfo>();
        for (uint i = 0; i < 32; i++)
        {
            var adapter = new DISPLAY_DEVICE();
            adapter.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            if (!EnumDisplayDevices(null, i, ref adapter, 0)) continue;

            for (uint j = 0; j < 16; j++)
            {
                var monitor = new DISPLAY_DEVICE();
                monitor.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
                if (!EnumDisplayDevices(adapter.DeviceName, j, ref monitor, 0)) continue;

                result.Add(new DisplayInfo {
                    AdapterName = adapter.DeviceName,
                    AdapterString = adapter.DeviceString,
                    AdapterStateFlags = adapter.StateFlags,
                    MonitorString = monitor.DeviceString,
                    MonitorDeviceId = monitor.DeviceID,
                    MonitorPnpId = ExtractPnpId(monitor.DeviceID)
                });
            }
        }
        return result;
    }

    public static DisplayMode GetCurrentMode(string adapterName)
    {
        var mode = new DEVMODE();
        mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettings(adapterName, ENUM_CURRENT_SETTINGS, ref mode)) return null;

        return new DisplayMode {
            Width = mode.dmPelsWidth,
            Height = mode.dmPelsHeight,
            Frequency = mode.dmDisplayFrequency,
            BitsPerPel = mode.dmBitsPerPel
        };
    }

    public static int[] GetSupportedFrequencies(string adapterName, int width, int height)
    {
        var set = new SortedSet<int>();
        for (int i = 0; i < 1000; i++)
        {
            var mode = new DEVMODE();
            mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            if (!EnumDisplaySettings(adapterName, i, ref mode)) break;
            if (mode.dmPelsWidth == width && mode.dmPelsHeight == height && mode.dmDisplayFrequency > 0)
            {
                set.Add(mode.dmDisplayFrequency);
            }
        }
        var arr = new int[set.Count];
        set.CopyTo(arr);
        return arr;
    }

    public static int SetRefreshRate(string adapterName, int hz)
    {
        var mode = new DEVMODE();
        mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettings(adapterName, ENUM_CURRENT_SETTINGS, ref mode)) return -1001;

        mode.dmDisplayFrequency = hz;
        mode.dmFields = DM_DISPLAYFREQUENCY;

        return ChangeDisplaySettingsEx(adapterName, ref mode, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
    }
}
'@
}

function Get-PowerOnline {
    try {
        $batteryStatus = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop |
            Select-Object -First 1
        if ($null -ne $batteryStatus.PowerOnline) {
            return [bool]$batteryStatus.PowerOnline
        }
    } catch {
        Write-RefreshLog "Aviso: BatteryStatus falhou: $($_.Exception.Message)"
    }

    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $battery) { return $true }

    return ($battery.BatteryStatus -in 2, 6, 7, 8, 9)
}

function Get-InternalMonitorPnpIds {
    $internalTechnology = [uint32]2147483648

    @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction Stop |
        Where-Object { $_.Active -eq $true -and [uint32]$_.VideoOutputTechnology -eq $internalTechnology } |
        ForEach-Object {
            $parts = $_.InstanceName -split "\\"
            if ($parts.Count -ge 2) { $parts[1].ToUpperInvariant() }
        } | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-InternalDisplay {
    Add-DisplayRefreshNativeType

    $internalIds = @(Get-InternalMonitorPnpIds)
    $displays = @([DisplayRefreshNative]::GetDisplays())

    foreach ($display in $displays) {
        $mode = [DisplayRefreshNative]::GetCurrentMode($display.AdapterName)
        [pscustomobject]@{
            AdapterName = $display.AdapterName
            AdapterString = $display.AdapterString
            MonitorString = $display.MonitorString
            MonitorPnpId = $display.MonitorPnpId
            IsInternal = ($internalIds -contains $display.MonitorPnpId)
            CurrentMode = $mode
        }
    }
}

function Select-NearestFrequency {
    param(
        [int]$RequestedHz,
        [int[]]$SupportedHz
    )

    if (-not $SupportedHz -or $SupportedHz.Count -eq 0) { return $RequestedHz }
    if ($SupportedHz -contains $RequestedHz) { return $RequestedHz }

    return @($SupportedHz | Sort-Object { [math]::Abs($_ - $RequestedHz) }, { $_ } | Select-Object -First 1)[0]
}

function Set-InternalRefreshForPowerState {
    Add-DisplayRefreshNativeType

    $targetHz = switch ($Mode) {
        "AC" { $AcHz }
        "DC" { $BatteryHz }
        default {
            if (Get-PowerOnline) { $AcHz } else { $BatteryHz }
        }
    }

    $internal = @(Get-InternalDisplay | Where-Object { $_.IsInternal } | Select-Object -First 1)
    if (-not $internal) {
        Write-RefreshLog "Tela interna ativa nao encontrada; nada alterado. Isso e esperado se ela estiver desligada."
        return
    }

    $modeNow = $internal.CurrentMode
    if (-not $modeNow) {
        Write-RefreshLog "Nao consegui ler modo atual de $($internal.AdapterName)."
        return
    }

    $supported = @([DisplayRefreshNative]::GetSupportedFrequencies($internal.AdapterName, $modeNow.Width, $modeNow.Height))
    $actualHz = Select-NearestFrequency -RequestedHz $targetHz -SupportedHz $supported

    Write-RefreshLog ("Tela interna: adapter={0}; monitor={1}; pnp={2}; modo={3}x{4}@{5}; alvo={6}; suportados={7}" -f `
        $internal.AdapterName, $internal.MonitorString, $internal.MonitorPnpId, $modeNow.Width, $modeNow.Height, $modeNow.Frequency, $actualHz, ($supported -join ","))

    if ($modeNow.Frequency -eq $actualHz) {
        Write-RefreshLog "Tela interna ja esta em ${actualHz}Hz."
        return
    }

    $code = [DisplayRefreshNative]::SetRefreshRate($internal.AdapterName, $actualHz)
    if ($code -eq [DisplayRefreshNative]::DISP_CHANGE_SUCCESSFUL) {
        Write-RefreshLog "Taxa da tela interna alterada para ${actualHz}Hz."
    } else {
        Write-RefreshLog "Falha ao alterar taxa da tela interna para ${actualHz}Hz. Codigo ChangeDisplaySettingsEx=$code"
    }
}

function Install-RefreshTask {
    Invoke-SelfElevated

    if (-not $KeepLegacyQResTask) {
        foreach ($legacyTask in @("dynamic-refresh")) {
            $task = Get-ScheduledTask -TaskName $legacyTask -ErrorAction SilentlyContinue
            if ($task) {
                Unregister-ScheduledTask -TaskName $legacyTask -Confirm:$false -ErrorAction SilentlyContinue
                Write-RefreshLog "Tarefa legada removida/desativada: $legacyTask"
            }
        }
    }

    $scriptPath = $PSCommandPath
    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        $launcherPath = Join-Path (Split-Path -Parent $PSCommandPath) "Run-InternalDisplayRefreshHidden.vbs"
    $launcher = @"
Option Explicit
Dim shell, fso, scriptDir, psScript, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = fso.BuildPath(scriptDir, "Set-InternalDisplayRefresh.ps1")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """ -Mode Auto -BatteryHz $BatteryHz -AcHz $AcHz -Quiet"
shell.Run cmd, 0, False
"@
    Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding ASCII
    $scriptPath = $launcherPath
    $ps = Join-Path $env:SystemRoot "System32\wscript.exe"
    $args = "//B //Nologo `"$scriptPath`""
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Alterna a taxa de atualizacao somente da tela interna conforme tomada/bateria, sem QRes e sem polling.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$sid</UserId>
    </LogonTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and (EventID=104 or EventID=105)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT1M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$ps</Command>
      <Arguments>$args</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    Register-ScheduledTask -TaskName $TaskName -Xml $xml -Force | Out-Null
    Write-RefreshLog "Tarefa instalada: $TaskName"
    Set-InternalRefreshForPowerState
}

function Uninstall-RefreshTask {
    Invoke-SelfElevated
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-RefreshLog "Tarefa removida: $TaskName"
}

switch ($Mode) {
    "InstallTask" {
        Install-RefreshTask
    }
    "UninstallTask" {
        Uninstall-RefreshTask
    }
    "List" {
        Get-InternalDisplay | Format-Table -AutoSize
    }
    default {
        Set-InternalRefreshForPowerState
    }
}





