@echo off
setlocal

rem ========== CONFIG ==========
set "SCRIPTS_DIR=scripts"
set "PY_CONVERTER=convert_excel_to_json.py"
set "EXCEL_FILE=Template_Proyectos_Dashboard.xlsx"
set "BRANCH=main"
rem ============================

echo ==== Dashboard Update ====
echo [*] Checking Python...
python --version
if errorlevel 1 (
  echo [x] Python not found or not in PATH.
  pause
  exit /b 1
)

echo [*] Git sync...
git fetch origin
git pull --rebase origin %BRANCH%
if errorlevel 1 (
  echo [x] Git pull failed.
  pause
  exit /b 1
)

echo [*] Running converter...
if not exist "%SCRIPTS_DIR%\%PY_CONVERTER%" (
  echo [x] Script %SCRIPTS_DIR%\%PY_CONVERTER% not found.
  pause
  exit /b 1
)
python "%SCRIPTS_DIR%\%PY_CONVERTER%"
if errorlevel 1 (
  echo [x] Conversion failed.
  pause
  exit /b 1
)

echo [*] Updating cache-bust.txt...
echo %date% %time%>cache-bust.txt

echo [*] Committing and pushing...
git add -A
git commit -m "auto: publish %date% %time%" >NUL 2>&1
git push origin %BRANCH%
if errorlevel 1 (
  echo [x] Git push failed.
  pause
  exit /b 1
)

echo [OK] Dashboard updated and synced.
pause
