[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ArtifactDir,

    [string]$PfxBase64 = $env:CODESIGN_PFX_BASE64,
    [string]$PfxPassword = $env:CODESIGN_PFX_PASSWORD,
    [string]$PfxPath = $env:CODESIGN_PFX_PATH,
    [string]$TimestampServer = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ArtifactDir)) {
    throw "Artifact directory not found: $ArtifactDir"
}

if ([string]::IsNullOrWhiteSpace($PfxPassword)) {
    throw "CODESIGN_PFX_PASSWORD is required for signing."
}

$tempPfxPath = $null
if ([string]::IsNullOrWhiteSpace($PfxPath)) {
    if ([string]::IsNullOrWhiteSpace($PfxBase64)) {
        throw "CODESIGN_PFX_BASE64 or CODESIGN_PFX_PATH is required for signing."
    }
    $tempPfxPath = Join-Path ([IO.Path]::GetTempPath()) "computer-recovery-toolkit-codesign.pfx"
    [IO.File]::WriteAllBytes($tempPfxPath, [Convert]::FromBase64String($PfxBase64))
    $PfxPath = $tempPfxPath
}

try {
    $targets = Get-ChildItem -LiteralPath $ArtifactDir -Recurse -File -Include *.exe |
        Where-Object { $_.Name -eq "ComputerRecoveryToolkit.WinUI.exe" }

    if (-not $targets) {
        throw "ComputerRecoveryToolkit.WinUI.exe was not found under $ArtifactDir"
    }

    $signtool = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    foreach ($target in $targets) {
        Write-Host "Signing $($target.FullName)"
        if ($signtool) {
            & $signtool.FullName sign /f $PfxPath /p $PfxPassword /fd SHA256 /tr $TimestampServer /td SHA256 /v $target.FullName
            if ($LASTEXITCODE -ne 0) { throw "signtool failed with exit code $LASTEXITCODE" }
            & $signtool.FullName verify /pa /v $target.FullName
            if ($LASTEXITCODE -ne 0) { throw "signtool verification failed with exit code $LASTEXITCODE" }
        } else {
            $securePassword = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
            $cert = Get-PfxCertificate -FilePath $PfxPath -Password $securePassword -NoPromptForPassword
            $signature = Set-AuthenticodeSignature -FilePath $target.FullName -Certificate $cert -TimestampServer $TimestampServer
            $signature | Out-Host
            if ($signature.Status -notin @("Valid", "UnknownError")) {
                throw "Authenticode signing failed: $($signature.Status) $($signature.StatusMessage)"
            }
        }
    }
} finally {
    if ($tempPfxPath) {
        Remove-Item -LiteralPath $tempPfxPath -Force -ErrorAction SilentlyContinue
    }
}
