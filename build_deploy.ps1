# build_deploy.ps1 - SingPromfter one-click release: build -> deploy to dist -> refresh desktop shortcut
# Usage:  powershell -ExecutionPolicy Bypass -File build_deploy.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dist = Join-Path $root 'dist\SingPromfter'
$release = Join-Path $root 'build\windows\x64\runner\Release'

# app version comes from lib/constants/app_version.dart (single source of truth)
$verFile = Join-Path $root 'lib\constants\app_version.dart'
$version = ([regex]::Match((Get-Content $verFile -Raw), "current\s*=\s*'([^']+)'")).Groups[1].Value
if (-not $version) { throw 'cannot read version from lib/constants/app_version.dart' }

# guard: pubspec version must match AppVersion.current (they drifted 5.2.0 vs 5.5.0 once)
$pubVer = ([regex]::Match((Get-Content (Join-Path $root 'pubspec.yaml') -Raw), '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')).Groups[1].Value
if ($pubVer -ne $version) { throw "version mismatch: pubspec.yaml=$pubVer, app_version.dart=$version" }
Write-Host "[1/4] building SingPromfter v$version ..."

# stop a running instance so the exe is not locked
Get-Process singpromfter_app -ErrorAction SilentlyContinue | Stop-Process -Force
Set-Location $root
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

Write-Host '[2/4] deploying to dist\SingPromfter ...'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Copy-Item "$release\*" $dist -Recurse -Force

$exe = Join-Path $dist 'singpromfter_app.exe'
if (-not (Test-Path $exe)) { throw "deploy failed: $exe not found" }

Write-Host '[3/4] refreshing desktop shortcut ...'
$desktop = [Environment]::GetFolderPath('Desktop')
$sh = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut((Join-Path $desktop 'SingPromfter.lnk'))
$lnk.TargetPath = $exe
$lnk.WorkingDirectory = $dist
$lnk.IconLocation = "$exe,0"
$lnk.Description = "SingPromfter v$version - low-vision lyrics prompter"
$lnk.Save()

Write-Host '[4/4] done.'
Write-Host "  version : v$version"
Write-Host "  exe     : $exe"
Write-Host "  shortcut: $(Join-Path $desktop 'SingPromfter.lnk')"
