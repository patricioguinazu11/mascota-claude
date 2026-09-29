@echo off
rem Doble clic para ejecutar desinstalar.ps1 sin cambiar la politica de ejecucion de Windows.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0desinstalar.ps1"
echo.
pause
