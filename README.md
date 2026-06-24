# Computer Recovery Toolkit

Windows computer diagnostics and recovery scripts for machines with bad standby,
high battery drain, noisy fans, hybrid GPU weirdness, wake timers, driver issues,
or "something is wrong but I do not know where to look" behavior.

This project was extracted from a real recovery kit used to stabilize a Windows
PC with Modern Standby and hybrid graphics problems. The public version is
generic, privacy-conscious, and opt-in: diagnostics are easy to run, but fixes
are split into explicit scripts.

## What this kit does

- Collects a complete plain-text diagnostic bundle for human or LLM analysis.
- Generates `powercfg` battery, sleep, wake, and energy reports.
- Lists CPU, memory, disk, network, startup, services, drivers, scheduled tasks,
  recent crashes, WHEA, power events, and Modern Standby signals.
- Detects NVIDIA dGPU processes with `nvidia-smi` when available.
- Lets you set per-app Windows GPU preference to iGPU, dGPU, or default.
- Offers a conservative Modern Standby policy for battery drain control.
- Offers a manual dGPU drain helper for shell/WebView processes that keep the
  dedicated GPU awake after dock/monitor changes.
- Offers a temporary AC-only download mode for launchers that do not reliably
  keep downloading during Modern Standby.
- Offers an optional WinUI 3 app for people who prefer a native Windows UI over
  direct PowerShell usage, with portable use plus per-user install, repair, and
  uninstall actions.
- Installs optional PowerShell aliases for faster troubleshooting.

## What this kit does not do

- It does not remove drivers.
- It does not uninstall OEM software.
- It does not change BIOS settings.
- It does not disable hibernation.
- It does not force Docker, CUDA, games, or compute workloads away from the dGPU.
- It does not include personal battery reports, machine names, usernames, or
  hardware benchmark history from the original machine.

## Quick start

Open PowerShell in this folder and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Collect-ComputerDiagnostics.ps1
```

For a deeper 60-second energy trace, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Collect-ComputerDiagnostics.ps1 -IncludeEnergyTrace -EnergyTraceSeconds 60
```

The script creates a timestamped folder under `.\reports\` and a `.zip` beside
it. Send the zip to whoever will analyze the machine.

## Suggested workflow

1. Run diagnostics first.
2. Read `summary.txt` and `power-state.txt`.
3. Check `events-power.txt`, `events-crashes.txt`, and `gpu-nvidia.txt`.
4. Only then run a fix script, and prefer dry runs before `-Apply`.

## Related tools

If this kit helps you find the problem and you want to go deeper, these sibling
projects may be useful:

- [Telemetry Lab](https://github.com/wvxbs/telemetry-lab): capture and compare
  performance telemetry for games, workloads, power modes, and thermal behavior.
- [G HUB RGB Freestyle Injector](https://github.com/wvxbs/ghub-rgb-freestyle-injector):
  sync Markdown/JSON palettes into Logitech G HUB Freestyle presets without
  rebuilding per-key lighting manually.

## Fix scripts

### Modern Standby / battery drain policy

Preview only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Apply-ComputerPowerPolicy.ps1
```

Apply:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Apply-ComputerPowerPolicy.ps1 -Apply
```

Defaults:

- AC: Modern Standby network connectivity enabled.
- Battery: Modern Standby network connectivity disabled.
- AC: wake timers allowed.
- Battery: wake timers disabled.
- AC: never hibernate from idle.
- Battery: hibernate after 120 minutes.
- AC: Windows Energy Saver off.
- Battery: Windows Energy Saver always on/aggressive.
- AC: Intel Graphics Power Plan maximum performance, if the setting exists.
- Battery: Intel Graphics Power Plan maximum battery life, if the setting exists.
- Critical battery: hibernate.

Customize battery hibernation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Apply-ComputerPowerPolicy.ps1 -Apply -BatteryHibernateAfterMinutes 90
```

Skip optional Energy Saver or Intel Graphics policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Apply-ComputerPowerPolicy.ps1 -Apply -SkipEnergySaverPolicy -SkipIntelGraphicsPolicy
```

### Temporary download mode

Steam, Epic, Riot, Xbox, and other launchers may not keep downloading reliably
inside true Modern Standby. This temporary mode keeps the computer awake only
while its PowerShell window is open, only on AC power, with the display turning
off quickly and the CPU capped to reduce heat with the lid closed. It can also
stop automatically after a timer or after configured launchers become idle.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-TemporaryDownloadMode.ps1
```

With a 4-hour maximum and 20-minute idle exit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-TemporaryDownloadMode.ps1 -MaxMinutes 240 -IdleExitMinutes 20
```

Behavior:

- refuses to start on battery;
- prevents sleep only on AC;
- makes lid close do nothing only on AC;
- turns the display off quickly;
- caps processor maximum on AC, default `70%`;
- watches Steam, Epic, Riot, Xbox/Microsoft Store/Gaming Services, disk, and
  network activity;
- keeps running while relevant launcher I/O, disk verification, or network
  movement is active;
- restores previous settings on `Q`, Enter, Esc, Ctrl+C, AC removal, or window close;
- uses a hidden watchdog to restore settings if the main window is killed.

### Optional WinUI 3 app

The native app is optional; the scripts remain the core implementation.

Download the portable zip from
[GitHub Releases](https://github.com/wvxbs/computer-recovery-toolkit/releases),
extract it, and run `ComputerRecoveryToolkit.WinUI.exe`. The app can stay
portable or install itself into the current Windows user profile without admin
rights. The install tab adds a Start Menu launcher and a normal uninstall entry.

Release builds are meant to be signed. If a zip came from a CI artifact instead
of the Releases page, Windows Defender/SmartScreen may warn because that package
is only a test artifact.

Build a local portable zip:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Package-WinUIRelease.ps1
```

