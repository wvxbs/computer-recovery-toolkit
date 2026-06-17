[CmdletBinding()]
param(
    [string]$List
)

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    if (-not [string]::IsNullOrWhiteSpace($List)) { $args += @("-List", "`"$List`"") }
    Start-Process powershell.exe -ArgumentList $args -Verb RunAs
    exit
}

$smi = Join-Path $env:WINDIR "System32\nvidia-smi.exe"
if (-not (Test-Path -LiteralPath $smi)) {
    Write-Host "nvidia-smi.exe not found." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 0
}

$requested = @()
if (-not [string]::IsNullOrWhiteSpace($List)) {
    $requested = $List -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique
}

$protected = '^(dwm|csrss|winlogon|explorer|System|Registry|Idle)$'
$gpuApps = & $smi --query-compute-apps=pid,name --format=csv,noheader 2>$null

if (-not $gpuApps) {
    Write-Host "No dGPU processes detected." -ForegroundColor Green
    exit 0
}

foreach ($app in $gpuApps) {
    $parts = $app -split ",", 2
    if ($parts.Count -lt 2) { continue }
    $pidText = $parts[0].Trim()
    $path = $parts[1].Trim()
    $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
    if (-not $name -or $name -match $protected) { continue }

    [int]$pid = 0
    if (-not [int]::TryParse($pidText, [ref]$pid)) { continue }

    if ($requested.Count -gt 0 -and $requested -notcontains $name) { continue }

    Write-Host ""
    Write-Host "Process using dGPU:" -ForegroundColor Cyan
    Write-Host "Name: $name"
    Write-Host "PID:  $pid"
    Write-Host "Path: $path"

    $answer = "R"
    if ($requested.Count -eq 0) {
        $answer = Read-Host "Action? [R]estart, [K]ill, [I]gnore"
    }

    switch -Regex ($answer) {
        "^[rR]" {
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            if (Test-Path -LiteralPath $path) {
                Start-Process -FilePath "explorer.exe" -ArgumentList "`"$path`"" -ErrorAction SilentlyContinue
                Write-Host "Restarted: $name" -ForegroundColor Green
            }
        }
        "^[kK]" {
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
            Write-Host "Killed: $name" -ForegroundColor Yellow
        }
        default {
            Write-Host "Ignored: $name" -ForegroundColor Gray
        }
    }
}

if ([string]::IsNullOrWhiteSpace($List)) {
    Read-Host "Press Enter to exit"
}

