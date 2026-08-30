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

# 원격이 앞서 있으면 push 가 거부된다 — 다른 경로(웹 콘솔 편집, npm run deploy 등)가
# gh-pages 를 먼저 밀어 둔 경우다. 2026-08-30 하루에 두 프로젝트가 이걸로 배포에 실패했다.
# 배포는 site\ 내용으로 덮어쓰는 동작이므로, 시작할 때 원격 끝점에 맞춰 두면 된다.
# git fetch 는 진행 상황을 stderr 로 쓴다. PowerShell 5.1 은 $ErrorActionPreference='Stop' 에서
# 그걸 NativeCommandError 로 승격시켜 스크립트를 죽이므로 이 구간만 완화한다.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
git fetch origin gh-pages *>$null
$ErrorActionPreference = $prevEap
$remoteHead = (git rev-parse --verify --quiet refs/remotes/origin/gh-pages)

git show-ref --verify --quiet refs/heads/gh-pages
$exists = ($LASTEXITCODE -eq 0)

if ($exists -and $remoteHead) {
    # 워크트리에 물려 있으면 브랜치를 직접 못 옮기므로, 워크트리를 만든 뒤 그 안에서 맞춘다.
    git worktree add $work gh-pages | Out-Null
    Push-Location $work
    git reset --hard $remoteHead | Out-Null
    Pop-Location
} elseif ($exists) {
    git worktree add $work gh-pages | Out-Null
} else {
    git worktree add --detach $work | Out-Null
    Push-Location $work
    git checkout --orphan gh-pages | Out-Null
    git rm -rf . 2>$null | Out-Null
    Pop-Location
}

try {
    # gh-pages 를 통째로 비우기 전에 CNAME(커스텀 도메인)을 살려 둔다. 2026-08-30 추가 —
    # site\ 에 CNAME 이 없는 저장소는 이걸 안 하면 배포할 때마다 도메인이 끊긴다.
    $cnamePath = Join-Path $work "CNAME"
    $cnameKeep = $null
    if ((Test-Path $cnamePath) -and -not (Test-Path (Join-Path $src "CNAME"))) {
        $cnameKeep = (Get-Content $cnamePath -Raw).Trim()
    }

    Get-ChildItem $work -Force |
        Where-Object { $_.Name -ne ".git" } |
        Remove-Item -Recurse -Force
    Copy-Item (Join-Path $src "*") $work -Recurse -Force
    Remove-Item (Join-Path $work "README.md") -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path (Join-Path $work ".nojekyll"))) {
        New-Item -ItemType File (Join-Path $work ".nojekyll") | Out-Null
    }
    if ($cnameKeep) {
        [IO.File]::WriteAllText($cnamePath, $cnameKeep, [Text.UTF8Encoding]::new($false))
        Write-Host "CNAME 보존: $cnameKeep  (영구 반영하려면 site\CNAME 으로 옮길 것)"
    }

    Push-Location $work
    git add -A
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "변경 없음 — 배포를 건너뜁니다."
    } else {
        git commit -m ("Publish site " + (Get-Date -Format "yyyy-MM-dd HH:mm")) | Out-Null
        git push origin gh-pages
        # push 가 거부됐는데 「배포 완료」를 찍던 결함(2026-08-30 실측). 종료코드를 반드시 본다.
        # 거부되면 대개 원격이 앞선 것이다 — git fetch 후 gh-pages 를 원격 끝점에 맞추고 다시 돌린다.
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            throw "push 실패 (exit $LASTEXITCODE) — 배포되지 않았다."
        }
        Write-Host "배포 완료."
    }
    Pop-Location
} finally {
    git worktree remove $work --force 2>$null | Out-Null
}
