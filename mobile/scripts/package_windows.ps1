# Build Flutter Windows release and optionally package with Inno Setup.
# Run on Windows with Flutter in PATH.
# Output:
#   build\windows\x64\runner\Release\          — app folder
#   dist\qingya-windows-setup.exe              — installer (if ISCC available)

param(
  [string]$InnoScript = "$PSScriptRoot\qingya_windows.iss",
  [string]$OutDir = "$PSScriptRoot\..\..\dist\flutter"
)

$ErrorActionPreference = "Stop"
Set-Location "$PSScriptRoot\.."

Write-Host "flutter pub get"
flutter pub get

Write-Host "flutter build windows --release"
flutter build windows --release

$releaseDir = "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
  throw "Release dir not found: $releaseDir"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$iscc = Get-Command iscc -ErrorAction SilentlyContinue
if ($null -eq $iscc) {
  $candidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { $iscc = @{ Source = $c }; break }
  }
}

if ($null -ne $iscc) {
  Write-Host "Packaging with Inno Setup: $($iscc.Source)"
  & $iscc.Source $InnoScript
  $setup = "build\windows\qingya-windows-setup.exe"
  if (Test-Path $setup) {
    Copy-Item -Force $setup "$OutDir\qingya-windows-setup.exe"
    Write-Host "Wrote $OutDir\qingya-windows-setup.exe"
  } else {
    Write-Warning "Inno finished but setup not at $setup"
  }
} else {
  Write-Warning "ISCC not found. Copying portable zip instead."
  $zip = "$OutDir\qingya-windows-portable.zip"
  if (Test-Path $zip) { Remove-Item $zip }
  Compress-Archive -Path "$releaseDir\*" -DestinationPath $zip
  Write-Host "Wrote $zip (install Inno Setup 6 to produce qingya-windows-setup.exe)"
}
