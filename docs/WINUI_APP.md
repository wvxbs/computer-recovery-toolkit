# WinUI 3 app

The WinUI 3 app is an optional native shell for Computer Recovery Toolkit. The
PowerShell scripts remain the source of truth; the app runs those scripts and
shows their output in a friendlier Windows interface.

## Features

- Portuguese and English UI selector.
- Collect standard diagnostics.
- Collect a 60-second energy trace.
- Preview or apply the conservative power policy.
- Inspect NVIDIA dGPU processes.
- List internal/external displays.
- Install the internal display refresh automation.
- Start temporary download mode with timer, idle exit, and CPU cap controls.

## Build locally

```powershell
dotnet publish .\winui\ComputerRecoveryToolkit.WinUI\ComputerRecoveryToolkit.WinUI.csproj `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -p:Platform=x64 `
  -p:WindowsPackageType=None `
  -o .\artifacts\ComputerRecoveryToolkit-WinUI3-windows-x64
```

Run:

```powershell
.\artifacts\ComputerRecoveryToolkit-WinUI3-windows-x64\ComputerRecoveryToolkit.WinUI.exe
```

## GitHub artifact

The workflow `Build WinUI 3 artifact` publishes:

```text
ComputerRecoveryToolkit-WinUI3-windows-x64
```

Download the artifact from the GitHub Actions run, extract it, and run
`ComputerRecoveryToolkit.WinUI.exe`.

## Signing

The workflow can sign the WinUI executable when these repository secrets exist:

```text
CODESIGN_PFX_BASE64
CODESIGN_PFX_PASSWORD
```

Without those secrets, the artifact is intentionally published unsigned. The
project does not fake trust or bypass Windows reputation systems; proper
distribution should use a real code-signing certificate.

## License and contact

License: MIT.

Author: Gabriel Ferreira

- Email: gabriel.ferreira7854@gmail.com
- LinkedIn: https://www.linkedin.com/in/gabriel-ferreira-021a44140/
- GitHub: https://github.com/wvxbs
