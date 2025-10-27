@echo off
setlocal

rem =================== CONFIG ===================
set "BRANCH=main"
set "SCRIPTS_DIR=scripts"
set "PY_CONVERTER=convert_excel_to_json.py"
set "LOG_DIR=logs"
set "TMP_DIR=%TEMP%\upd_dash_%RANDOM%"
set "PUSH_ALL=1"   rem 1 = add -A (todo el repo); 0 = solo data.json + cache-bust + Excel
rem =================================================

rem --- preparar carpetas temporales / logs ---
mkdir "%TMP_DIR%" >NUL 2>&1
mkdir "%LOG_DIR%" >NUL 2>&1
set "LAST_LOG=%LOG_DIR%\last-run.log"
set "HIST_LOG=%LOG_DIR%\history.log"
> "%LAST_LOG%" echo ==== RUN %DATE% %TIME% ====
>>"%HIST_LOG%" echo ==== RUN %DATE% %TIME% ====

rem helper para loguear y mostrar
set "ECHOLOG=call :_log"

rem 0) ir a la raiz del repo
cd /d "%~dp0"

rem seguridad: debe ser repo git
git rev-parse --is-inside-work-tree >NUL 2>&1 || (
  %ECHOLOG% [x] Esta carpeta no es un repositorio Git.
  goto :END
)

%ECHOLOG% ==== Dashboard: Actualizacion de datos ====

rem 1) Python (py -3 o python)
set "PYBIN="
where py >NUL 2>&1 && set "PYBIN=py -3"
if not defined PYBIN where python >NUL 2>&1 && set "PYBIN=python"
if not defined PYBIN (
  %ECHOLOG% [x] Python 3 no encontrado. Instala desde https://www.python.org/downloads/
  goto :END
)
for /f "tokens=*" %%V in ('%PYBIN% --version 2^>^&1') do set "PYVER=%%V"
%ECHOLOG% [*] Python: %PYVER%

rem 2) deps: pandas + openpyxl (instalar si faltan)
%ECHOLOG% [*] Verificando dependencias de Python...
%PYBIN% - <<PYEND > "%TMP_DIR%\chk.txt" 2>&1
import importlib, sys
mods = ["pandas", "openpyxl"]
missing = [m for m in mods if importlib.util.find_spec(m) is None]
print("MISSING:" + ",".join(missing))
PYEND

set "MISSING="
for /f "tokens=2 delims=:" %%A in ('type "%TMP_DIR%\chk.txt" ^| find "MISSING:"') do set "MISSING=%%A"

if defined MISSING if not "%MISSING%"=="" (
  %ECHOLOG% [*] Instalando: %MISSING%
  %PYBIN% -m pip -q --disable-pip-version-check install --upgrade pip
  %PYBIN% -m pip -q --disable-pip-version-check install %MISSING%
) else (
  %ECHOLOG% [✓] Dependencias OK.
)

rem 3) Git: stash → pull --rebase → pop
%ECHOLOG% [*] Sincronizando con remoto...
git status --porcelain > "%TMP_DIR%\changes.txt"
set "CHANGES="
set /p CHANGES=<"%TMP_DIR%\changes.txt"
if defined CHANGES (
  %ECHOLOG% [i] Cambios locales detectados. Guardando en stash temporal...
  git stash push -u -m "auto-stash antes de actualizar" >NUL
  set "HAD_STASH=1"
) else (
  %ECHOLOG% [i] Sin cambios locales antes de actualizar.
)

git fetch origin
git pull --rebase origin %BRANCH%
if errorlevel 1 (
  %ECHOLOG% [x] Conflicto al hacer pull --rebase. Ejecuta: git status ^&^& git add . ^&^& git rebase --continue
  goto :END
)

if defined HAD_STASH (
  %ECHOLOG% [*] Reaplicando cambios locales del stash...
  git stash pop
  if errorlevel 1 (
    %ECHOLOG% [!] Conflictos al aplicar el stash. Revisa "git status", resuelve y reintenta.
    goto :END
  )
)

rem 4) Ejecutar convertidor Excel -> JSON
if not exist "%SCRIPTS_DIR%\%PY_CONVERTER%" (
  %ECHOLOG% [x] Falta el script %SCRIPTS_DIR%\%PY_CONVERTER%
  goto :END
)
%ECHOLOG% [*] Ejecutando convertidor...
%PYBIN% "%SCRIPTS_DIR%\%PY_CONVERTER%" > "%TMP_DIR%\conv.txt" 2>&1
if errorlevel 1 (
  type "%TMP_DIR%\conv.txt" >> "%LAST_LOG%"
  type "%TMP_DIR%\conv.txt" >> "%HIST_LOG%"
  %ECHOLOG% [x] Conversion fallida (revisa logs).
  goto :END
) else (
  type "%TMP_DIR%\conv.txt" >> "%LAST_LOG%"
  type "%TMP_DIR%\conv.txt" >> "%HIST_LOG%"
)

rem 5) cache-bust
%ECHOLOG% [*] Actualizando cache-bust.txt...
> cache-bust.txt echo %DATE% %TIME%

rem 6) Commit + push
%ECHOLOG% [*] Publicando cambios...
if "%PUSH_ALL%"=="1" (
  git add -A
) else (
  git add data.json cache-bust.txt *.xls *.xlsx *.xlsm 2>NUL
)

rem ¿hay algo staged?
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "auto: publish %DATE% %TIME%" >NUL
  rem asegurar upstream y push
  git rev-parse --abbrev-ref --symbolic-full-name @{u} >NUL 2>&1
  if errorlevel 1 ( git push -u origin %BRANCH% ) else ( git push origin %BRANCH% )
  if errorlevel 1 (
    %ECHOLOG% [x] Error al hacer push (credenciales o permisos).
    goto :END
  )
) else (
  %ECHOLOG% (sin cambios para commitear)
)

rem 7) Pull final para quedar alineado con remoto
git fetch origin
git pull --rebase origin %BRANCH% >NUL

%ECHOLOG% [OK] Dashboard actualizado y sincronizado.
goto :END

:_log
echo %* 
>> "%LAST_LOG%" echo %*
>> "%HIST_LOG%" echo %*
exit /b 0

:END
rem limpieza
rd /s /q "%TMP_DIR%" >NUL 2>&1
echo.
pause
