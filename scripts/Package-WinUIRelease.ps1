[CmdletBinding()]
param(
    [string]$ProjectPath = ".\winui\ComputerRecoveryToolkit.WinUI\ComputerRecoveryToolkit.WinUI.csproj",
    [string]$OutputRoot = ".\artifacts",
    [string]$PackageName = "ComputerRecoveryToolkit-WinUI3-portable-win-x64",
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [string]$Platform = "x64",
    [switch]$Sign,
    [switch]$RequireSigning,
    [string]$PfxBase64 = $env:CODESIGN_PFX_BASE64,
    [string]$PfxPassword = $env:CODESIGN_PFX_PASSWORD
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot

$projectFullPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$outputFullPath = Join-Path $repoRoot $OutputRoot
$packageDir = Join-Path $outputFullPath $PackageName
$zipPath = Join-Path $outputFullPath "$PackageName.zip"
$checksumPath = Join-Path $outputFullPath "SHA256SUMS.txt"

Remove-Item -LiteralPath $packageDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $checksumPath -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

dotnet publish $projectFullPath `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:Platform=$Platform `
    -p:WindowsPackageType=None `
    -p:WindowsAppSDKSelfContained=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $packageDir

$removableExtensions = @(".pdb", ".ipdb", ".iobj", ".xml")
Get-ChildItem -LiteralPath $packageDir -Recurse -File |
    Where-Object { $_.Extension -in $removableExtensions } |
    Remove-Item -Force -ErrorAction SilentlyContinue

$createdump = Join-Path $packageDir "createdump.exe"
Remove-Item -LiteralPath $createdump -Force -ErrorAction SilentlyContinue

$keepCultures = @("en-US", "en-us", "pt-BR", "pt-PT")
Get-ChildItem -LiteralPath $packageDir -Directory |
    Where-Object { $_.Name -match '^[a-z]{2}(-[A-Za-z]{2,8}){0,2}$' -and $_.Name -notin $keepCultures } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

$hasSigningMaterial = -not [string]::IsNullOrWhiteSpace($PfxBase64) -and -not [string]::IsNullOrWhiteSpace($PfxPassword)
if ($Sign -or $RequireSigning -or $hasSigningMaterial) {
    if (-not $hasSigningMaterial) {
        if ($RequireSigning) {
            throw "Release signing is required, but CODESIGN_PFX_BASE64/CODESIGN_PFX_PASSWORD are missing."
        }
        Write-Warning "Signing skipped because certificate secrets are missing."
    } else {
        & (Join-Path $repoRoot "scripts\Sign-WindowsArtifact.ps1") -ArtifactDir $packageDir -PfxBase64 $PfxBase64 -PfxPassword $PfxPassword
    }
}

$packageItems = Get-ChildItem -LiteralPath $packageDir -Force
if (-not $packageItems) {
    throw "Package directory is empty: $packageDir"
}
Compress-Archive -Path $packageItems.FullName -DestinationPath $zipPath -CompressionLevel Optimal -Force

$hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
"$($hash.Hash.ToLowerInvariant())  $(Split-Path -Leaf $zipPath)" | Set-Content -LiteralPath $checksumPath -Encoding ASCII

Write-Host "Package: $zipPath"
Write-Host "Checksum: $checksumPath"
