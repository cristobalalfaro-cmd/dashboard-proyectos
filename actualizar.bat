@echo off
setlocal enabledelayedexpansion

REM === Config ===
set EXCEL=Template_Proyectos_Dashboard.xlsx
set JSON=data.json
set VENV=.venv

echo.
echo ==== Dashboard: Actualizacion de datos ====
echo.

REM 1) Verifica Python
where python >nul 2>nul
if errorlevel 1 (
  echo [x] Python no esta instalado o no esta en PATH.
  echo     Instala Python 3.10+ desde https://www.python.org/downloads/ y reintenta.
  pause
  exit /b 1
)

REM 2) Crea venv si no existe
if not exist "%VENV%\Scripts\python.exe" (
  echo [*] Creando entorno virtual...
  python -m venv "%VENV%"
)

REM 3) Instala dependencias
echo [*] Instalando dependencias (pandas, openpyxl)...
"%VENV%\Scripts\python" -m pip install -q --upgrade pip
"%VENV%\Scripts\python" -m pip install -q pandas openpyxl

REM 4) Ejecuta conversion Excel -> JSON
echo [*] Convirtiendo "%EXCEL%" a "%JSON%"...
"%VENV%\Scripts\python" convert_excel_to_json.py
if errorlevel 1 (
  echo [x] Error en la conversion. Revisa mensajes arriba.
  pause
  exit /b 1
)

REM 5) Toca cache-bust (opcional) para forzar despliegue
for /f "tokens=1-4 delims=/:. " %%a in ("%date% %time%") do set TS=%%a-%%b-%%c_%%d
echo %TS%> cache-bust.txt

REM 6) Commit + push
echo [*] Publicando a GitHub...
git add "%JSON%" cache-bust.txt "%EXCEL%" 2>nul
git commit -m "auto: publish %date% %time%" || echo (sin cambios que commitear)
git push origin main

echo.
echo [✓] Listo. En ~30-60s deberias ver los datos nuevos online.
echo     Si no ves cambios, recarga con Ctrl+F5 o desregistra el SW en DevTools.
echo.
pause