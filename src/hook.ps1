# hook.ps1 - Lo ejecuta Claude Code en cada evento (UserPromptSubmit, PreToolUse,
# PostToolUse, Notification, Stop). Lee el JSON que llega por stdin, decide en qué
# estado tiene que estar la mascota y lo escribe en estado.json.
# Nunca debe fallar ni imprimir nada: cualquier error se ignora y sale con 0.

param([string]$Evento = '')

# Marca de tiempo tomada lo antes posible: los hooks corren en segundo plano y
# pueden terminar desordenados; con esto el más nuevo siempre gana.
$ts = [DateTime]::UtcNow.Ticks

function Acortar([string]$s, [int]$max) {
    if (-not $s) { return '' }
    $s = ($s -replace '\s+', ' ').Trim()
    if ($s.Length -gt $max) { $s = $s.Substring(0, $max - 1) + [char]0x2026 }
    return $s
}

function NombreArchivo($ti) {
    foreach ($k in 'file_path', 'notebook_path', 'path') {
        $v = $ti.$k
        if ($v) { return Acortar (([string]$v).TrimEnd('\', '/') -split '[\\/]')[-1] 22 }
    }
    return ''
}

try {
    # Por defecto, la carpeta donde está este script (%LOCALAPPDATA%\ClaudeMascota).
    $dir = $PSScriptRoot
    if ($env:CLAUDE_MASCOTA_DIR) { $dir = $env:CLAUDE_MASCOTA_DIR }
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $archivo = Join-Path $dir 'estado.json'

    $reader = New-Object IO.StreamReader([Console]::OpenStandardInput(), (New-Object Text.UTF8Encoding($false)))
    $raw = $reader.ReadToEnd()
    $d = $null
    try { if ($raw) { $d = $raw | ConvertFrom-Json } } catch { $d = $null }

    if ($d -and $d.hook_event_name) { $Evento = [string]$d.hook_event_name }
    elseif (-not $Evento -and $raw -match '"hook_event_name"\s*:\s*"([^"]+)"') { $Evento = $Matches[1] }

    $herramienta = ''
    if ($d) { $herramienta = [string]$d.tool_name }
    elseif ($raw -match '"tool_name"\s*:\s*"([^"]+)"') { $herramienta = $Matches[1] }

    $estado = 'trabajando'
    $texto = 'Pensando' + [char]0x2026
    $e = [char]0x2026

    switch ($Evento) {
        'UserPromptSubmit' { $estado = 'trabajando'; $texto = "Pensando$e" }
        'PostToolUse'      { $estado = 'trabajando'; $texto = "Pensando$e" }
        'PreToolUse' {
            $ti = if ($d) { $d.tool_input } else { $null }
            $arch = NombreArchivo $ti
            $estado = 'trabajando'
            switch -Regex ($herramienta) {
                '^(Edit|MultiEdit|NotebookEdit)$' { $texto = if ($arch) { "Editando $arch$e" } else { "Editando archivo$e" } }
                '^Write$'           { $texto = if ($arch) { "Escribiendo $arch$e" } else { "Escribiendo archivo$e" } }
                '^Read$'            { $texto = if ($arch) { "Leyendo $arch$e" } else { "Leyendo archivo$e" } }
                '^(Bash|PowerShell)$' {
                    $desc = if ($ti) { [string]$ti.description } else { '' }
                    $texto = if ($desc) { Acortar $desc 34 } else { "Ejecutando comando$e" }
                }
                '^(Grep|Glob|LS)$'  { $texto = "Buscando en el c$([char]0xF3)digo$e" }
                '^WebSearch$'       { $texto = "Buscando en internet$e" }
                '^WebFetch$'        { $texto = "Leyendo una p$([char]0xE1)gina web$e" }
                '^(Task|Agent)$'    { $texto = "Delegando a un ayudante$e" }
                '^(TodoWrite|TaskCreate|TaskUpdate)$' { $texto = "Organizando tareas$e" }
                '^AskUserQuestion$' { $estado = 'aprobacion'; $texto = 'Tengo una pregunta' }
                '^ExitPlanMode$'    { $estado = 'aprobacion'; $texto = "Revis$([char]0xE1) mi plan" }
                '^mcp__'            { $texto = "Usando " + (Acortar (($herramienta -split '__')[1]) 20) + $e }
                default             { $texto = if ($herramienta) { "Usando " + (Acortar $herramienta 20) + $e } else { "Trabajando$e" } }
            }
        }
        'Notification' {
            $tipo = if ($d) { [string]$d.notification_type } else { '' }
            $msg = if ($d) { [string]$d.message } else { '' }
            if ($tipo -eq 'permission_prompt' -or (-not $tipo -and $msg -match 'permission|permiso')) {
                $estado = 'aprobacion'
                $texto = 'Necesito tu permiso'
                if ($msg -match 'to use (\S+)') { $texto = "$([char]0xBF)Me dej$([char]0xE1)s usar " + (Acortar $Matches[1] 16) + '?' }
            } elseif ($tipo -eq 'idle_prompt' -or $msg -match 'waiting for your input') {
                $estado = 'esperando'; $texto = "Te espero$e"
            } elseif ($tipo -match '^elicitation_(dialog|url_dialog)$|^agent_needs_input$') {
                $estado = 'aprobacion'; $texto = 'Necesito tu respuesta'
            } else {
                # Otros avisos (auth_success, etc.): no cambian el estado.
                exit 0
            }
        }
        'Stop'      { $estado = 'listo'; $texto = "$([char]0xA1)Termin$([char]0xE9)!" }
        'SessionEnd' { $estado = 'esperando'; $texto = "Hasta luego$e" }
        default { exit 0 }
    }

    $proyecto = ''
    if ($d -and $d.cwd) { $proyecto = Acortar (([string]$d.cwd).TrimEnd('\', '/') -split '[\\/]')[-1] 24 }

    # Si ya hay un estado más nuevo escrito por otro hook, no lo pisamos.
    if (Test-Path $archivo) {
        try {
            $previo = [IO.File]::ReadAllText($archivo) | ConvertFrom-Json
            if ($previo.ts -and [long]$previo.ts -gt $ts) { exit 0 }
        } catch { }
    }

    $json = [ordered]@{
        estado   = $estado
        texto    = $texto
        evento   = $Evento
        proyecto = $proyecto
        ts       = $ts
    } | ConvertTo-Json -Compress

    # Escritura atómica: archivo temporal + reemplazo.
    $tmp = "$archivo.$PID.tmp"
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $archivo -Force
} catch {
    try { if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Force } } catch { }
}
exit 0
