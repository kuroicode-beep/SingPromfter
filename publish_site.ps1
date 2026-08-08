# site\ 폴더를 gh-pages 브랜치로 배포한다 (GitHub Pages가 서빙하는 브랜치).
# 사용법: 프로젝트 루트에 두고  .\publish_site.ps1
# 한글 주석이 있으므로 이 파일은 반드시 UTF-8 BOM으로 저장할 것 (PS 5.1이 CP949로 오독하는 것 방지).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$src = Join-Path $PSScriptRoot "site"
if (-not (Test-Path (Join-Path $src "index.html"))) {
    throw "site\index.html 이 없습니다."
}

# 워크트리로 gh-pages를 따로 체크아웃해 현재 작업 내용을 건드리지 않는다.
$work = Join-Path $env:TEMP ("ghpages-" + [guid]::NewGuid().ToString("N").Substring(0, 8))

git show-ref --verify --quiet refs/heads/gh-pages
$exists = ($LASTEXITCODE -eq 0)

if ($exists) {
    git worktree add $work gh-pages | Out-Null
} else {
    git worktree add --detach $work | Out-Null
    Push-Location $work
    git checkout --orphan gh-pages | Out-Null
    git rm -rf . 2>$null | Out-Null
    Pop-Location
}

try {
    Get-ChildItem $work -Force |
        Where-Object { $_.Name -ne ".git" } |
        Remove-Item -Recurse -Force
    Copy-Item (Join-Path $src "*") $work -Recurse -Force
    Remove-Item (Join-Path $work "README.md") -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path (Join-Path $work ".nojekyll"))) {
        New-Item -ItemType File (Join-Path $work ".nojekyll") | Out-Null
    }

    Push-Location $work
    git add -A
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "변경 없음 — 배포를 건너뜁니다."
    } else {
        git commit -m ("Publish site " + (Get-Date -Format "yyyy-MM-dd HH:mm")) | Out-Null
        git push origin gh-pages
        Write-Host "배포 완료."
    }
    Pop-Location
} finally {
    git worktree remove $work --force 2>$null | Out-Null
}