Run:

```powershell
Expand-Archive .\artifacts\ComputerRecoveryToolkit-WinUI3-portable-win-x64.zip .\artifacts\app
.\artifacts\app\ComputerRecoveryToolkit.WinUI.exe
```

The GitHub Actions workflow `Release WinUI portable app` attaches
`ComputerRecoveryToolkit-WinUI3-portable-win-x64.zip` and `SHA256SUMS.txt` to a
GitHub Release. Signing is supported when `CODESIGN_PFX_BASE64` and
`CODESIGN_PFX_PASSWORD` repository secrets are set. Release packaging requires
signing by default; an unsigned release must be explicitly requested and may be
blocked by Windows reputation systems. See [docs/WINUI_APP.md](docs/WINUI_APP.md).

### Hybrid GPU process check

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-DgpuProcesses.ps1
```

If the script prints a restart command, copy it and decide manually. Unknown
apps are not killed automatically.

### Set GPU preference for one app

Prefer integrated graphics:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-AppGpuPreference.ps1 -ExePath "C:\Path\To\App.exe" -Mode PowerSaving
```

Force dedicated/high-performance GPU:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-AppGpuPreference.ps1 -ExePath "C:\Path\To\Game.exe" -Mode HighPerformance
```

Return to Windows default:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-AppGpuPreference.ps1 -ExePath "C:\Path\To\App.exe" -Mode Default
```


### Internal display refresh automation

For laptops whose internal panel supports multiple refresh rates, this installs a hidden Scheduled Task that switches only the internal display when AC power changes. It does not use QRes, does not poll in a loop, does not install a resident service, and does not target the primary monitor.

List detected displays first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-InternalDisplayRefresh.ps1 -Mode List
```

Install the AC/DC automation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-InternalDisplayRefresh.ps1 -Mode InstallTask -BatteryHz 60 -AcHz 120
```

Apply once using the current power source:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-InternalDisplayRefresh.ps1 -Mode Auto
```

Remove the task:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-InternalDisplayRefresh.ps1 -Mode UninstallTask
```

Notes:

- Runtime is hidden with `-WindowStyle Hidden`.
- Installation may request UAC because task registration needs elevation.
- The task runs on logon and `Kernel-Power` AC/DC events 104/105.
- The script identifies the internal panel through Windows display WMI plus PnP ID matching; if the internal panel is disabled or unavailable, it exits without touching external monitors.
- By default it removes a legacy task named `dynamic-refresh` to avoid old QRes automation conflicts. Use `-KeepLegacyQResTask` if you intentionally want to keep that task.
- Log: `%LOCALAPPDATA%\ComputerRecoveryToolkit\internal-display-refresh-latest.log`.

### Optional aliases

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-ComputerAliases.ps1
```

Run the installer from the Windows account that should receive the aliases. For
multi-user machines, use Windows "Run as different user" or sign into the other
account and run the same command there. The script writes only that user's
PowerShell profiles.

By default it installs every alias group. You can install only part of the
toolkit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-ComputerAliases.ps1 -GpuOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-ComputerAliases.ps1 -Diagnostics -Gpu
```

Aliases installed:

- `computer-diag`
- `computer-energy`
- `computer-power-fix`
- `computer-gpu`
- `computer-gpu-drain`
- `computer-gpu-pref`
- `computer-refresh`
- `computer-download`
- `computer-kit`

Selection flags:

- `-All`: install everything, same as the default.
- `-Diagnostics`: diagnostics and energy trace aliases.
- `-Power`: power policy alias.
- `-Gpu` or `-GpuOnly`: GPU analysis/drain/preference aliases.
- `-Display`: internal display refresh alias.
- `-Download`: temporary download mode alias.
- `-Navigation`: folder navigation alias.

## Privacy

Diagnostic reports can contain machine names, installed software, event logs,
device serials, usernames, paths, Wi-Fi adapter names, and process command
lines. Review the generated zip before publishing it.

See [docs/PRIVACY.md](docs/PRIVACY.md).

## Safety model

The diagnostic script is read-mostly, but some Windows reports require admin.
Fix scripts self-elevate only when `-Apply` is used or when process management
requires it. Most changes can be reversed with Windows power settings, GPU
settings, or by rerunning the script with different parameters.

## License

MIT. Use it, adapt it, and send it to the friend whose computer sounds like a
jet engine while "sleeping".

Copyright (C) 2026 Gabriel Ferreira.

## Author And Contact

- Author: Gabriel Ferreira
- Email: gabriel.ferreira7854@gmail.com
- LinkedIn: https://www.linkedin.com/in/gabriel-ferreira-021a44140/
- GitHub: https://github.com/wvxbs


