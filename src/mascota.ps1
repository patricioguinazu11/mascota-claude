# mascota.ps1 - Mascota de escritorio que muestra qué está haciendo Claude Code.
# Solo usa Windows PowerShell 5.1 + .NET Framework (WinForms/GDI+), que ya vienen con Windows.
#
# Lee estado.json (lo escribe hook.ps1 desde los hooks de Claude Code) y anima una
# bestia pixel-art con 4 estados: esperando, trabajando, aprobacion y listo.
# Camina por la pantalla, se puede arrastrar, un clic le da mimos, doble clic trae
# la ventana de Claude Code al frente y el clic derecho abre el menú.

$ErrorActionPreference = 'Stop'

$carpeta       = $PSScriptRoot
$archivoEstado = Join-Path $carpeta 'estado.json'
$archivoConfig = Join-Path $carpeta 'config.json'
$archivoLog    = Join-Path $carpeta 'mascota.log'

function Log([string]$msg) {
    try { Add-Content -LiteralPath $archivoLog -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) -Encoding UTF8 } catch { }
}

# Si algo falla al arrancar, lo anotamos y lo mostramos en vez de morir en silencio.
trap {
    Log ("Error fatal: {0} (linea {1})" -f $_, $_.InvocationInfo.ScriptLineNumber)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show("La mascota no pudo arrancar:`n`n$_`n`nDetalle en $archivoLog", 'Mascota de Claude Code')
    } catch { }
    exit 1
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
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
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
# Un error inesperado en un evento de la ventana se anota en el log en vez de cerrarla.
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({ param($o, $ev) Log "Error no controlado: $($ev.Exception.Message)" })
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Escala según DPI -------------------------------------------------------------
$gTmp = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$s = [Math]::Max(1.0, $gTmp.DpiX / 96.0)
$gTmp.Dispose()

$W = [int](240 * $s)          # ancho de la ventana
$H = [int](140 * $s)          # alto de la ventana
$u = [int][Math]::Max(2, [Math]::Round(3 * $s))   # tamaño de un "pixel" del personaje

# --- Colores ----------------------------------------------------------------------
function Pincel([string]$hex) { New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($hex)) }
$colorClave  = [System.Drawing.Color]::FromArgb(255, 255, 0, 254)   # se vuelve transparente
$bRojo       = Pincel '#E5443A'
$bRosa       = Pincel '#E5577A'
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

