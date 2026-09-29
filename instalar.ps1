# instalar.ps1 - Instala la mascota de Claude Code en Windows.
# Uso (desde la carpeta del repo):
#   powershell -ExecutionPolicy Bypass -File .\instalar.ps1
#
# Qué hace:
#   1. Copia los archivos a %LOCALAPPDATA%\ClaudeMascota
#   2. Agrega los hooks en %USERPROFILE%\.claude\settings.json (sin borrar lo que ya hay; deja copia)
#   3. Crea un acceso directo en la carpeta Inicio para que arranque con Windows
#   4. Abre la mascota

$ErrorActionPreference = 'Stop'

# Siempre con Windows PowerShell 5.1 (el que trae Windows), aunque lo lances desde pwsh 7.
if ($PSVersionTable.PSEdition -eq 'Core') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

$origen   = Join-Path $PSScriptRoot 'src'
$destino  = Join-Path $env:LOCALAPPDATA 'ClaudeMascota'
$inicio   = [Environment]::GetFolderPath('Startup')
$acceso   = Join-Path $inicio 'Mascota Claude.lnk'
$settings = Join-Path $env:USERPROFILE '.claude\settings.json'

Write-Host ''
Write-Host '=== Instalando la mascota de Claude Code ===' -ForegroundColor Cyan

if (-not (Test-Path (Join-Path $origen 'mascota.ps1'))) {
    throw "No encuentro la carpeta 'src' al lado de instalar.ps1. Ejecutalo desde la carpeta del repositorio."
}

# 1. Cerrar una mascota que ya esté corriendo (reinstalación)
$corriendo = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*ClaudeMascota*mascota.ps1*' }
foreach ($p in $corriendo) {
    Write-Host '  Cerrando la mascota que estaba abierta...'
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}
if ($corriendo) { Start-Sleep -Milliseconds 500 }

# 2. Copiar archivos
Write-Host "1/4 Copiando archivos a $destino"
New-Item -ItemType Directory -Path $destino -Force | Out-Null
foreach ($f in 'mascota.ps1', 'hook.ps1', 'configurar-hooks.ps1') {
    Copy-Item -LiteralPath (Join-Path $origen $f) -Destination $destino -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'desinstalar.ps1') -Destination $destino -Force
Get-ChildItem -LiteralPath $destino -Filter *.ps1 | Unblock-File

# 3. Hooks en settings.json
Write-Host "2/4 Configurando hooks en $settings"
$rutaHook = (Join-Path $destino 'hook.ps1') -replace '\\', '/'
$comando = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$rutaHook`""
& (Join-Path $destino 'configurar-hooks.ps1') -Accion Agregar -Comando $comando -Settings $settings

# 4. Arranque automático con Windows
Write-Host '3/4 Creando acceso directo en Inicio (arranca sola con Windows)'
$argumentos = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $destino 'mascota.ps1')`""
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($acceso)
$lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$lnk.Arguments = $argumentos
$lnk.WorkingDirectory = $destino
$lnk.WindowStyle = 7   # minimizada: evita que se vea la consola al arrancar
$lnk.Description = 'Mascota de Claude Code'
$lnk.Save()

# 5. Abrirla ahora
Write-Host '4/4 Abriendo la mascota'
Start-Process -FilePath $lnk.TargetPath -ArgumentList $argumentos -WindowStyle Hidden -WorkingDirectory $destino

Write-Host ''
Write-Host 'Listo. La mascota ya debería estar en la esquina inferior derecha.' -ForegroundColor Green
Write-Host 'Si tenías Claude Code abierto, cerralo y volvelo a abrir para que tome los hooks.'
Write-Host 'Arrastrala con el mouse; clic derecho para silenciarla o cerrarla.'
Write-Host ''
