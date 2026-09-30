# diagnosticar.ps1 - Revisa por qué la mascota no cambia de estado.
# Uso: doble clic en diagnosticar.bat (o powershell -ExecutionPolicy Bypass -File .\diagnosticar.ps1)
# Al final, copiá todo lo que muestra y mandáselo a Claude.

$ErrorActionPreference = 'Continue'
if ($PSVersionTable.PSEdition -eq 'Core') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

# Todo lo que se muestra queda guardado en un archivo que se abre al final en el Bloc de notas.
$reporte = Join-Path $env:TEMP 'diagnostico-mascota.txt'
try { Start-Transcript -LiteralPath $reporte -Force | Out-Null } catch { $reporte = $null }

$destino  = Join-Path $env:LOCALAPPDATA 'ClaudeMascota'
$settings = Join-Path $env:USERPROFILE '.claude\settings.json'
$estado   = Join-Path $destino 'estado.json'
$marca    = 'ClaudeMascota[\\/]+hook\.ps1'

function Ok($m)    { Write-Host "  [OK]  $m" -ForegroundColor Green }
function Mal($m)   { Write-Host "  [!!]  $m" -ForegroundColor Red }
function Info($m)  { Write-Host "        $m" }
function Titulo($m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }

Write-Host '=== Diagnóstico de la mascota de Claude Code ===' -ForegroundColor Cyan
Info ("Windows {0} | PowerShell {1} | {2:yyyy-MM-dd HH:mm:ss}" -f [Environment]::OSVersion.Version, $PSVersionTable.PSVersion, (Get-Date))

Titulo '1. Instalación'
foreach ($f in 'mascota.ps1', 'hook.ps1', 'configurar-hooks.ps1') {
    if (Test-Path (Join-Path $destino $f)) { Ok "$f instalado" } else { Mal "Falta $destino\$f (volvé a ejecutar instalar.bat)" }
}
$viva = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -like '*ClaudeMascota*mascota.ps1*' }
if ($viva) { Ok "Mascota abierta (proceso $($viva[0].ProcessId))" } else { Mal 'La mascota no está abierta' }

Titulo '2. Claude Code'
$claude = Get-Command claude -ErrorAction SilentlyContinue
if ($claude) {
    $ver = & $claude.Source --version 2>&1 | Select-Object -First 1
    Ok "claude encontrado: $($claude.Source)"
    Info "Versión: $ver"
} else {
    Info 'No encontré el comando "claude" en el PATH (si usás la app de escritorio o VS Code puede ser normal).'
}
if ($env:CLAUDE_CONFIG_DIR) { Mal "CLAUDE_CONFIG_DIR = $env:CLAUDE_CONFIG_DIR : Claude Code usa OTRO settings.json, no $settings" }
$procs = Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(claude|node)\.exe$' -and $_.CommandLine -match 'claude' }
if ($procs) {
    foreach ($p in $procs) {
        $inicio = $p.CreationDate
        Info ("Proceso Claude abierto desde {0:HH:mm:ss}: {1}" -f $inicio, $p.Name)
    }
    $inst = (Get-Item (Join-Path $destino 'hook.ps1') -ErrorAction SilentlyContinue).LastWriteTime
    if ($inst -and ($procs | Where-Object { $_.CreationDate -lt $inst })) {
        Mal 'Hay una sesión de Claude Code abierta ANTES de instalar: cerrala y abrila de nuevo.'
    }
}

Titulo '3. Hooks en settings.json'
$comandos = @{}
if (-not (Test-Path $settings)) {
    Mal "No existe $settings"
} else {
    try {
        $cfg = [IO.File]::ReadAllText($settings, [Text.Encoding]::UTF8) | ConvertFrom-Json
        Ok 'settings.json es JSON válido'
        foreach ($ev in 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Notification', 'Stop', 'SessionEnd') {
            $cmd = $null
            foreach ($grupo in @($cfg.hooks.$ev)) {
                foreach ($h in @($grupo.hooks)) { if ([string]$h.command -match $marca) { $cmd = [string]$h.command } }
            }
            if ($cmd) { Ok "$ev configurado"; $comandos[$ev] = $cmd } else { Mal "$ev NO tiene el hook de la mascota" }
        }
        if ($cfg.disableAllHooks) { Mal 'settings.json tiene "disableAllHooks": true, así que ningún hook corre' }
        if ($comandos['PreToolUse']) { Info "Comando: $($comandos['PreToolUse'])" }
    } catch {
        Mal "settings.json tiene un error de formato: $_"
    }
}
foreach ($otro in (Join-Path $env:USERPROFILE '.claude\settings.local.json')) {
    if (Test-Path $otro) {
        $t = Get-Content $otro -Raw
        if ($t -match '"disableAllHooks"\s*:\s*true') { Mal "$otro desactiva todos los hooks" }
    }
}

