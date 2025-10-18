@echo off
setlocal

echo.
echo ==== Commit rápido de cambios de código ====
echo.

:: Preguntar el mensaje del commit
set /p MSG="Escribe el mensaje del commit (por ejemplo: 'Actualizo dashboard o alertas'): "

if "%MSG%"=="" (
  echo [x] No escribiste ningún mensaje. Cancelado.
  pause
  exit /b
)

:: Agrega todos los cambios y hace commit
git add .
git commit -m "%MSG%"
if errorlevel 1 (
  echo [!] No se detectaron cambios o ya están comiteados.
  pause
  exit /b
)

:: Opción: hacer push también automáticamente
choice /m "¿Deseas subir (push) estos cambios a GitHub ahora?"
if errorlevel 2 (
  echo [i] Cambios guardados localmente. No se subieron.
) else (
  git push origin main
  echo [✓] Cambios subidos correctamente.
)

echo.
pause
