# configurar-hooks.ps1 - Agrega o quita los hooks de la mascota en el settings.json
# de usuario de Claude Code, SIN tocar el resto de la configuración.
#
#   -Accion Agregar -Comando "<comando del hook>"   (se le agrega el nombre del evento al final)
#   -Accion Quitar
#
# Solo se consideran "de la mascota" los hooks cuyo comando apunta a ClaudeMascota\hook.ps1.
# Antes de escribir se guarda una copia: settings.json.bak-mascota-AAAAMMDD-HHMMSS

param(
    [Parameter(Mandatory = $true)][ValidateSet('Agregar', 'Quitar')][string]$Accion,
    [string]$Comando,
    [string]$Settings = (Join-Path $env:USERPROFILE '.claude\settings.json')
)

$ErrorActionPreference = 'Stop'
$marca = 'ClaudeMascota[\\/]+hook\.ps1'
$eventos = [ordered]@{
    # evento           = usa matcher de herramienta
    UserPromptSubmit = $false
    PreToolUse       = $true
    PostToolUse      = $true
    Notification     = $false
    Stop             = $false
    SessionEnd       = $false
}

# En Windows PowerShell 5.1 esto evita que los arrays se serialicen raro.
if (Get-TypeData -TypeName System.Array) { Remove-TypeData -TypeName System.Array }

function ConvertTo-Nativo($o) {
    if ($null -eq $o) { return $null }
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-Nativo $p.Value }
        return $h
    }
    if ($o -is [System.Collections.IList]) {
        $l = New-Object System.Collections.ArrayList
        foreach ($i in $o) { [void]$l.Add((ConvertTo-Nativo $i)) }
        return , $l
    }
    return $o
}

function Texto-Json([string]$t) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $t.ToCharArray()) {
        switch ($ch) {
            '"'  { [void]$sb.Append('\"') }
            '\'  { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            "`b" { [void]$sb.Append('\b') }
            "`f" { [void]$sb.Append('\f') }
            default {
                if ([int]$ch -lt 0x20) { [void]$sb.AppendFormat('\u{0:x4}', [int]$ch) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    $sb.ToString()
}

function Escribir-Json($v, [int]$nivel) {
    $ind = '  ' * $nivel
    $ind2 = '  ' * ($nivel + 1)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($null -eq $v) { return 'null' }
    if ($v -is [string]) { return Texto-Json $v }
    if ($v -is [bool]) { return $(if ($v) { 'true' } else { 'false' }) }
    if ($v -is [datetime]) { return Texto-Json $v.ToString('o') }
    if ($v -is [System.Collections.IDictionary]) {
        if ($v.Count -eq 0) { return '{}' }
        $partes = foreach ($k in $v.Keys) { $ind2 + (Texto-Json ([string]$k)) + ': ' + (Escribir-Json $v[$k] ($nivel + 1)) }
        return "{`n" + (@($partes) -join ",`n") + "`n$ind}"
    }
    if ($v -is [System.Collections.IList]) {
        if ($v.Count -eq 0) { return '[]' }
        $partes = foreach ($i in $v) { $ind2 + (Escribir-Json $i ($nivel + 1)) }
        return "[`n" + (@($partes) -join ",`n") + "`n$ind]"
    }
    if ($v -is [double] -or $v -is [single]) { return $v.ToString('R', $inv) }
    if ($v -is [ValueType]) { return [Convert]::ToString($v, $inv) }
    return Texto-Json ([string]$v)
}

function Quitar-Nuestros($cfg) {
    if (-not $cfg.Contains('hooks') -or -not ($cfg['hooks'] -is [System.Collections.IDictionary])) { return 0 }
    $hooks = $cfg['hooks']
    $quitados = 0
    foreach ($ev in @($hooks.Keys)) {
        $grupos = $hooks[$ev]
        if (-not ($grupos -is [System.Collections.IList])) { continue }
        $nuevosGrupos = New-Object System.Collections.ArrayList
        foreach ($grupo in $grupos) {
            if (-not ($grupo -is [System.Collections.IDictionary]) -or -not ($grupo['hooks'] -is [System.Collections.IList])) {
                [void]$nuevosGrupos.Add($grupo); continue
            }
            $lista = New-Object System.Collections.ArrayList
            foreach ($h in $grupo['hooks']) {
                if ($h -is [System.Collections.IDictionary] -and ([string]$h['command']) -match $marca) { $quitados++ }
                else { [void]$lista.Add($h) }
            }
            if ($lista.Count -gt 0 -or $grupo['hooks'].Count -eq 0) {
                $grupo['hooks'] = $lista
                [void]$nuevosGrupos.Add($grupo)
            }
        }
        if ($nuevosGrupos.Count -gt 0) { $hooks[$ev] = $nuevosGrupos } else { $hooks.Remove($ev) }
    }
    if ($hooks.Count -eq 0) { $cfg.Remove('hooks') }
    return $quitados
}

# --- Leer settings.json -----------------------------------------------------------
$texto = ''
if (Test-Path -LiteralPath $Settings) {
    $texto = [IO.File]::ReadAllText($Settings, [Text.Encoding]::UTF8)
} elseif ($Accion -eq 'Quitar') {
    Write-Host "  No existe $Settings, no hay nada que quitar."
    return
}

if ($texto.Trim()) {
    try { $obj = $texto | ConvertFrom-Json }
    catch { throw "No pude leer $Settings (JSON inválido). No se modificó nada. Detalle: $_" }
    if (-not ($obj -is [System.Management.Automation.PSCustomObject])) {
        throw "$Settings no contiene un objeto JSON. No se modificó nada."
    }
    $cfg = ConvertTo-Nativo $obj
} else {
    $cfg = [ordered]@{}
}

# --- Modificar --------------------------------------------------------------------
$quitados = Quitar-Nuestros $cfg

if ($Accion -eq 'Agregar') {
    if (-not $Comando) { throw 'Falta -Comando.' }
    if (-not $cfg.Contains('hooks') -or -not ($cfg['hooks'] -is [System.Collections.IDictionary])) { $cfg['hooks'] = [ordered]@{} }
    $hooks = $cfg['hooks']
    foreach ($ev in $eventos.Keys) {
        $entrada = [ordered]@{ type = 'command'; command = "$Comando $ev"; async = $true }
        $grupo = [ordered]@{}
        if ($eventos[$ev]) { $grupo['matcher'] = '*' }
        $grupo['hooks'] = New-Object System.Collections.ArrayList
        [void]$grupo['hooks'].Add($entrada)
        if (-not ($hooks[$ev] -is [System.Collections.IList])) { $hooks[$ev] = New-Object System.Collections.ArrayList }
        [void]$hooks[$ev].Add($grupo)
    }
} elseif ($quitados -eq 0) {
    Write-Host '  No había hooks de la mascota en settings.json.'
    return
}

# --- Guardar (con copia de seguridad) ---------------------------------------------
$dir = Split-Path -Parent $Settings
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
if (Test-Path -LiteralPath $Settings) {
    $backup = "$Settings.bak-mascota-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $Settings -Destination $backup -Force
    Write-Host "  Copia de seguridad: $backup"
}
$salida = (Escribir-Json $cfg 0) + "`n"
# Verificación: lo que escribimos tiene que ser JSON válido.
$null = $salida | ConvertFrom-Json
[IO.File]::WriteAllText($Settings, $salida, (New-Object Text.UTF8Encoding($false)))

if ($Accion -eq 'Agregar') { Write-Host "  Hooks configurados en $Settings" }
else { Write-Host "  Se quitaron $quitados hooks de la mascota de $Settings" }