Titulo '4. Simulación de un aviso de Claude Code'
function Probar-Hook([string]$exe, [string[]]$argumentos, [string]$nombre) {
    $prueba = 'diag-' + (Get-Random -Maximum 99999) + '.txt'
    $json = '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"C:\\\\' + $prueba + '"}}'
    $antes = if (Test-Path $estado) { (Get-Item $estado).LastWriteTimeUtc } else { [DateTime]::MinValue }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.Arguments = ($argumentos -join ' ')
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.Write($json)
        $p.StandardInput.Close()
        $salida = $p.StandardOutput.ReadToEndAsync()
        $errores = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(20000)) { Mal "$nombre : el hook no terminó en 20 segundos"; try { $p.Kill() } catch { }; return }
        $txt = if (Test-Path $estado) { Get-Content $estado -Raw -Encoding UTF8 } else { '' }
        if ($txt -match [regex]::Escape($prueba)) {
            Ok "$nombre : el hook funcionó y la mascota debería decir 'Leyendo $prueba'"
        } else {
            Mal "$nombre : el hook NO actualizó estado.json (código de salida $($p.ExitCode))"
            if ($salida.Result) { Info "Salida: $($salida.Result.Trim())" }
            if ($errores.Result) { Info "Errores: $($errores.Result.Trim())" }
        }
    } catch {
        Mal "$nombre : no pude ejecutarlo: $_"
    }
}

$cmd = $comandos['PreToolUse']
if (-not $cmd) {
    Mal 'No hay comando de hook para probar.'
} else {
    # Claude Code en Windows ejecuta los hooks con Git Bash (o con PowerShell si no hay Git Bash).
    $bash = $null
    foreach ($c in @($env:CLAUDE_CODE_GIT_BASH_PATH, "$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
        if ($c -and (Test-Path $c)) { $bash = $c; break }
    }
    if ($bash) {
        Info "Git Bash: $bash"
        $escapado = $cmd.Replace('\', '\\').Replace('"', '\"')
        Probar-Hook $bash @('-c', "`"$escapado`"") 'Vía Git Bash (como Claude Code)'
    } else {
        Info 'No encontré Git Bash: Claude Code usaría PowerShell para los hooks.'
    }
    $hookPs = Join-Path $destino 'hook.ps1'
    Probar-Hook 'powershell.exe' @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$hookPs`"", 'PreToolUse') 'Hook directo con PowerShell'
}

Titulo '5. Estado actual y registro del hook'
if (Test-Path $estado) {
    Info ("estado.json ({0:HH:mm:ss}): {1}" -f (Get-Item $estado).LastWriteTime, (Get-Content $estado -Raw -Encoding UTF8))
} else { Mal 'No existe estado.json: ningún hook llegó a escribir nunca.' }
$log = Join-Path $destino 'hook.log'
if (Test-Path $log) {
    Info 'Últimas llamadas al hook (hook.log):'
    Get-Content $log -Tail 15 -Encoding UTF8 | ForEach-Object { Info "  $_" }
} else { Info 'No hay hook.log todavía (el hook nunca fue llamado desde que se agregó el registro).' }
$logM = Join-Path $destino 'mascota.log'
if (Test-Path $logM) {
    Info 'Últimas líneas de mascota.log:'
    Get-Content $logM -Tail 5 -Encoding UTF8 | ForEach-Object { Info "  $_" }
}

Write-Host ''
Write-Host 'Listo. Se abre el Bloc de notas con este resultado: Ctrl+A, Ctrl+C y pegáselo a Claude.' -ForegroundColor Cyan
if ($reporte) {
    try { Stop-Transcript | Out-Null } catch { }
    Start-Process notepad.exe -ArgumentList "`"$reporte`""
}
