@echo off
setlocal enabledelayedexpansion

rem === Ir a la raíz del repo ===
cd /d "%~dp0"

rem === Config ===
set "EXCEL=Template_Proyectos_Dashboard.xlsx"
set "JSON=data.json"
set "VENV=.venv"

echo.
echo ==== Dashboard: Actualizacion de datos ====
echo.

rem === Resolver Python ===
set "PYBIN="
where py >nul 2>nul && set "PYBIN=py -3"
if not defined PYBIN (
  where python >nul 2>nul && set "PYBIN=python"
)
if not defined PYBIN (
  echo [x] No se encontro Python. Instala Python 3.10+
  pause & exit /b 1
)

rem === Venv ===
if not exist "%VENV%\Scripts\python.exe" (
  %PYBIN% -m venv "%VENV%"
)

echo [*] Instalando dependencias (pandas, openpyxl)...
"%VENV%\Scripts\python.exe" -m pip install -q --upgrade pip
"%VENV%\Scripts\python.exe" -m pip install -q pandas openpyxl

echo [*] Convirtiendo "%EXCEL%" a "%JSON%"...
"%VENV%\Scripts\python.exe" scripts\convert_excel_to_json.py
if errorlevel 1 (
  echo [x] Error en la conversion. Revisa mensajes arriba.
  pause & exit /b 1
)

for /f "tokens=1-4 delims=/:. " %%a in ("%date% %time%") do set TS=%%a-%%b-%%c_%%d
> cache-bust.txt echo %TS%

echo [*] Sincronizando con remoto...
git add -A
git stash push -u -m "auto-stash before pull" >nul 2>&1
git pull --rebase origin main
git stash pop >nul 2>&1 || echo (sin cambios locales que aplicar)

git add "%JSON%" cache-bust.txt "%EXCEL%" 2>nul
git commit -m "auto: publish %date% %time%" || echo (sin cambios que commitear)
git push origin main

echo.
echo [✓] Listo. Revisa el sitio en GitHub Pages.
echo.
pause
