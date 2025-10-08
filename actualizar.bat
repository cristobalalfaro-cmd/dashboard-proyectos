@echo off
setlocal ENABLEDELAYEDEXPANSION
REM === Publica cambios del dashboard en GitHub (branch main) ===

REM 1) Ir a la carpeta del script
cd /d "%~dp0"

REM 2) Validar que es un repo Git
git rev-parse --is-inside-work-tree >NUL 2>&1
if errorlevel 1 (
  echo [ERROR] Esta carpeta no es un repositorio Git.
  echo Abre una terminal aqui y ejecuta:
  echo   git init
  echo   git branch -M main
  echo   git remote add origin https://github.com/cristobalalfaro-cmd/dashboard-proyectos.git
  pause
  exit /b 1
)

REM 3) Asegurar branch main
git rev-parse --abbrev-ref HEAD | findstr /i "main" >NUL
if errorlevel 1 (
  echo [INFO] Cambiando/creando branch main...
  git checkout -B main
)

REM 4) Asegurar remoto "origin"
git remote get-url origin >NUL 2>&1
if errorlevel 1 (
  echo [INFO] Configurando remoto origin...
  git remote add origin https://github.com/cristobalalfaro-cmd/dashboard-proyectos.git
)

REM 5) Traer ultimos cambios para evitar conflictos (ignora si no hay)
git pull --ff-only origin main >NUL 2>&1

REM 6) Agregar todo
git add -A

REM 7) Timestamp robusto (independiente de la region) con PowerShell
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm-ss"') do set TS=%%I
set "MSG=auto: publish %TS%"

REM 8) Commit solo si hay cambios staged
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "%MSG%"
) else (
  echo [INFO] No hay cambios para commitear.
)

REM 9) Push a main
git push -u origin main
if errorlevel 1 (
  echo [ERROR] Fallo el push. Revisa tu conexion o permisos del repo.
  pause
  exit /b 1
)

echo.
echo ✔ Publicado. Abre tu sitio y recarga con Ctrl+F5:
echo   https://cristobalalfaro-cmd.github.io/dashboard-proyectos/
echo.
echo Si necesitas forzar un redeploy sin cambios, ejecuta: force-rebuild.bat
pause
