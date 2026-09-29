@echo off
rem Doble clic para ejecutar instalar.ps1 sin cambiar la politica de ejecucion de Windows.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar.ps1"
echo.
pause
