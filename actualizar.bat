@echo off
setlocal enabledelayedexpansion
REM === Publica cambios del dashboard en GitHub (branch main) ===

REM Ir a la carpeta donde está este .bat
cd /d "%~dp0"

REM Verificar que existe .git
if not exist ".git" (
  echo [ERROR] Esta carpeta no parece ser un repositorio Git.
  echo Abre una terminal aqui y ejecuta:  git init && git branch -M main && git remote add origin https://github.com/TU_USUARIO/TU_REPO.git
  pause
  exit /b 1
)

REM Agregar cambios
git add -A

REM Commit con timestamp (si hay cambios)
for /f "tokens=1-3 delims=/ " %%a in ("%date%") do ( set FECHA=%%a-%%b-%%c )
set HORA=%time: =0%
set MSG=auto: publish %FECHA% %HORA%
git commit -m "%MSG%" || echo [INFO] No hay cambios para commitear.

REM Push a main
git push -u origin main

echo.
echo ✔ Publicado. Abre tu sitio y recarga con Ctrl+F5.
echo (Si no ves cambios, ejecuta force-rebuild.bat)
pause