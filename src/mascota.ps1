# mascota.ps1 - Mascota de escritorio que muestra qué está haciendo Claude Code.
# Solo usa Windows PowerShell 5.1 + .NET Framework (WinForms/GDI+), que ya vienen con Windows.
#
# Lee estado.json (lo escribe hook.ps1 desde los hooks de Claude Code) y anima un
# personaje pixel-art con 4 estados: esperando, trabajando, aprobacion y listo.
# Arrastrala con el botón izquierdo; clic derecho para el menú (sonido / cerrar).

$ErrorActionPreference = 'Stop'

$carpeta       = $PSScriptRoot
$archivoEstado = Join-Path $carpeta 'estado.json'
$archivoConfig = Join-Path $carpeta 'config.json'
$archivoLog    = Join-Path $carpeta 'mascota.log'

function Log([string]$msg) {
    try { Add-Content -LiteralPath $archivoLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) -Encoding UTF8 } catch { }
}

# --- Una sola instancia -----------------------------------------------------------
$nueva = $false
$script:mutex = New-Object System.Threading.Mutex($true, 'Local\ClaudeMascota', [ref]$nueva)
if (-not $nueva) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# Ventana propia: doble buffer, no roba el foco y no aparece en Alt+Tab.
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class MascotaNativo {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}

public class MascotaForm : Form {
    public MascotaForm() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            return cp;
        }
    }
}
'@

[void][MascotaNativo]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Escala según DPI -------------------------------------------------------------
$gTmp = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$s = [Math]::Max(1.0, $gTmp.DpiX / 96.0)
$gTmp.Dispose()

$W = [int](240 * $s)          # ancho de la ventana
$H = [int](115 * $s)          # alto de la ventana
$u = [int][Math]::Max(3, [Math]::Round(5 * $s))   # tamaño de un "pixel" del personaje

# --- Colores ----------------------------------------------------------------------
function Pincel([string]$hex) { New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($hex)) }
$colorClave  = [System.Drawing.Color]::FromArgb(255, 255, 0, 254)   # se vuelve transparente
$bNaranja    = Pincel '#D97757'
$bNaranjaCl  = Pincel '#F2A477'
$bNaranjaOsc = Pincel '#B95F42'
$bOjos       = Pincel '#2B2B2B'
$bRojo       = Pincel '#E5443A'
$bVerde      = Pincel '#3DBB5B'
$bAmarillo   = Pincel '#FFC933'
$bGris       = Pincel '#9A9A9A'
$bBlanco     = Pincel '#FFFFFF'
$bBorde      = Pincel '#2B2B2B'
$bTexto      = Pincel '#2B2B2B'

$fuente = New-Object System.Drawing.Font('Segoe UI', [single](12 * $s), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$formatoTexto = New-Object System.Drawing.StringFormat
$formatoTexto.Alignment     = [System.Drawing.StringAlignment]::Center
$formatoTexto.LineAlignment = [System.Drawing.StringAlignment]::Center
$formatoTexto.Trimming      = [System.Drawing.StringTrimming]::EllipsisCharacter
$formatoTexto.FormatFlags   = [System.Drawing.StringFormatFlags]::NoWrap

# --- Sonido corto (generado en memoria, "din-don") --------------------------------
function Crear-Sonido {
    $rate = 22050
    $tonos = @(@(988, 0.09), @(0, 0.03), @(1319, 0.14))
    $muestras = New-Object System.Collections.Generic.List[int16]
    foreach ($t in $tonos) {
        $n = [int]($rate * $t[1])
        for ($i = 0; $i -lt $n; $i++) {
            $amp = [Math]::Min(1.0, [Math]::Min($i / 200.0, ($n - $i) / 600.0))
            $v = if ($t[0] -gt 0) { [Math]::Sin(2 * [Math]::PI * $t[0] * $i / $rate) * 9000 * $amp } else { 0 }
            $muestras.Add([int16]$v)
        }
    }
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $datos = $muestras.Count * 2
    $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + $datos))
    $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $bw.Write([int]16)
    $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]$rate); $bw.Write([int]($rate * 2))
    $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]$datos)
    foreach ($m in $muestras) { $bw.Write($m) }
    $bw.Flush(); $ms.Position = 0
    New-Object System.Media.SoundPlayer($ms)
}
$script:sonido = $null
try { $script:sonido = Crear-Sonido; $script:sonido.Load() } catch { Log "Sin sonido: $_" }

