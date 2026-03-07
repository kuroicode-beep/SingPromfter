@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ========================================
echo   SingPrompt - 로컬 서버 실행
echo ========================================
echo.

where npx >nul 2>&1
if %errorlevel% equ 0 (
  echo [npx serve] 서버 시작 중...
  echo 브라우저에서 http://localhost:3000 접속
  echo 종료: Ctrl+C
  echo.
  npx -y serve . -p 3000
  goto :eof
)

where python >nul 2>&1
if %errorlevel% equ 0 (
  echo [Python] 서버 시작 중...
  echo 브라우저에서 http://localhost:3000 접속
  echo 종료: Ctrl+C
  echo.
  python -m http.server 3000
  goto :eof
)

echo [오류] Node(npx) 또는 Python이 필요합니다.
echo - Node: https://nodejs.org
echo - Python: https://python.org
pause
