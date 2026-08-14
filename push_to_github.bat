@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "GIT_NAME=baz"
set "GIT_EMAIL=baz@baz.com"
set "REPO_URL=https://github.com/bazset/Rainbow-Islands-FPGA.git"
set "BRANCH=main"

echo ============================================================
echo  Rainbow Islands - push source to GitHub
echo  Folder : %CD%
echo  Remote : %REPO_URL%
echo  Author : %GIT_NAME% ^<%GIT_EMAIL%^>
echo ============================================================
echo.

where git >nul 2>&1
if errorlevel 1 goto :no_git

git config user.name "%GIT_NAME%"
git config user.email "%GIT_EMAIL%"

if exist ".git" goto :have_git
echo Initializing new Git repository...
git init
if errorlevel 1 goto :fail_init
goto :after_init

:have_git
echo Git repository already present.

:after_init

if exist ".gitignore" goto :have_ignore
echo Creating .gitignore ...
> ".gitignore" (
  echo # Quartus / build
  echo db/
  echo incremental_db/
  echo output_files/
  echo *.sof
  echo *.pof
  echo *.rbf
  echo *.rpt
  echo *.done
  echo *.qws
  echo *.summary
  echo *.smsg
  echo *.jdi
  echo *.pin
  echo *.srf
  echo # Simulation
  echo transcript
  echo modelsim.ini
  echo *.vcd
  echo *.wlf
  echo *.cr.mti
  echo work/
  echo # Local / editor
  echo .claude/
  echo *.bak
  echo *.orig
  echo *~
)

:have_ignore

echo.
echo Staging files...
git add .
if errorlevel 1 goto :fail_add

echo.
echo Current status:
git status --short
echo.

REM Commit if there are staged changes
git diff --cached --quiet
if errorlevel 1 goto :do_commit
echo Nothing new to commit - working tree clean or already committed.
goto :after_commit

:do_commit
git commit -m "Initial commit: Rainbow Islands MiSTer core"
if errorlevel 1 goto :fail_commit

:after_commit

echo.
echo Setting branch to %BRANCH% ...
git branch -M %BRANCH%

git remote get-url origin >nul 2>&1
if errorlevel 1 goto :add_remote
echo Updating remote origin URL...
git remote set-url origin %REPO_URL%
goto :remote_done

:add_remote
echo Adding remote origin...
git remote add origin %REPO_URL%

:remote_done

echo.
echo Remote configured as:
git remote -v
echo.

echo ------------------------------------------------------------
echo About to push to GitHub.
echo If asked for credentials:
echo   Username = your GitHub username
echo   Password = a Personal Access Token  NOT your GitHub password
echo   Create token: GitHub Settings, Developer settings, Personal access tokens
echo ------------------------------------------------------------
echo.
choice /C YN /M "Push to GitHub now"
if errorlevel 2 goto :cancelled

echo.
git push -u origin %BRANCH%
if errorlevel 1 goto :fail_push

echo.
echo Done. Check: %REPO_URL%
echo.
pause
exit /b 0

:cancelled
echo Cancelled. Local commit is done.
echo Push later with:  git push -u origin %BRANCH%
pause
exit /b 0

:no_git
echo ERROR: Git is not installed or not on PATH.
echo Download: https://git-scm.com/download/win
pause
exit /b 1

:fail_init
echo ERROR: git init failed.
pause
exit /b 1

:fail_add
echo ERROR: git add failed.
pause
exit /b 1

:fail_commit
echo ERROR: git commit failed.
pause
exit /b 1

:fail_push
echo.
echo Push failed. Common fixes:
echo   - Sign in with a Personal Access Token when prompted for password
echo   - If the GitHub repo already has a README commit, run:
echo       git pull origin %BRANCH% --allow-unrelated-histories
echo     then run this bat again
echo.
pause
exit /b 1
