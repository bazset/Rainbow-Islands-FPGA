@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "REPO_URL=https://github.com/bazset/Rainbow-Islands-FPGA.git"
set "BRANCH=main"

echo ============================================================
echo  Pull GitHub README history, then push your code
echo  Folder : %CD%
echo ============================================================
echo.

where git >nul 2>&1
if errorlevel 1 (
  echo ERROR: Git not on PATH.
  pause
  exit /b 1
)

git remote set-url origin %REPO_URL% 2>nul
git remote add origin %REPO_URL% 2>nul

echo Fetching from GitHub...
git fetch origin
if errorlevel 1 (
  echo ERROR: git fetch failed. Check your login / network.
  pause
  exit /b 1
)

echo.
echo Merging remote history into your local repo...
git pull origin %BRANCH% --allow-unrelated-histories --no-edit
if errorlevel 1 (
  echo.
  echo Pull reported a problem. If it is a merge conflict in README.md:
  echo   1. Open README.md and keep YOUR version
  echo   2. Run:  git add README.md
  echo   3. Run:  git commit -m "Merge remote README"
  echo   4. Run this bat again
  echo.
  pause
  exit /b 1
)

echo.
echo Files currently tracked - spot check:
git ls-files | more
echo.

echo Pushing to GitHub...
git push -u origin %BRANCH%
if errorlevel 1 (
  echo ERROR: push failed.
  pause
  exit /b 1
)

echo.
echo Done. Open: %REPO_URL%
echo.
echo IMPORTANT: On the GitHub page, confirm you see rtl/, README.md, etc.
echo If you only see .gitignore and this bat, your source was never committed.
echo In that case run:  git add -A
echo                  git status
echo                  git commit -m "Add Rainbow Islands core source"
echo                  git push
echo.
pause
