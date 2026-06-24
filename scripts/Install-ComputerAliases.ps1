[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Diagnostics,
    [switch]$Power,
    [switch]$Gpu,
    [switch]$Display,
    [switch]$Download,
    [switch]$Navigation,
    [switch]$GpuOnly
)

$ErrorActionPreference = "Stop"

$kitRoot = Split-Path -Parent $PSScriptRoot
$toolsPath = Join-Path $PSScriptRoot "Computer-PowerShell-Tools.ps1"

if ($GpuOnly) {
    $Gpu = $true
}

$explicitSelection = $All -or $Diagnostics -or $Power -or $Gpu -or $Display -or $Download -or $Navigation -or $GpuOnly
if (-not $explicitSelection -or $All) {
    $Diagnostics = $true
    $Power = $true
    $Gpu = $true
    $Display = $true
    $Download = $true
    $Navigation = $true
}

$functions = New-Object System.Collections.Generic.List[string]
$aliases = New-Object System.Collections.Generic.List[string]

if ($Diagnostics) {
    $functions.Add(@'
function Invoke-ComputerDiagnostics {
    & (Join-Path $script:ComputerScripts "Collect-ComputerDiagnostics.ps1") @args
}

function Invoke-ComputerEnergyDiagnostics {
    & (Join-Path $script:ComputerScripts "Collect-ComputerDiagnostics.ps1") -IncludeEnergyTrace @args
}
'@)
    $aliases.Add("Set-Alias computer-diag Invoke-ComputerDiagnostics")
    $aliases.Add("Set-Alias computer-energy Invoke-ComputerEnergyDiagnostics")
}

if ($Power) {
    $functions.Add(@'
function Invoke-ComputerPowerFix {
    & (Join-Path $script:ComputerScripts "Apply-ComputerPowerPolicy.ps1") @args
}
'@)
    $aliases.Add("Set-Alias computer-power-fix Invoke-ComputerPowerFix")
}

if ($Gpu) {
    $functions.Add(@'
function Invoke-ComputerGpuAnalyze {
    & (Join-Path $script:ComputerScripts "Get-DgpuProcesses.ps1") @args
}

function Invoke-ComputerGpuDrain {
    & (Join-Path $script:ComputerScripts "Invoke-ComputerGpuDrain.ps1") -ShowNvidiaProcesses @args
}

function Invoke-ComputerGpuPreference {
    & (Join-Path $script:ComputerScripts "Set-AppGpuPreference.ps1") @args
}
'@)
    $aliases.Add("Set-Alias computer-gpu Invoke-ComputerGpuAnalyze")
    $aliases.Add("Set-Alias computer-gpu-drain Invoke-ComputerGpuDrain")
    $aliases.Add("Set-Alias computer-gpu-pref Invoke-ComputerGpuPreference")
}

if ($Display) {
    $functions.Add(@'
function Invoke-ComputerDisplayRefresh {
    & (Join-Path $script:ComputerScripts "Set-InternalDisplayRefresh.ps1") @args
}
'@)
    $aliases.Add("Set-Alias computer-refresh Invoke-ComputerDisplayRefresh")
}

if ($Download) {
    $functions.Add(@'
function Start-ComputerDownloadMode {
    & (Join-Path $script:ComputerScripts "Start-TemporaryDownloadMode.ps1") @args
}
'@)
    $aliases.Add("Set-Alias computer-download Start-ComputerDownloadMode")
}

if ($Navigation) {
    $functions.Add(@'
function Set-ComputerKitLocation {
    Set-Location -LiteralPath $script:ComputerKitRoot
}
'@)
    $aliases.Add("Set-Alias computer-kit Set-ComputerKitLocation")
}

$content = @"
# Computer Recovery Toolkit helper commands.
# Generated for the Windows user that ran Install-ComputerAliases.ps1.
`$script:ComputerKitRoot = "$kitRoot"
`$script:ComputerScripts = Join-Path `$script:ComputerKitRoot "scripts"

$($functions -join "`r`n")

$($aliases -join "`r`n")
"@

Set-Content -LiteralPath $toolsPath -Value $content -Encoding UTF8

$profiles = @(
    $PROFILE.CurrentUserCurrentHost,
    $PROFILE.CurrentUserAllHosts,
    (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"),
    (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PowerShell\Microsoft.PowerShell_profile.ps1")
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

$begin = "# BEGIN Computer Recovery Toolkit aliases"
$end = "# END Computer Recovery Toolkit aliases"
$loader = @"
$begin
`$computerTools = "$toolsPath"
if (Test-Path -LiteralPath `$computerTools) { . `$computerTools }
$end
"@

foreach ($profilePath in $profiles) {
    $dir = Split-Path -Parent $profilePath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $existing = if (Test-Path -LiteralPath $profilePath) {
        Get-Content -LiteralPath $profilePath -Raw
    } else {
        ""
    }

    $pattern = "(?s)" + [regex]::Escape($begin) + ".*?" + [regex]::Escape($end) + "\r?\n?"
    $existing = [regex]::Replace($existing, $pattern, "")
    $updated = ($existing.TrimEnd() + "`r`n`r`n" + $loader + "`r`n").TrimStart()

    Set-Content -LiteralPath $profilePath -Value $updated -Encoding UTF8
    Write-Host "Updated profile for $env:USERNAME: $profilePath"
}

$installedAliases = @($aliases | ForEach-Object { ($_ -split '\s+')[-2] })
Write-Host ("Aliases installed for {0}: {1}" -f $env:USERNAME, (($installedAliases | Sort-Object) -join ", "))
Write-Host "Open a new PowerShell/Windows Terminal tab to load the commands."
