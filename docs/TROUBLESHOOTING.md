# Troubleshooting Playbook

## The computer wakes, drains battery, or gets hot in a bag

Run:

```powershell
.\scripts\Collect-ComputerDiagnostics.ps1 -IncludeEnergyTrace
```

Check:

- `power-state.txt`
- `powercfg-requests.txt`
- `powercfg-waketimers.txt`
- `powercfg-wake-armed.txt`
- `events-power.txt`
- `sleepstudy.html`

Then consider:

```powershell
.\scripts\Apply-ComputerPowerPolicy.ps1 -Apply
```

## The dedicated GPU stays awake

Run:

```powershell
.\scripts\Get-DgpuProcesses.ps1
```

If it shows shell/WebView processes after unplugging an external monitor, try:

```powershell
.\scripts\Invoke-ComputerGpuDrain.ps1 -ShowNvidiaProcesses
```

For apps that should not use the dGPU:

```powershell
.\scripts\Set-AppGpuPreference.ps1 -ExePath "C:\Path\To\App.exe" -Mode PowerSaving
```

For games or 3D apps:

```powershell
.\scripts\Set-AppGpuPreference.ps1 -ExePath "C:\Path\To\Game.exe" -Mode HighPerformance
```

## Games run badly

Collect diagnostics and inspect:

- `processes-top-cpu.txt`
- `processes-top-memory.txt`
- `gpu-nvidia.txt`
- `drivers-display.txt`
- `thermal-and-battery.txt`
- `events-crashes.txt`
- `events-whea.txt`

Also check OEM performance mode, AC adapter wattage, temperatures, RAM usage,
VRAM pressure, and whether the game is accidentally using the iGPU.

For repeatable game or workload comparisons, pair this diagnostic kit with
[Telemetry Lab](https://github.com/wvxbs/telemetry-lab). It is better suited for
capturing benchmark-style telemetry over time instead of one-off system reports.

If Logitech G HUB lighting/profile management is part of the setup, see
[G HUB RGB Freestyle Injector](https://github.com/wvxbs/ghub-rgb-freestyle-injector).

