@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

rem === Ir a la carpeta del script (raíz del repo) ===
cd /d "%~dp0"

rem === Verificar que estamos dentro de un repo git ===
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
  echo [x] Esta carpeta no es un repositorio Git. Abre el repo correcto.
  pause
  exit /b 1
)

rem === Branch actual (fallback a main si Git no responde) ===
for /f "tokens=*" %%b in ('git branch --show-current') do set BR=%%b
if "%BR%"=="" set "BR=main"

echo.
echo ==== Commit rapido de cambios ====
echo Branch actual: %BR%
echo.

rem === Verificar si hay cambios pendientes ===
git status --porcelain > "%TEMP%\_gs.txt"
for /f %%c in ('type "%TEMP%\_gs.txt" ^| find /c /v ""') do set COUNT=%%c

if "%COUNT%"=="0" (
  echo [i] No hay cambios que comitear.
  echo.
  goto askpushmaybe
)

rem === Pedir mensaje de commit ===
set /p MSG="Escribe el mensaje del commit (p.ej. 'Actualizo dashboard'): "
if "%MSG%"=="" set "MSG=actualizacion rapida"

rem === Add + commit ===
git add -A
git commit -m "%MSG%"
if errorlevel 1 (
  echo [!] No se pudo crear el commit (puede que no haya cambios nuevos).
  del "%TEMP%\_gs.txt" 2>nul
  echo.
  pause
  exit /b 1
)

:askpushmaybe
echo.
choice /m "¿Deseas subir (push) estos cambios a GitHub ahora?"
if errorlevel 2 (
  echo [i] Cambios guardados localmente. No se subieron.
  del "%TEMP%\_gs.txt" 2>nul
  echo.
  pause
  exit /b 0
)

rem === pull --rebase antes de push para evitar rechazos ===
git pull --rebase origin %BR%
if errorlevel 1 (
  echo [!] pull --rebase fallo. Resuelve conflictos y vuelve a ejecutar.
  del "%TEMP%\_gs.txt" 2>nul
  echo.
  pause
  exit /b 1
)

rem === push ===
git push origin %BR%
if errorlevel 1 (
  echo [x] No se pudo subir. Revisa mensajes arriba.
) else (
  echo [✓] Cambios subidos correctamente a origin/%BR%.
)

del "%TEMP%\_gs.txt" 2>nul
echo.
pause
