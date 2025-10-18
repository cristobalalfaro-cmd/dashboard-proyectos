@echo off
setlocal enabledelayedexpansion

rem =========================================================
rem  Dashboard: Actualización de datos (segura / sin perder cambios)
rem  - Detecta Python (py o python), crea/usa .venv
rem  - pip: pandas, openpyxl
rem  - Convierte Excel -> data.json (scripts\convert_excel_to_json.py)
rem  - Actualiza cache-bust.txt
rem  - Stash (si hay cambios) -> pull --rebase -> pop
rem  - Commit/push SOLO de: data.json, cache-bust.txt, Template_Proyectos_Dashboard.xlsx
rem =========================================================

rem 0) Ir a la carpeta del .bat (raíz del repo)
cd /d "%~dp0"

rem Si por error quedó en /scripts, subir un nivel
if not exist ".git" (
  cd ..
)

set "EXCEL=Template_Proyectos_Dashboard.xlsx"
set "JSON=data.json"
set "VENV=.venv"
set "PYBIN="

echo.
echo ==== Dashboard: Actualizacion de datos (segura) ====
echo.

rem 1) Resolver Python
where py >nul 2>nul && set "PYBIN=py -3"
if not defined PYBIN (
  where python >nul 2>nul && set "PYBIN=python"
)
if not defined PYBIN (
  echo [x] No se encontro Python. Instala Python 3.10+ desde https://www.python.org/downloads/
  pause
  exit /b 1
)

rem 2) Crear venv si no existe
if not exist "%VENV%\Scripts\python.exe" (
  echo [*] Creando entorno virtual...
  %PYBIN% -m venv "%VENV%"
)

rem 3) Instalar deps
echo [*] Instalando dependencias (pandas, openpyxl)...
"%VENV%\Scripts\python.exe" -m pip install -q --upgrade pip
"%VENV%\Scripts\python.exe" -m pip install -q pandas openpyxl

rem 4) Traer cambios remotos de forma segura
echo [*] Trayendo cambios remotos...
for /f "delims=" %%b in ('git status --porcelain') do set CHANGES=1

set "STASH_NAME="
if defined CHANGES (
  echo [i] Hay cambios locales. Guardando temporalmente (stash)...
  for /f "delims=" %%s in ('git stash push -u -m "auto-stash antes de actualizar"') do (
    set "STASH_NAME=auto-stash antes de actualizar"
  )
)

rem Asegurar estar en main
for /f %%b in ('git branch --show-current') do set CUR=%%b
if /I not "%CUR%"=="main" (
  git fetch origin
  git checkout main || (echo [x] No se pudo cambiar a branch main & pause & exit /b 1)
)

git pull --rebase origin main
if errorlevel 1 (
  echo [x] Hubo conflictos al hacer pull --rebase. Resuelvelos y vuelve a ejecutar.
  echo     Sugerencia: git status, corrige conflictos, git add ., git rebase --continue
  goto :END
)

rem Reaplicar el stash si existía
if defined STASH_NAME (
  echo [*] Reaplicando cambios locales...
  git stash pop
  if errorlevel 1 (
    echo [!] El stash al reaplicarse genero conflictos.
    echo     Revisa "git status", resuelve conflictos y luego ejecuta nuevamente este .bat.
    goto :END
  )
)

rem 5) Ejecutar conversion Excel -> JSON
echo [*] Convirtiendo "%EXCEL%" a "%JSON%"...
if not exist "%EXCEL%" (
  echo [x] No se encontro "%EXCEL%" en la raiz del repo.
  pause
  exit /b 1
)

"%VENV%\Scripts\python.exe" scripts\convert_excel_to_json.py
if errorlevel 1 (
  echo [x] Error en la conversion. Revisa mensajes arriba.
  pause
  exit /b 1
)

rem 6) Actualizar cache-bust (para forzar refresco en GitHub Pages)
for /f "tokens=1-4 delims=/:. " %%a in ("%date% %time%") do set "TS=%%a-%%b-%%c_%%d"
> cache-bust.txt echo %TS%

rem 7) Commit/push de archivos generados
echo [*] Publicando cambios generados...
git add "%JSON%" cache-bust.txt "%EXCEL%" 2>nul
git commit -m "auto: publish %date% %time%" || echo (sin cambios que commitear)
git push origin main

echo.
echo [✓] Listo. En ~30-60s deberias ver los datos nuevos online.
echo     Si no ves cambios, Ctrl+F5 o limpia cache del navegador.
echo.
:END
pause
