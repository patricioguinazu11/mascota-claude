@echo off
rem Doble clic para revisar por que la mascota no cambia de estado.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnosticar.ps1"
echo.
pause
