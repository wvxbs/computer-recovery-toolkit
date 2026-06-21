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
- Install, repair, or uninstall the app for the current Windows user without
  requiring administrator rights.

## Download from Releases

For normal use, download the portable zip from:

```text
https://github.com/wvxbs/computer-recovery-toolkit/releases
```

Extract `ComputerRecoveryToolkit-WinUI3-portable-win-x64.zip` and run
`ComputerRecoveryToolkit.WinUI.exe`. The app can run directly from that extracted
folder, or you can open the Install tab and choose:

- Install: copies the portable folder to
  `%LOCALAPPDATA%\Programs\ComputerRecoveryToolkit`, adds a Start Menu launcher,
  and registers an uninstall entry under the current user.
- Repair: refreshes the launcher and uninstall metadata.
- Uninstall: removes the per-user install. Portable copies are left alone.

## Build locally

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Package-WinUIRelease.ps1
```

Run:

```powershell
Expand-Archive .\artifacts\ComputerRecoveryToolkit-WinUI3-portable-win-x64.zip .\artifacts\app
.\artifacts\app\ComputerRecoveryToolkit.WinUI.exe
```

## GitHub Actions

The workflow `Build WinUI 3 artifact` publishes a CI test zip. It is useful for
checking changes, but it may be unsigned and should not be treated as the public
download.

The workflow `Release WinUI portable app` publishes these files to the Releases
page:

```text
ComputerRecoveryToolkit-WinUI3-portable-win-x64.zip
SHA256SUMS.txt
```

Release workflow triggers:

- Push a tag like `v0.1.0`; or
- Run the workflow manually and provide a tag.

## Signing

The release workflow signs the WinUI executable when these repository secrets
exist:

```text
CODESIGN_PFX_BASE64
CODESIGN_PFX_PASSWORD
```

Release packaging requires signing by default. You can intentionally allow an
unsigned release through the manual workflow input, but Windows Defender or
SmartScreen may block it because unsigned, new, self-contained desktop apps have
little reputation.

This project does not disable Defender, add exclusions, or fake trust. The
proper fix for public distribution is a real code-signing certificate with a
timestamp, plus stable versioned Releases and checksums.

## License and contact

License: MIT.

Author: Gabriel Ferreira

- Email: gabriel.ferreira7854@gmail.com
- LinkedIn: https://www.linkedin.com/in/gabriel-ferreira-021a44140/
- GitHub: https://github.com/wvxbs
