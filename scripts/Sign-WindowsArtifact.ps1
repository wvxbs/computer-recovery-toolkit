[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ArtifactDir,

    [string]$PfxBase64 = $env:CODESIGN_PFX_BASE64,
    [string]$PfxPassword = $env:CODESIGN_PFX_PASSWORD,
    [string]$TimestampServer = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ArtifactDir)) {
    throw "Artifact directory not found: $ArtifactDir"
}

if ([string]::IsNullOrWhiteSpace($PfxBase64) -or [string]::IsNullOrWhiteSpace($PfxPassword)) {
    throw "CODESIGN_PFX_BASE64 and CODESIGN_PFX_PASSWORD are required for signing."
}

$pfxPath = Join-Path ([IO.Path]::GetTempPath()) "computer-recovery-toolkit-codesign.pfx"
[IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($PfxBase64))

try {
    $securePassword = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
    $cert = Get-PfxCertificate -FilePath $pfxPath -Password $securePassword -NoPromptForPassword
    $targets = Get-ChildItem -LiteralPath $ArtifactDir -Recurse -File -Include *.exe,*.dll |
        Where-Object { $_.Name -eq "ComputerRecoveryToolkit.WinUI.exe" }

    foreach ($target in $targets) {
        Write-Host "Signing $($target.FullName)"
        Set-AuthenticodeSignature -FilePath $target.FullName -Certificate $cert -TimestampServer $TimestampServer | Out-Host
    }
} finally {
    Remove-Item -LiteralPath $pfxPath -Force -ErrorAction SilentlyContinue
}
