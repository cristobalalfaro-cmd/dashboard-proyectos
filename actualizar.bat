@echo off
setlocal enabledelayedexpansion
REM =========================================================
REM  Dashboard: Actualización de datos  (Windows .BAT, seguro)
REM  - NO modifica ni commitea archivos de código (index.html, styles.css, etc.)
REM  - Solo publica: data.json y cache-bust.txt (y el Excel si cambió)
REM  - Primero trae cambios remotos (pull --rebase)
REM =========================================================

REM 0) Ir a la RAÍZ del repo (donde está este .bat)
cd /d "%~dp0"
if not exist ".git" (
  echo [x] No encuentro .git en esta carpeta. Asegúrate de ejecutar el .bat en la raiz del repo.
  pause
  exit /b 1
)

REM 1) Config
set "EXCEL=Template_Proyectos_Dashboard.xlsx"
set "JSON=data.json"
set "VENV=.venv"

echo.
echo ==== Dashboard: Actualizacion de datos (segura) ====
echo.

REM 2) Resolver Python (py o python)
set "PYBIN="
where py >nul 2>nul && set "PYBIN=py -3"
if not defined PYBIN (
  where python >nul 2>nul && set "PYBIN=python"
)
if not defined PYBIN (
  echo [x] No se encontro Python. Instala Python 3.10+ desde https://www.python.org/downloads/
  pause
  exit /b 1
)

REM 3) Crear venv si no existe
if not exist "%VENV%\Scripts\python.exe" (
  echo [*] Creando entorno virtual...
  %PYBIN% -m venv "%VENV%"
)

REM 4) Instalar dependencias minimas
echo [*] Instalando dependencias (pandas, openpyxl)...
"%VENV%\Scripts\python.exe" -m pip install -q --upgrade pip
"%VENV%\Scripts\python.exe" -m pip install -q pandas openpyxl

REM 5) Sincronizar PRIMERO con remoto (para no pisar cambios)
echo [*] Trayendo cambios remotos...
git fetch origin
REM Si no estamos en main, intentamos cambiar
for /f %%b in ('git branch --show-current') do set CUR=%%b
if /I not "%CUR%"=="main" (
  echo [i] Estabas en "%CUR%". Cambiando a "main" para publicar...
  git checkout main || (echo [x] No se pudo cambiar a main. Revisa ramas. & pause & exit /b 1)
)
git pull --rebase origin main || (
  echo [x] Hubo conflictos al hacer pull --rebase. Resuélvelos y vuelve a ejecutar.
  pause
  exit /b 1
)

REM 6) Ejecutar conversion Excel -> JSON (NO toca archivos de codigo)
echo [*] Convirtiendo "%EXCEL%" a "%JSON%"...
if not exist "scripts\convert_excel_to_json.py" (
  echo [x] Falta scripts\convert_excel_to_json.py
  echo     Asegurate de tener la estructura del repo correcta.
  pause
  exit /b 1
)
"%VENV%\Scripts\python.exe" scripts\convert_excel_to_json.py
if errorlevel 1 (
  echo [x] Error en la conversion. Revisa mensajes arriba.
  pause
  exit /b 1
)

REM 7) Actualizar cache-bust (fuerza refresco en GitHub Pages)
for /f "tokens=1-4 delims=/:. " %%a in ("%date% %time%") do set "TS=%%a-%%b-%%c_%%d"
> cache-bust.txt echo %TS%

REM 8) Preparar commit SOLO de generados
echo [*] Preparando commit solo con generados...
git add "%JSON%" cache-bust.txt 2>nul

REM Si el Excel cambió y quieres publicarlo, descomenta la línea siguiente:
REM git add "%EXCEL%" 2>nul

REM 9) ¿Hay algo en staging? (evita commits vacíos)
git diff --cached --quiet && (
  echo (i) No hay cambios nuevos en archivos generados. Nada que publicar.
  goto :PUSH
)

git commit -m "data: actualizar data.json y cache-bust (%date% %time%)"

:PUSH
REM 10) Push a main
echo [*] Enviando a GitHub...
git push origin main || (
  echo [x] No se pudo hacer push. Revisa credenciales o conflictos.
  pause
  exit /b 1
)

echo.
echo [✓] Listo. En ~30-60s deberías ver datos nuevos online.
echo     Sugerencia: Ctrl+F5 para forzar refresco del navegador.
echo.

REM 11) Comprobaciones útiles (no cambia nada)
echo [i] Comprobación rapida:
echo     - index.html / styles.css / scripts del dashboard NO se tocaron.
echo     - Solo se actualizaron: %JSON% y cache-bust.txt (y el Excel si lo agregaste).
echo.
pause
