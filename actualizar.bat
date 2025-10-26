@echo off
setlocal enabledelayedexpansion

rem =========================================================
rem  actualizar.bat  (dashboard-proyectos)
rem  Flujo:
rem   1) Detecta Python y usa .venv
rem   2) Instala deps solo si faltan (pandas, openpyxl)
rem   3) Git pull --rebase (stash si hay cambios)
rem   4) Convierte Excel -> JSON con scripts\convert_excel_to_json.py
rem   5) Escribe cache-bust.txt (timestamp)
rem   6) Commit + push de TODO el repo
rem =========================================================

rem ---------- Config rapida ----------
set "SCRIPTS_DIR=scripts"
set "PY_VENV=.venv"
set "EXCEL_BASE=Template_Proyectos_Dashboard"
set "PY_CONVERTER=convert_excel_to_json.py"
set "PUSH_ALL=1"   rem 1 = add -A; 0 = solo data.json + cache-bust + excel
rem -----------------------------------

rem 0) Ir a la carpeta donde esta este .bat (raiz)
cd /d "%~dp0"

rem Verificar repo git
git rev-parse --is-inside-work-tree >NUL 2>&1 || (
  echo [x] No es un repositorio Git. Abre una consola en la carpeta del repo y ejecuta de nuevo.
  pause
  exit /b 1
)

echo.
echo ==== Dashboard: Actualizacion de datos ====
echo.

rem 1) Resolver Python (py -3 o python)
set "PYBIN="
where py >nul 2>nul && set "PYBIN=py -3"
if not defined PYBIN where python >nul 2>nul && set "PYBIN=python"
if not defined PYBIN (
  echo [x] No se encontro Python 3. Instala desde https://www.python.org/downloads/
  pause
  exit /b 1
)

rem 2) Crear venv si no existe
if not exist "%PY_VENV%\Scripts\python.exe" (
  echo [*] Creando entorno virtual...
  %PYBIN% -m venv "%PY_VENV%"
)

echo [*] Verificando dependencias Python...
"%PY_VENV%\Scripts\python.exe" -c "import pandas,openpyxl" >NUL 2>&1
if errorlevel 1 (
  echo [*] Instalando pandas y openpyxl...
  "%PY_VENV%\Scripts\python.exe" -m pip install -q --disable-pip-version-check --upgrade pip
  "%PY_VENV%\Scripts\python.exe" -m pip install -q --disable-pip-version-check pandas openpyxl
)

rem 3) Git: detectar cambios locales y hacer pull --rebase
echo [*] Sincronizando con remoto...

set "CHANGES="
for /f "delims=" %%A in ('git status --porcelain') do (
  set "CHANGES=1"
  goto :AfterLocalScan
)
:AfterLocalScan

if defined CHANGES (
  echo [i] Hay cambios locales. Guardando en stash temporal...
  git stash push -u -m "auto-stash antes de actualizar" >NUL
  set "HAD_STASH=1"
) else (
  echo [i] Sin cambios locales antes de actualizar.
)

rem Detectar rama actual (fallback main)
set "CURBR="
for /f %%B in ('git branch --show-current') do set "CURBR=%%B"
if not defined CURBR set "CURBR=main"

git fetch origin
git pull --rebase origin %CURBR%
if errorlevel 1 (
  echo [x] Conflictos al hacer pull --rebase. Resuelve y reintenta:
  echo     git status
  echo     corregir conflictos
  echo     git add .
  echo     git rebase --continue
  goto :END
)

if defined HAD_STASH (
  echo [*] Reaplicando cambios locales del stash...
  git stash pop
  if errorlevel 1 (
    echo [!] Hubo conflictos al aplicar el stash. Revisa "git status", resuelvelos y reintenta.
    goto :END
  )
)

rem 4) Detectar el Excel (autodetecta extension)
set "EXCEL_PATH="
for %%E in (xlsx xlsm xls) do (
  if exist "%EXCEL_BASE%.%%E" (
    set "EXCEL_PATH=%EXCEL_BASE%.%%E"
    goto :FoundExcel
  )
)
:FoundExcel

if not defined EXCEL_PATH (
  echo [x] No se encontro archivo Excel: %EXCEL_BASE%.xlsx (o .xlsm/.xls) en la raiz del repo.
  pause
  exit /b 1
)

rem 5) Ejecutar conversion Excel -> JSON
echo [*] Convirtiendo "%EXCEL_PATH%" a JSON con %SCRIPTS_DIR%\%PY_CONVERTER% ...
if not exist "%SCRIPTS_DIR%\%PY_CONVERTER%" (
  echo [x] No se encontro el script: %SCRIPTS_DIR%\%PY_CONVERTER%
  pause
  exit /b 1
)
"%PY_VENV%\Scripts\python.exe" "%SCRIPTS_DIR%\%PY_CONVERTER%"
if errorlevel 1 (
  echo [x] Error durante la conversion (Python). Revisa mensajes anteriores.
  pause
  exit /b 1
)

rem 6) cache-bust.txt (timestamp estable)
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%I"
if not defined TS (
  for /f "tokens=1-4 delims=/:. " %%a in ("%date% %time%") do set "TS=%%a-%%b-%%c_%%d"
)
> cache-bust.txt echo %TS%

rem 7) Commit + push (todo el repo segun opcion)
echo [*] Publicando cambios...
if "%PUSH_ALL%"=="1" (
  git add -A
) else (
  git add data.json cache-bust.txt "%EXCEL_PATH%" 2>NUL
)

set "HAVECHG="
for /f %%M in ('git status --porcelain') do (
  set "HAVECHG=1"
  goto :DoCommit
)
:DoCommit

if defined HAVECHG (
  git commit -m "auto: publish %TS%" >NUL
) else (
  echo (sin cambios para commitear)
)

rem Asegurar upstream en primer push
git rev-parse --abbrev-ref --symbolic-full-name @{u} >NUL 2>&1
if errorlevel 1 (
  git push -u origin %CURBR%
) else (
  git push origin %CURBR%
)
if errorlevel 1 (
  echo [x] Error al hacer push. Revisa credenciales o conflictos.
  goto :END
)

echo.
echo [OK] Proceso terminado. Si no ves cambios online, fuerza recarga (Ctrl+F5).
echo.

:END
pause
