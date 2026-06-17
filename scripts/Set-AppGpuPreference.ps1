[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ExePath,

    [Parameter(Mandatory)]
    [ValidateSet("PowerSaving", "HighPerformance", "Default")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

$resolved = (Resolve-Path -LiteralPath $ExePath).Path
$key = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
New-Item -Path $key -Force | Out-Null

switch ($Mode) {
    "PowerSaving" {
        New-ItemProperty -Path $key -Name $resolved -Value "GpuPreference=1;" -PropertyType String -Force | Out-Null
        Write-Host "Power saving / integrated GPU preference applied to: $resolved"
    }
    "HighPerformance" {
        New-ItemProperty -Path $key -Name $resolved -Value "GpuPreference=2;" -PropertyType String -Force | Out-Null
        Write-Host "High performance / dedicated GPU preference applied to: $resolved"
    }
    "Default" {
        Remove-ItemProperty -Path $key -Name $resolved -ErrorAction SilentlyContinue
        Write-Host "GPU preference removed; Windows will decide automatically: $resolved"
    }
}

Write-Host "Close and reopen the app for the change to take effect."