# --- Personaje: la bestia -----------------------------------------------------------
# Dibujo pixel-art mirando a la derecha (cuando camina a la izquierda se espeja), con
# tres cuadros para caminar. Cada letra es un color; para cambiar el diseño alcanza con
# editar este dibujo:
#   K contorno   A/G/D cuerpo (luz, medio, sombra)   F manchas   L/Q panza y mandíbula
#   S/R cuero de la silla   B/V manta   Y ribete   H/J cuernos, colmillo y uñas
#   W/U/E ojo (brillo, arriba, abajo)   T dientes   M/N boca (se ven cuando la abre)   . nada
$arte = @'
[parado]
........................KK....................
...............KKKKKKKKKSK.........H....H.....
............KKKSSSSSSSSSSAK.......H....H......
..........KKVVSSSSSSSSSSSVVKK....HJ....H......
.........KAYBBBBBBBBBBBBBBBBYK...HJ...HJ......
........KAGYBBBBBBBBBBBBBBBBYAK..JAKKKJ.......
.......KAGGYBBBBBBBBBBBBBBBBYGAKKAAAAAAK......
...KK.KAGGGGYYYYYYYYYYYYYYYGGGGAAGGGGGAAK.....
..KAAKAGGFFGGGGGGGGGGGGGFGGGGGGFFGGGFFFFAK....
..KGGAGGGFGGGGGGGGGGGGGGGGGGGGGFGGGGGWUGGAKK..
...KGGGGGGGGGGGGGGGGGGGGGGGGFFGGGGGGGEEGGGAAK.
...KGGFFGGGGGGFFGGGGGGGGGGGGFGGGGGGGGGGGGGGGK.
....KDFDDDDDDDFDDDDDDDDDDDDDDGGGGGGGGGGGGGGGFH
.....KDDDDDDDDDDDDFFDDDDDDDDDDGGGGGGGGGGGGGGH.
......KLLLLLLLLLLLLLLLLLLLLLLLLGGGGGGGGGGGGGH.
.......KLLLLLLLLLLLLLLLLLLLLLLLKLGGGMTMMTMMJ..
.......KGLLLLLLLLLLLLLLLLLLLLLK.KQQNNNNNNNNK..
.......KGGDKKQQQQQKKKKKKKKQQGDK.KLLLLLLLLLLK..
.......KGGDK.KGGDK........KGGDK.KGQQQQQQKKK...
.......KGGDK.KGGDK........KGGDK.KGGDKKKK......
.......KGGDK.KGGDK........KGGDK.KGGDK.........
.......KGGDK.KGGDK........KGGDK.KGGDK.........
.......KGGDK.KGGDK........KGGDK.KGGDK.........
.......HKHKH.HKHKH........HKHKH.HKHKH.........
[paso_a]
........................KK....................
...............KKKKKKKKKSK.........H....H.....
............KKKSSSSSSSSSSAK.......H....H......
..........KKVVSSSSSSSSSSSVVKK....HJ....H......
.........KAYBBBBBBBBBBBBBBBBYK...HJ...HJ......
........KAGYBBBBBBBBBBBBBBBBYAK..JAKKKJ.......
.......KAGGYBBBBBBBBBBBBBBBBYGAKKAAAAAAK......
...KK.KAGGGGYYYYYYYYYYYYYYYGGGGAAGGGGGAAK.....
..KAAKAGGFFGGGGGGGGGGGGGFGGGGGGFFGGGFFFFAK....
..KGGAGGGFGGGGGGGGGGGGGGGGGGGGGFGGGGGWUGGAKK..
...KGGGGGGGGGGGGGGGGGGGGGGGGFFGGGGGGGEEGGGAAK.
...KGGFFGGGGGGFFGGGGGGGGGGGGFGGGGGGGGGGGGGGGK.
....KDFDDDDDDDFDDDDDDDDDDDDDDGGGGGGGGGGGGGGGFH
.....KDDDDDDDDDDDDFFDDDDDDDDDDGGGGGGGGGGGGGGH.
......KLLLLLLLLLLLLLLLLLLLLLLLLGGGGGGGGGGGGGH.
......KLLLLLLLLLLLLLLLLLLLLLLLLKKGGGMTMMTMMJ..
......KGGLLKLLLLLLLLLLLLLLLLLLK..KQNNNNNNNNK..
......KGGDK.KKQQQQQKKKKKKQQQDK...KLLLLLLLLLK..
......KGGDK...KGGDK......KGGDK...KQQQQQQKKK...
......KGGDK...KGGDK......KGGDK...KGGDQKK......
......KGGDK...KGGDK......KGGDK...KGGDK........
......KGGDK...KGGDK......KGGDK...KGGDK........
......HKHKH...KGGDK......KGGDK...HKHKH........
..............HKHKH......HKHKH................
[paso_b]
........................KK....................
...............KKKKKKKKKSK.........H....H.....
............KKKSSSSSSSSSSAK.......H....H......
..........KKVVSSSSSSSSSSSVVKK....HJ....H......
.........KAYBBBBBBBBBBBBBBBBYK...HJ...HJ......
........KAGYBBBBBBBBBBBBBBBBYAK..JAKKKJ.......
.......KAGGYBBBBBBBBBBBBBBBBYGAKKAAAAAAK......
...KK.KAGGGGYYYYYYYYYYYYYYYGGGGAAGGGGGAAK.....
..KAAKAGGFFGGGGGGGGGGGGGFGGGGGGFFGGGFFFFAK....
..KGGAGGGFGGGGGGGGGGGGGGGGGGGGGFGGGGGWUGGAKK..
...KGGGGGGGGGGGGGGGGGGGGGGGGFFGGGGGGGEEGGGAAK.
...KGGFFGGGGGGFFGGGGGGGGGGGGFGGGGGGGGGGGGGGGK.
....KDFDDDDDDDFDDDDDDDDDDDDDDGGGGGGGGGGGGGGGFH
.....KDDDDDDDDDDDDFFDDDDDDDDDDGGGGGGGGGGGGGGH.
......KLLLLLLLLLLLLLLLLLLLLLLLLGGGGGGGGGGGGGH.
.......KLLLLLLLLLLLLLLLLLLLLLLLLLGGGMTMMTMMJ..
........KLLLLLLLLLLLLLLLLLLLLLLKGQQNNNNNNNNK..
........KGGDQQQQQKKKKKKKKKKQGGDKGLLLLLLLLLLK..
........KGGDKGGDK..........KGGDKGGQQKQQQKKK...
........KGGDKGGDK..........KGGDKGGDK.KKK......
........KGGDKGGDK..........KGGDKGGDK..........
........KGGDKGGDK..........KGGDKGGDK..........
........KGGDHKHKH..........HKHKHGGDK..........
........HKHKH..................HKHKH..........
'@
$script:partes = @{}
$parte = $null
foreach ($linea in ($arte -split "`r?`n")) {
    if ($linea -match '^\[(\w+)\]$') { $parte = $Matches[1]; $script:partes[$parte] = New-Object System.Collections.ArrayList; continue }
    if ($parte -and $linea.Trim()) { [void]$script:partes[$parte].Add($linea.TrimEnd()) }
}
$ANCHO = [int](@($script:partes['parado']) | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
$ALTO = $script:partes['parado'].Count

$script:pinceles = @{}
$coloresArte = @{ K = '#232818'; A = '#9BAB80'; G = '#7C8C66'; D = '#5E6D4A'; F = '#4E5C3C'; L = '#BDC29B'
                  Q = '#9CA47E'; S = '#6B4A2E'; R = '#8E6843'; B = '#584C83'; V = '#7A6DAE'; Y = '#D8B652'
                  H = '#F0E8D0'; J = '#C4B894'; E = '#141414'; W = '#FFFFFF'; P = '#B5535A'; O = '#8E3B44'
                  C = '#A3B585' }
foreach ($k in $coloresArte.Keys) { $script:pinceles[$k] = Pincel $coloresArte[$k] }

# Traduce una letra del dibujo al color final según ojos y boca.
function Letra-Final([string]$ch, [string]$ojo, [bool]$boca, [bool]$claro) {
    switch -CaseSensitive ($ch) {
        'E' { if ($ojo -eq 'abierto') { return 'E' } else { return 'F' } }
        'U' { if ($ojo -eq 'abierto') { return 'E' } else { return 'G' } }
        'W' { if ($ojo -eq 'abierto') { return 'W' } else { return 'G' } }
        'T' { if ($boca) { return 'H' } else { return 'K' } }
        'M' { if ($boca) { return 'P' } else { return 'K' } }
        'N' { if ($boca) { return 'O' } else { return 'Q' } }
        'G' { if ($claro) { return 'C' } else { return 'G' } }
        default { return $ch }
    }
}

# Arma (y guarda) la lista de rectángulos de cada variante del dibujo.
$script:sprites = @{}
function Sprite([string]$patas, [string]$ojo, [bool]$boca, [bool]$claro) {
    $clave = "$patas|$ojo|$boca|$claro"
    if (-not $script:sprites.ContainsKey($clave)) {
        $filas = @($script:partes[$patas])
        $lista = New-Object System.Collections.ArrayList
        for ($fila = 0; $fila -lt $filas.Count; $fila++) {
            $letras = foreach ($ch in $filas[$fila].ToCharArray()) { Letra-Final ([string]$ch) $ojo $boca $claro }
            $letras = @($letras)
            $col = 0
            while ($col -lt $letras.Count) {
                $fin = $col + 1
                while ($fin -lt $letras.Count -and $letras[$fin] -ceq $letras[$col]) { $fin++ }
                if ($letras[$col] -ne '.') { [void]$lista.Add(@($col, $fila, ($fin - $col), $script:pinceles[$letras[$col]])) }
                $col = $fin
            }
        }
        $script:sprites[$clave] = $lista
    }
    return , $script:sprites[$clave]
}

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
$script:config = [pscustomobject]@{ x = $null; y = $null; sonido = $true; caminar = $true }
if (Test-Path $archivoConfig) {
    try {
        $c = [IO.File]::ReadAllText($archivoConfig) | ConvertFrom-Json
        if ($null -ne $c.x) { $script:config.x = [int]$c.x }
        if ($null -ne $c.y) { $script:config.y = [int]$c.y }
        if ($null -ne $c.sonido) { $script:config.sonido = [bool]$c.sonido }
        if ($null -ne $c.caminar) { $script:config.caminar = [bool]$c.caminar }
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
$script:dir = -1            # hacia dónde camina: 1 derecha, -1 izquierda
$script:espejo = $true      # el dibujo mira a la derecha; se espeja al ir a la izquierda
$script:moviendo = $false
$script:paseo = 0           # cuadros que le quedan caminando cuando pasea
$script:descanso = 30       # cuadros que le quedan quieta cuando pasea
$script:dormido = $false
$script:mimos = 0           # cuadros que le quedan de la reacción a un clic
$script:rnd = New-Object System.Random

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
# El personaje mide $ANCHO x $ALTO "pixeles" (cada uno de $u x $u). Pixel dibuja en esas
# unidades y espeja todo cuando la bestia mira a la izquierda.
# (No se llama "R" porque en PowerShell "r" es un alias de Invoke-History y le gana a la función.)
function Pixel([double]$c, [double]$r, [double]$w, [double]$h, $b) {
    if ($script:espejo) { $c = $ANCHO - $c - $w }
    $g.FillRectangle($b, [int]($ox + $c * $u), [int]($oy + $r * $u), [int]($w * $u), [int]($h * $u))
}

function Chispa([double]$c, [double]$r, $b) {
    Pixel $c ($r - 1) 1 3 $b
    Pixel ($c - 1) $r 3 1 $b
}

function Corazon([double]$c, [double]$r, $b) {
    $forma = '.X.X.', 'XXXXX', '.XXX.', '..X..'
    for ($i = 0; $i -lt 4; $i++) {
        for ($j = 0; $j -lt 5; $j++) {
            if ($forma[$i][$j] -eq 'X') { Pixel ($c + $j * 0.75) ($r + $i * 0.75) 0.75 0.75 $b }
        }
    }
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
    $t = $f - $script:inicioFrame        # cuadros desde que empezó el estado
    $saltos = 0, -1, -2, -3, -3, -2, -1, 0
    $dy = 0                              # salto (en unidades, negativo = arriba)
    $ojo = 'abierto'
    $boca = $false
    $claro = $false
    $patas = 'parado'
    if ($script:moviendo -or ($script:estado -eq 'trabajando' -and -not $script:config.caminar)) {
        $patas = if ((($f -shr 1) % 2) -eq 0) { 'paso_a' } else { 'paso_b' }
    }

    switch ($script:estado) {
        'esperando'  { if ($script:dormido -or ($f % 40) -lt 2) { $ojo = 'cerrado' } }
        'trabajando' { if (($f % 30) -lt 2) { $ojo = 'cerrado' } }
        'aprobacion' {
            $dy = $saltos[$f % 8]
            $boca = $true
            if ((($f / 3) % 2) -ge 1) { $claro = $true }
        }
        'listo' {
            $ojo = 'cerrado'; $boca = $true
            if ($t -lt 8) { $dy = $saltos[$t] }
        }
    }
    if ($script:mimos -gt 0) {
        $ojo = 'cerrado'; $boca = $true
        $k = 15 - $script:mimos
        if ($k -lt 8) { $dy = $saltos[$k] }
    }

    # Origen del personaje (abajo al centro de la ventana)
    $script:ox = [int](($W - $ANCHO * $u) / 2)
    $script:oy = [int]($H - 3 * $s - $ALTO * $u)
    $ox = $script:ox; $oy = $script:oy

    foreach ($p in (Sprite $patas $ojo $boca $claro)) { Pixel $p[0] ($p[1] + $dy) $p[2] 1 $p[3] }

    # Extras de cada estado (al lado de la cabeza)
    switch ($script:estado) {
        'esperando' {
            if ($script:dormido) {
                # Una "z" que sube despacito
                $sub = ($f % 24) / 8.0
                $zx = 42; $zy = 3 - $sub
                Pixel $zx $zy 2 0.5 $bGris
                Pixel ($zx + 1) ($zy + 0.5) 0.5 0.5 $bGris
                Pixel ($zx + 0.5) ($zy + 1) 0.5 0.5 $bGris
                Pixel $zx ($zy + 1.5) 2 0.5 $bGris
            }
        }
        'trabajando' {
            # Puntitos de "pensando" que se van encendiendo
            $n = ($f -shr 2) % 4
            if ($n -ge 1) { Pixel 41 4 1 1 $bGris }
            if ($n -ge 2) { Pixel 43 2 1 1 $bGris }
            if ($n -ge 3) { Pixel 45 0 1 1 $bGris }
        }
        'aprobacion' {
            # Signo de exclamación arriba de la cabeza
            Pixel 43 (-2 + $dy) 2 3 $bRojo
            Pixel 43 (2 + $dy) 2 1 $bRojo
        }
        'listo' {
            if ((($f -shr 2) % 2) -eq 0) {
                Chispa -2 8 $bAmarillo
                Chispa 48 6 $bVerde
            } else {
                Chispa 3 3 $bVerde
                Chispa 31 0 $bAmarillo
            }
        }
    }
    if ($script:mimos -gt 0) { Corazon 40 (2 - (15 - $script:mimos) / 3.0) $bRosa }
}

# --- Caminar ------------------------------------------------------------------------
# Trabajando camina decidida; esperando pasea de a ratos y después de un rato largo se
# duerme; pidiendo permiso o cuando termina se queda quieta.
function Mover-Mascota {
    $script:moviendo = $false
    if ($script:mimos -gt 0) { $script:mimos--; return }
    $t = $script:frame - $script:inicioFrame
    $script:dormido = ($script:estado -eq 'esperando' -and $t -gt 1200)
    if (-not $script:config.caminar -or $script:arrastrando -or $menu.Visible) { return }

    $vel = 0
    switch ($script:estado) {
        'trabajando' { $vel = 3 }
        'esperando' {
            if ($script:dormido) { }
            elseif ($script:paseo -gt 0) {
                $script:paseo--
                $vel = 2
                if ($script:paseo -eq 0) { $script:descanso = $script:rnd.Next(40, 150) }
            } elseif ($script:descanso -gt 0) {
                $script:descanso--
                if ($script:descanso -eq 0) {
                    $script:paseo = $script:rnd.Next(20, 80)
                    if ($script:rnd.Next(3) -eq 0) { $script:dir = -$script:dir }
                }
            }
        }
    }
    if ($vel -eq 0) { return }

    $area = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $paso = [int][Math]::Max(1, [Math]::Round($vel * $s))
    $x = $form.Left + $script:dir * $paso
    if ($x -lt $area.Left) { $x = $area.Left; $script:dir = 1 }
    elseif ($x -gt $area.Right - $W) { $x = $area.Right - $W; $script:dir = -1 }
    $form.Left = $x
    $script:moviendo = $true
    $script:espejo = ($script:dir -lt 0)
}

# Doble clic: trae al frente la ventana donde está corriendo Claude Code.
function Traer-Claude {
    $ventana = Get-Process | Where-Object {
        $_.Id -ne $PID -and $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -match 'Claude Code'
    } | Select-Object -First 1
    if (-not $ventana) {
        $script:texto = "No encuentro Claude Code"
        return
    }
    if ([MascotaNativo]::IsIconic($ventana.MainWindowHandle)) { [void][MascotaNativo]::ShowWindow($ventana.MainWindowHandle, 9) }
    [void][MascotaNativo]::SetForegroundWindow($ventana.MainWindowHandle)
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
    param($origen, $ev)
    try {
        $g = $ev.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
        $g.Clear($colorClave)
        Dibujar-Personaje $g
        Dibujar-Globo $g
    } catch {
        if (-not $script:errorDibujo) { Log ("Error dibujando: {0} (linea {1})" -f $_, $_.InvocationInfo.ScriptLineNumber); $script:errorDibujo = $true }
    }
})

# Arrastrar con el botón izquierdo
$script:arrastrando = $false
$script:agarre = $null
$script:inicioClic = $null
$script:movido = $false
$form.Add_MouseDown({
    param($origen, $ev)
    if ($ev.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:arrastrando = $true
        $script:movido = $false
        $cur = [System.Windows.Forms.Cursor]::Position
        $script:inicioClic = $cur
        $script:agarre = New-Object System.Drawing.Point(($cur.X - $form.Left), ($cur.Y - $form.Top))
    }
})
$form.Add_MouseMove({
    if ($script:arrastrando) {
        $cur = [System.Windows.Forms.Cursor]::Position
        if ([Math]::Abs($cur.X - $script:inicioClic.X) + [Math]::Abs($cur.Y - $script:inicioClic.Y) -gt 4) { $script:movido = $true }
        if ($script:movido) {
            $form.Location = New-Object System.Drawing.Point(($cur.X - $script:agarre.X), ($cur.Y - $script:agarre.Y))
        }
    }
})
$form.Add_MouseUp({
    if ($script:arrastrando) {
        $script:arrastrando = $false
        if ($script:movido) { Guardar-Config }
        else { $script:mimos = 15 }      # un clic sin arrastrar: mimos
    }
})
$form.Add_DoubleClick({ Traer-Claude })

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
$itemCaminar = New-Object System.Windows.Forms.ToolStripMenuItem('Caminar por la pantalla')
$itemCaminar.CheckOnClick = $true
$itemCaminar.Checked = [bool]$script:config.caminar
$itemCaminar.Add_Click({
    $script:config.caminar = $itemCaminar.Checked
    Guardar-Config
})
[void]$menu.Items.Add($itemCaminar)
$itemClaude = New-Object System.Windows.Forms.ToolStripMenuItem('Mostrar Claude Code (doble clic)')
$itemClaude.Add_Click({ Traer-Claude })
[void]$menu.Items.Add($itemClaude)
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
        Mover-Mascota
        # Mientras camina, guardamos la posición cada 30 segundos
        if (($script:frame % 300) -eq 0 -and $script:config.caminar) { Guardar-Config }
        # Cada tanto reafirmamos "siempre visible" (algunas apps a pantalla completa lo pisan)
        if (($script:frame % 50) -eq 0 -and -not $menu.Visible) { $form.TopMost = $true }
        $form.Invalidate()
    } catch {
        if (-not $script:errorTimer) { Log ("Error en timer: {0} (linea {1})" -f $_, $_.InvocationInfo.ScriptLineNumber); $script:errorTimer = $true }
    }
})

$form.Add_FormClosing({
    param($o, $ev)
    Log "Mascota cerrada ($($ev.CloseReason))"
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
