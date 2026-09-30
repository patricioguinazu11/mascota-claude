# desinstalar.ps1 - Quita la mascota de Claude Code.
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\desinstalar.ps1
#
# Cierra la mascota, quita SOLO sus hooks de %USERPROFILE%\.claude\settings.json
# (deja copia de seguridad), borra el acceso directo de Inicio y la carpeta
# %LOCALAPPDATA%\ClaudeMascota.

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

$destino  = Join-Path $env:LOCALAPPDATA 'ClaudeMascota'
$acceso   = Join-Path ([Environment]::GetFolderPath('Startup')) 'Mascota Claude.lnk'
$settings = Join-Path $env:USERPROFILE '.claude\settings.json'

Write-Host ''
Write-Host '=== Desinstalando la mascota de Claude Code ===' -ForegroundColor Cyan

# 1. Cerrar la mascota
Write-Host '1/4 Cerrando la mascota'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*ClaudeMascota*mascota.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2. Quitar hooks (usa el script del repo o el copiado en la instalación)
Write-Host '2/4 Quitando hooks de settings.json'
$config = Join-Path $PSScriptRoot 'src\configurar-hooks.ps1'
if (-not (Test-Path $config)) { $config = Join-Path $PSScriptRoot 'configurar-hooks.ps1' }
if (-not (Test-Path $config)) { $config = Join-Path $destino 'configurar-hooks.ps1' }
if (Test-Path $config) {
    # Se copia a TEMP para poder borrar la carpeta de instalación sin problemas.
    $tmp = Join-Path $env:TEMP 'configurar-hooks-mascota.ps1'
    Copy-Item -LiteralPath $config -Destination $tmp -Force
    & $tmp -Accion Quitar -Settings $settings
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
} else {
    Write-Warning "No encontré configurar-hooks.ps1; revisá a mano $settings"
}

# 3. Acceso directo de Inicio
Write-Host '3/4 Quitando el arranque automático'
if (Test-Path -LiteralPath $acceso) { Remove-Item -LiteralPath $acceso -Force }

# 4. Archivos
Write-Host "4/4 Borrando $destino"
Start-Sleep -Milliseconds 500
if (Test-Path -LiteralPath $destino) {
    Remove-Item -LiteralPath $destino -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $destino) { Write-Warning "No pude borrar todo $destino; podés borrarlo a mano." }
}

Write-Host ''
Write-Host 'Mascota desinstalada. Reiniciá Claude Code para que deje de usar los hooks.' -ForegroundColor Green
Write-Host ''