# --- Configuración (posición y sonido) --------------------------------------------
$script:config = [pscustomobject]@{ x = $null; y = $null; sonido = $true }
if (Test-Path $archivoConfig) {
    try {
        $c = [IO.File]::ReadAllText($archivoConfig) | ConvertFrom-Json
        if ($null -ne $c.x) { $script:config.x = [int]$c.x }
        if ($null -ne $c.y) { $script:config.y = [int]$c.y }
        if ($null -ne $c.sonido) { $script:config.sonido = [bool]$c.sonido }
    } catch { Log "config.json inválido: $_" }
}

function Guardar-Config {
    try {
        $script:config.x = $form.Left
        $script:config.y = $form.Top
        [IO.File]::WriteAllText($archivoConfig, ($script:config | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    } catch { Log "No pude guardar config: $_" }
}

function Posicion-Inicial {
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $p = New-Object System.Drawing.Point(($area.Right - $W - [int](16 * $s)), ($area.Bottom - $H))
    if ($null -ne $script:config.x -and $null -ne $script:config.y) {
        $r = New-Object System.Drawing.Rectangle($script:config.x, $script:config.y, $W, $H)
        foreach ($pantalla in [System.Windows.Forms.Screen]::AllScreens) {
            $i = [System.Drawing.Rectangle]::Intersect($pantalla.WorkingArea, $r)
            if ($i.Width -ge 60 * $s -and $i.Height -ge 60 * $s) { return New-Object System.Drawing.Point($script:config.x, $script:config.y) }
        }
    }
    return $p
}

# --- Estado -----------------------------------------------------------------------
$e = [char]0x2026
$script:estado = 'esperando'
$script:texto  = "Esperando$e"
$script:ultimoTs = [long]0
$script:desde = [DateTime]::Now      # cuándo empezó el estado actual
$script:frame = 0
$script:inicioFrame = 0

function Poner-Estado([string]$nuevo, [string]$txt) {
    $anterior = $script:estado
    $script:estado = $nuevo
    $script:texto = $txt
    if ($nuevo -ne $anterior) {
        $script:desde = [DateTime]::Now
        $script:inicioFrame = $script:frame
        if ($nuevo -eq 'aprobacion' -and $script:config.sonido -and $script:sonido) {
            try { $script:sonido.Play() } catch { }
        }
    }
}

function Leer-Estado([bool]$arranque) {
    if (-not (Test-Path $archivoEstado)) { return }
    try { $j = [IO.File]::ReadAllText($archivoEstado, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { return }
    if (-not $j -or -not $j.ts) { return }
    $ts = [long]$j.ts
    if ($ts -le $script:ultimoTs) { return }
    $script:ultimoTs = $ts
    $viejo = ([DateTime]::UtcNow.Ticks - $ts) -gt [TimeSpan]::FromMinutes(2).Ticks
    if ($arranque -and $viejo) { return }   # al iniciar Windows no mostramos estados viejos
    $est = [string]$j.estado
    if ($est -notin 'esperando', 'trabajando', 'aprobacion', 'listo') { $est = 'trabajando' }
    Poner-Estado $est ([string]$j.texto)
    $tip = 'Claude Code'
    if ($j.proyecto) { $tip = "Claude Code - $($j.proyecto)" }
    $script:tooltip.SetToolTip($form, $tip)
}

# Si pasa mucho tiempo sin novedades, volvemos a "esperando".
function Revisar-Vencimientos {
    $min = ([DateTime]::Now - $script:desde).TotalMinutes
    $sinNovedades = ([DateTime]::UtcNow.Ticks - $script:ultimoTs) / [TimeSpan]::TicksPerMinute
    switch ($script:estado) {
        'listo'      { if ($min -gt 5) { Poner-Estado 'esperando' "Esperando$e" } }
        'trabajando' { if ($sinNovedades -gt 10) { Poner-Estado 'esperando' "Esperando$e" } }
        'aprobacion' { if ($sinNovedades -gt 10) { Poner-Estado 'esperando' "Esperando$e" } }
    }
}

# --- Dibujo -----------------------------------------------------------------------
# El personaje mide 16 x 11 "pixeles" (cada uno de $u x $u). R() dibuja en esas unidades.
function R([double]$c, [double]$r, [double]$w, [double]$h, $b) {
    $g.FillRectangle($b, [int]($ox + $c * $u), [int]($oy + $r * $u), [int]($w * $u), [int]($h * $u))
}

function Chispa([double]$c, [double]$r, $b) {
    R $c ($r - 1) 1 3 $b
    R ($c - 1) $r 3 1 $b
}

function Dibujar-Globo($g) {
    $txt = $script:texto
    if (-not $txt) { return }
    $borde = $bBorde
    if ($script:estado -eq 'aprobacion' -and ($script:frame % 6) -lt 3) { $borde = $bRojo }
    elseif ($script:estado -eq 'listo') { $borde = $bVerde }

    $b = [int][Math]::Max(2, [Math]::Round(2 * $s))
    $c = $b * 2
    $med = $g.MeasureString($txt, $fuente)
    $bw = [int][Math]::Min($W - 8 * $s, [Math]::Max(70 * $s, [Math]::Ceiling($med.Width) + 22 * $s))
    $bh = [int](30 * $s)
    $bx = [int](($W - $bw) / 2)
    $by = [int](4 * $s)

    # Cuerpo del globo con esquinas "pixeladas"
    $g.FillRectangle($borde, $bx + $c, $by, $bw - 2 * $c, $bh)
    $g.FillRectangle($borde, $bx, $by + $c, $bw, $bh - 2 * $c)
    $g.FillRectangle($borde, $bx + $b, $by + $b, $bw - 2 * $b, $bh - 2 * $b)
    $g.FillRectangle($bBlanco, $bx + $c, $by + $b, $bw - 2 * $c, $bh - 2 * $b)
    $g.FillRectangle($bBlanco, $bx + $b, $by + $c, $bw - 2 * $b, $bh - 2 * $c)

    # Colita escalonada apuntando al personaje
    $k = [int][Math]::Max(2, [Math]::Round(2 * $s))
    $cx = [int]($W / 2)
    for ($i = 0; $i -lt 4; $i++) {
        $mitad = (4 - $i) * $k
        $y = $by + $bh - $b + $i * $k
        $g.FillRectangle($borde, $cx - $mitad, $y, 2 * $mitad, $k)
        if (2 * $mitad - 2 * $b -gt 0) { $g.FillRectangle($bBlanco, $cx - $mitad + $b, $y, 2 * $mitad - 2 * $b, $k) }
    }

    $rect = New-Object System.Drawing.RectangleF(($bx + $b + 4 * $s), ($by + $b), ($bw - 2 * $b - 8 * $s), ($bh - 2 * $b))
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.DrawString($txt, $fuente, $bTexto, $rect, $formatoTexto)
}

function Dibujar-Personaje($g) {
    $f = $script:frame
    $t = $f - $script:inicioFrame        # frames desde que empezó el estado
    $dy = 0                              # salto (en unidades, negativo = arriba)
    $baja = 0                            # "respiración": el cuerpo baja 1 unidad
    $ojos = 'normal'
    $brazos = 'afuera'
    $piernas = 'parado'
    $cuerpo = $bNaranja

    switch ($script:estado) {
        'esperando' {
            if (($f % 30) -ge 15) { $baja = 1 }
            if (($f % 40) -lt 2) { $ojos = 'parpadeo' }
        }
        'trabajando' {
            $piernas = if ((($f -shr 1) % 2) -eq 0) { 'pasoA' } else { 'pasoB' }
            $ojos = if ((($f -shr 3) % 2) -eq 0) { 'izq' } else { 'der' }
            if (($f % 30) -lt 2) { $ojos = 'parpadeo' }
        }
        'aprobacion' {
            $saltos = 0, -1, -2, -3, -3, -2, -1, 0
            $dy = $saltos[$f % 8]
            $brazos = if ((($f -shr 1) % 2) -eq 0) { 'arriba' } else { 'afuera' }
            $ojos = 'grandes'
            if ((($f / 3) % 2) -ge 1) { $cuerpo = $bNaranjaCl }
        }
        'listo' {
            $ojos = 'felices'
            if ($t -lt 8) { $saltos = 0, -1, -2, -3, -3, -2, -1, 0; $dy = $saltos[$t] }
            if ($t -lt 14) { $brazos = 'arriba' }
            elseif (($f % 30) -ge 15) { $baja = 1 }
        }
    }

    # Origen del personaje (abajo al centro de la ventana)
    $script:ox = [int](($W - 16 * $u) / 2)
    $script:oy = [int]($H - 3 * $s - 11 * $u + $dy * $u)
    $ox = $script:ox; $oy = $script:oy

    # Piernas (columnas 3, 5, 10 y 12)
    foreach ($col in 3, 5, 10, 12) {
        $levantada = ($piernas -eq 'pasoA' -and ($col -eq 3 -or $col -eq 10)) -or ($piernas -eq 'pasoB' -and ($col -eq 5 -or $col -eq 12))
        if ($baja) { R $col 10 1 1 $bNaranjaOsc }
        elseif ($levantada) { R $col 9 1 1 $bNaranjaOsc }
        else { R $col 9 1 2 $bNaranjaOsc }
    }

    # Cuerpo
    R 2 (2 + $baja) 12 7 $cuerpo
    R 2 (8 + $baja) 12 1 $bNaranjaOsc

    # Brazos
    if ($brazos -eq 'arriba') {
        R 0 (1 + $baja) 2 3 $cuerpo
        R 14 (1 + $baja) 2 3 $cuerpo
    } else {
        R 0 (4 + $baja) 2 2 $cuerpo
        R 14 (4 + $baja) 2 2 $cuerpo
    }

    # Ojos
    $oj = 4 + $baja
    switch ($ojos) {
        'normal'   { R 5 $oj 1 2 $bOjos; R 10 $oj 1 2 $bOjos }
        'izq'      { R 4 $oj 1 2 $bOjos; R 9 $oj 1 2 $bOjos }
        'der'      { R 6 $oj 1 2 $bOjos; R 11 $oj 1 2 $bOjos }
        'parpadeo' { R 4 ($oj + 1) 2 1 $bOjos; R 10 ($oj + 1) 2 1 $bOjos }
        'grandes'  { R 4 $oj 2 2 $bOjos; R 10 $oj 2 2 $bOjos; R 7 ($oj + 2) 2 1 $bOjos }
        'felices'  {
            R 4 ($oj + 1) 1 1 $bOjos; R 5 $oj 1 1 $bOjos; R 6 ($oj + 1) 1 1 $bOjos
            R 9 ($oj + 1) 1 1 $bOjos; R 10 $oj 1 1 $bOjos; R 11 ($oj + 1) 1 1 $bOjos
        }
    }

    # Extras de cada estado
    switch ($script:estado) {
        'esperando' {
            # Una "z" que sube despacito
            if ($t -gt 20) {
                $sub = ($f % 24) / 8.0
                $zx = 16.5; $zy = 1 - $sub
                R $zx $zy 2 0.5 $bGris
                R ($zx + 1) ($zy + 0.5) 0.5 0.5 $bGris
                R ($zx + 0.5) ($zy + 1) 0.5 0.5 $bGris
                R $zx ($zy + 1.5) 2 0.5 $bGris
            }
        }
        'trabajando' {
            # Puntitos de "pensando" que se van encendiendo
            $n = ($f -shr 2) % 4
            if ($n -ge 1) { R 13 0 1 1 $bGris }
            if ($n -ge 2) { R 15 -1 1 1 $bGris }
            if ($n -ge 3) { R 17 -2 1 1 $bGris }
        }
        'aprobacion' {
            # Signo de exclamación al costado de la cabeza
            R 17 -1 2 3 $bRojo
            R 17 3 2 1 $bRojo
        }
        'listo' {
            if ((($f -shr 2) % 2) -eq 0) {
                Chispa -2 2 $bAmarillo
                Chispa 17.5 -1 $bVerde
            } else {
                Chispa -1.5 -1 $bVerde
                Chispa 18 3 $bAmarillo
            }
        }
    }
}

# --- Ventana ----------------------------------------------------------------------
$form = New-Object MascotaForm
$form.Text = 'Mascota Claude'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.ClientSize = New-Object System.Drawing.Size($W, $H)
$form.BackColor = $colorClave
$form.TransparencyKey = $colorClave
$form.Location = Posicion-Inicial

$script:tooltip = New-Object System.Windows.Forms.ToolTip
$script:tooltip.SetToolTip($form, 'Claude Code')

$form.Add_Paint({
    param($sender, $ev)
    try {
        $g = $ev.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
        $g.Clear($colorClave)
        Dibujar-Personaje $g
        Dibujar-Globo $g
    } catch {
        if (-not $script:errorDibujo) { Log "Error dibujando: $_"; $script:errorDibujo = $true }
    }
})

# Arrastrar con el botón izquierdo
$script:arrastrando = $false
$script:agarre = $null
$form.Add_MouseDown({
    param($sender, $ev)
    if ($ev.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:arrastrando = $true
        $cur = [System.Windows.Forms.Cursor]::Position
        $script:agarre = New-Object System.Drawing.Point(($cur.X - $form.Left), ($cur.Y - $form.Top))
    }
})
$form.Add_MouseMove({
    if ($script:arrastrando) {
        $cur = [System.Windows.Forms.Cursor]::Position
        $form.Location = New-Object System.Drawing.Point(($cur.X - $script:agarre.X), ($cur.Y - $script:agarre.Y))
    }
})
$form.Add_MouseUp({
    if ($script:arrastrando) {
        $script:arrastrando = $false
        Guardar-Config
    }
})

# Menú de clic derecho
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$itemTitulo = $menu.Items.Add('Mascota de Claude Code')
$itemTitulo.Enabled = $false
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$itemSonido = New-Object System.Windows.Forms.ToolStripMenuItem('Sonido al pedir permiso')
$itemSonido.CheckOnClick = $true
$itemSonido.Checked = [bool]$script:config.sonido
$itemSonido.Add_Click({
    $script:config.sonido = $itemSonido.Checked
    Guardar-Config
    if ($itemSonido.Checked -and $script:sonido) { try { $script:sonido.Play() } catch { } }
})
[void]$menu.Items.Add($itemSonido)
$itemEsquina = New-Object System.Windows.Forms.ToolStripMenuItem('Volver a la esquina')
$itemEsquina.Add_Click({
    $script:config.x = $null; $script:config.y = $null
    $form.Location = Posicion-Inicial
    Guardar-Config
})
[void]$menu.Items.Add($itemEsquina)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$itemCerrar = New-Object System.Windows.Forms.ToolStripMenuItem('Cerrar mascota')
$itemCerrar.Add_Click({ $form.Close() })
[void]$menu.Items.Add($itemCerrar)
$form.ContextMenuStrip = $menu

# Animación (10 cuadros por segundo) y lectura del estado
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 100
$timer.Add_Tick({
    try {
        $script:frame++
        if (($script:frame % 3) -eq 0) { Leer-Estado $false; Revisar-Vencimientos }
        # Cada tanto reafirmamos "siempre visible" (algunas apps a pantalla completa lo pisan)
        if (($script:frame % 50) -eq 0 -and -not $menu.Visible) { $form.TopMost = $true }
        $form.Invalidate()
    } catch {
        if (-not $script:errorTimer) { Log "Error en timer: $_"; $script:errorTimer = $true }
    }
})

$form.Add_FormClosing({
    $timer.Stop()
    Guardar-Config
})

try {
    Leer-Estado $true
    $timer.Start()
    Log 'Mascota iniciada'
    [System.Windows.Forms.Application]::Run($form)
} catch {
    Log "Error fatal: $_"
} finally {
    try { $script:mutex.ReleaseMutex() } catch { }
}
