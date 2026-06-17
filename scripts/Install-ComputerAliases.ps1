[CmdletBinding()]
param()

$kitRoot = Split-Path -Parent $PSScriptRoot
$toolsPath = Join-Path $PSScriptRoot "Computer-PowerShell-Tools.ps1"

$content = @"
# Computer Recovery Toolkit helper commands.
`$script:ComputerKitRoot = "$kitRoot"
`$script:ComputerScripts = Join-Path `$script:ComputerKitRoot "scripts"

function Invoke-ComputerDiagnostics {
    & (Join-Path `$script:ComputerScripts "Collect-ComputerDiagnostics.ps1") @args
}

function Invoke-ComputerEnergyDiagnostics {
    & (Join-Path `$script:ComputerScripts "Collect-ComputerDiagnostics.ps1") -IncludeEnergyTrace @args
}

function Invoke-ComputerPowerFix {
    & (Join-Path `$script:ComputerScripts "Apply-ComputerPowerPolicy.ps1") @args
}

function Invoke-ComputerGpuAnalyze {
    & (Join-Path `$script:ComputerScripts "Get-DgpuProcesses.ps1") @args
}

function Invoke-ComputerGpuDrain {
    & (Join-Path `$script:ComputerScripts "Invoke-ComputerGpuDrain.ps1") -ShowNvidiaProcesses @args
}

function Invoke-ComputerGpuPreference {
    & (Join-Path `$script:ComputerScripts "Set-AppGpuPreference.ps1") @args
}

function Set-ComputerKitLocation {
    Set-Location -LiteralPath `$script:ComputerKitRoot
}

Set-Alias computer-diag Invoke-ComputerDiagnostics
Set-Alias computer-energy Invoke-ComputerEnergyDiagnostics
Set-Alias computer-power-fix Invoke-ComputerPowerFix
Set-Alias computer-gpu Invoke-ComputerGpuAnalyze
Set-Alias computer-gpu-drain Invoke-ComputerGpuDrain
Set-Alias computer-gpu-pref Invoke-ComputerGpuPreference
Set-Alias computer-kit Set-ComputerKitLocation
"@

Set-Content -LiteralPath $toolsPath -Value $content -Encoding UTF8

$profiles = @(
    $PROFILE.CurrentUserCurrentHost,
    (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"),
    (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PowerShell\Microsoft.PowerShell_profile.ps1")
) | Sort-Object -Unique

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

    $pattern = "(?s)" + [regex]::Escape($begin) + ".*?" + [regex]::Escape($end)
    $updated = if ($existing -match $pattern) {
        [regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $loader })
    } else {
        ($existing.TrimEnd() + "`r`n`r`n" + $loader).TrimStart()
    }

    Set-Content -LiteralPath $profilePath -Value $updated -Encoding UTF8
    Write-Host "Updated profile: $profilePath"
}

Write-Host "Aliases installed. Open a new PowerShell/Windows Terminal tab."

