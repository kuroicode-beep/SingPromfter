# build_apk.ps1 - SingPromfter Android release: build split APKs -> collect into dist\android
# Usage:  powershell -ExecutionPolicy Bypass -File build_apk.ps1
#
# Why split-per-abi: the universal APK carries native code for every ABI.
# Measured 2026-08-31: universal 102.4MB vs arm64-v8a 66.3MB (~35% smaller).
# Phones only ever need one of them.
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $root 'dist\android'
$apkDir = Join-Path $root 'build\app\outputs\flutter-apk'

# app version comes from lib/constants/app_version.dart (single source of truth)
$verFile = Join-Path $root 'lib\constants\app_version.dart'
$version = ([regex]::Match((Get-Content $verFile -Raw), "current\s*=\s*'([^']+)'")).Groups[1].Value
if (-not $version) { throw 'cannot read version from lib/constants/app_version.dart' }

# guard: pubspec version must match AppVersion.current (same rule as build_deploy.ps1)
$pubVer = ([regex]::Match((Get-Content (Join-Path $root 'pubspec.yaml') -Raw), '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')).Groups[1].Value
if ($pubVer -ne $version) { throw "version mismatch: pubspec.yaml=$pubVer, app_version.dart=$version" }

Write-Host "[1/3] building SingPromfter v$version APKs (split per ABI) ..."
Set-Location $root
flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed ($LASTEXITCODE)" }

Write-Host '[2/3] collecting to dist\android ...'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$found = 0
foreach ($abi in @('arm64-v8a', 'armeabi-v7a', 'x86_64')) {
    $src = Join-Path $apkDir "app-$abi-release.apk"
    if (-not (Test-Path $src)) { continue }
    Copy-Item $src (Join-Path $out "singpromfter-$version-$abi.apk") -Force
    $found++
}
if ($found -eq 0) { throw "no APK found in $apkDir" }

Write-Host '[3/3] done.'
Write-Host "  version : v$version"
Get-ChildItem $out -Filter "singpromfter-$version-*.apk" | ForEach-Object {
    '  {0,-40} {1,8:N1} MB' -f $_.Name, ($_.Length / 1MB)
}
Write-Host ''
Write-Host '  NOTE: signed with the debug key unless android/key.properties exists.'
Write-Host '        Most phones need the arm64-v8a build.'
