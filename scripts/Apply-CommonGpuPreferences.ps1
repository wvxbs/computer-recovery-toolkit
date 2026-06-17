[CmdletBinding()]
param(
    [switch]$Apply,
    [string[]]$ExtraPowerSavingApps = @()
)

$apps = @(
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
) + $ExtraPowerSavingApps

$resolved = foreach ($app in $apps) {
    if ($app -like "*`**") {
        Get-ChildItem -Path (Split-Path -Parent $app) -Filter (Split-Path -Leaf $app) -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            ForEach-Object { $_.FullName }
    } elseif (Test-Path -LiteralPath $app -PathType Leaf) {
        (Resolve-Path -LiteralPath $app).Path
    }
}

$resolved = @($resolved | Sort-Object -Unique)

if (-not $Apply) {
    Write-Host "Preview mode. Add -Apply to write HKCU GPU preferences." -ForegroundColor Yellow
    $resolved
    exit 0
}

$key = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
New-Item -Path $key -Force | Out-Null
foreach ($path in $resolved) {
    New-ItemProperty -LiteralPath $key -Name $path -Value "GpuPreference=1;" -PropertyType String -Force | Out-Null
    Write-Host "PowerSaving: $path"
}

Write-Host "Close and reopen affected apps for the changes to apply."

