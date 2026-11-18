<#
.SYNOPSIS
  Captura la ventana REAL de EdenPOS en pantalla (pixeles de la pantalla, no DrawToBitmap) mientras simula uso.

.DESCRIPTION
  Capturas.ps1 dibuja formularios invisibles con DrawToBitmap, que pinta cada control una sola vez y NO reproduce los
  repintados reales (bufer doble compartido, hover, cambio de seleccion, scroll). Este script:
    1. Carga EdenPOS.exe por bytes (mismo resolvedor que Capturas.ps1) contra la base edenpos_capturas del 3307
       (debe existir: creela antes con  Capturas.ps1 -KeepDb). Nunca toca el 3306.
    2. Muestra el MainForm DE VERDAD (visible, encima de todo) a 1366x768 y luego maximizado.
    3. Simula uso: navega varias veces entre las pantallas, mueve el cursor sobre la barra lateral, selecciona filas,
       hace scroll en Inventario, llena un carrito y abre el dialogo de cobro (trabajador).
    4. Tras cada paso copia los pixeles reales de la ventana con Graphics.CopyFromScreen a devdb\capturas\real\<Etiqueta>\.
  La ventana aparece unos segundos en pantalla y el cursor se mueve; al terminar se cierra y el cursor vuelve a su sitio.

.EXAMPLE
  powershell -NoProfile -STA -ExecutionPolicy Bypass -File devdb\tools\CapturasReal.ps1 -Etiqueta despues -BinDir <carpeta>
#>
[CmdletBinding()]
param(
    [string]$Etiqueta = 'actual',
    [string]$OutDir = '',
    [string]$BinDir = ''
)

$ErrorActionPreference = 'Stop'

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $argsList = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $MyInvocation.MyCommand.Path, '-Etiqueta', $Etiqueta)
    if ($OutDir) { $argsList += @('-OutDir', $OutDir) }
    if ($BinDir) { $argsList += @('-BinDir', $BinDir) }
    & powershell.exe @argsList
    exit $LASTEXITCODE
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $BinDir) { $BinDir = Join-Path $root 'bin\Debug\net48' }
$BinDir = (Resolve-Path $BinDir).Path
if (-not $OutDir) { $OutDir = Join-Path $root ("devdb\capturas\real\" + $Etiqueta) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

$mysql = 'C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe'
$captureDb = 'edenpos_capturas'
$exists = & $mysql -h 127.0.0.1 -P 3307 -u root -N -B -e "SHOW DATABASES LIKE '$captureDb'" 2>&1
if ($LASTEXITCODE -ne 0 -or -not $exists) { throw "No existe $captureDb en el 3307. Ejecute antes: Capturas.ps1 -KeepDb" }

$dataPath = Join-Path ([IO.Path]::GetTempPath()) ('edenpos-real-data-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $dataPath | Out-Null
$env:EDENPOS_DATA_PATH = $dataPath
$env:EDENPOS_MYSQL_CONNECTION = "Server=127.0.0.1;Port=3307;Database=$captureDb;User ID=root;Password=;"

$cursorHome = $null
$snapshot = $null
try {
    if (-not ('EdenCapResolver' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Reflection;
public static class EdenCapResolver
{
    public static string Dir;
    public static void Install(string dir)
    {
        Dir = dir;
        AppDomain.CurrentDomain.AssemblyResolve += Resolve;
    }
    private static Assembly Resolve(object sender, ResolveEventArgs args)
    {
        string name = new AssemblyName(args.Name).Name;
        foreach (Assembly loaded in AppDomain.CurrentDomain.GetAssemblies())
            if (string.Equals(loaded.GetName().Name, name, StringComparison.OrdinalIgnoreCase)) return loaded;
        string path = Path.Combine(Dir, name + ".dll");
        if (File.Exists(path)) return Assembly.Load(File.ReadAllBytes(path));
        return null;
    }
}
"@
    }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing

    $snapshot = Join-Path ([IO.Path]::GetTempPath()) ('edenpos-real-bin-' + [Guid]::NewGuid().ToString('N'))
    Copy-Item -Recurse -Force $BinDir $snapshot
    [EdenCapResolver]::Install($snapshot)
    try { [AppDomain]::CurrentDomain.SetData('APPBASE', $snapshot + '') } catch { }
    [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $snapshot 'MySqlConnector.dll')))
    try { $appAsm = [Reflection.Assembly]::LoadFile((Join-Path $snapshot 'EdenPOS.exe')) }
    catch { $appAsm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $snapshot 'EdenPOS.exe'))) }
    [Windows.Forms.Application]::EnableVisualStyles()
    [Threading.Thread]::CurrentThread.CurrentCulture = New-Object Globalization.CultureInfo 'es-PE'
    [Threading.Thread]::CurrentThread.CurrentUICulture = New-Object Globalization.CultureInfo 'es-PE'

    $BF = [Reflection.BindingFlags]'Instance,NonPublic,Public'
    function Get-Priv($obj, [string]$name) {
        $t = $obj.GetType()
        while ($t) { $f = $t.GetField($name, $BF); if ($f) { return ,$f.GetValue($obj) }; $t = $t.BaseType }
        throw "Campo $name no encontrado en $($obj.GetType().Name)"
    }
    function Invoke-Priv($obj, [string]$name, [object[]]$arguments = @()) {
        $m = $obj.GetType().GetMethod($name, $BF)
        if (-not $m) { throw "Metodo $name no encontrado en $($obj.GetType().Name)" }
        return $m.Invoke($obj, $arguments)
    }
    function New-Obj([string]$typeName, [object[]]$arguments = @()) {
        $t = $appAsm.GetType($typeName, $true)
        $clean = New-Object 'object[]' $arguments.Length
        for ($i = 0; $i -lt $arguments.Length; $i++) {
            $a = $arguments[$i]
            if ($null -ne $a) { $a = $a.PSObject.BaseObject }
            $clean[$i] = $a
        }
        return [Activator]::CreateInstance($t, $BF, $null, $clean, $null)
    }
    # Deja que Windows entregue los WM_PAINT / WM_MOUSEMOVE reales (varias vueltas con pausas cortas).
    function Pump([int]$ms = 250) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt $ms) { [Windows.Forms.Application]::DoEvents(); [Threading.Thread]::Sleep(15) }
        [Windows.Forms.Application]::DoEvents()
    }

    $script:made = 0
    # Copia los pixeles REALES de la pantalla dentro del rectangulo de la ventana (recortado a la pantalla).
    function Snap($form, [string]$name) {
        Pump 350
        $screen = [Windows.Forms.Screen]::FromControl($form).Bounds
        $r = [Drawing.Rectangle]::Intersect($form.Bounds, $screen)
        $bmp = New-Object Drawing.Bitmap($r.Width, $r.Height)
        $g = [Drawing.Graphics]::FromImage($bmp)
        try {
            $g.CopyFromScreen($r.Location, [Drawing.Point]::Empty, $r.Size)
            $bmp.Save((Join-Path $OutDir ($name + '.png')), [Drawing.Imaging.ImageFormat]::Png)
            $script:made++
            Write-Host ("  ok  {0}.png ({1}x{2})" -f $name, $r.Width, $r.Height)
        } finally { $g.Dispose(); $bmp.Dispose() }
    }

    function Show-Real($form, [int]$w, [int]$h) {
        $form.StartPosition = 'Manual'
        $form.WindowState = 'Normal'
        $form.Location = New-Object Drawing.Point(0, 0)
        $form.Size = New-Object Drawing.Size($w, $h)
        $form.TopMost = $true
        $form.Opacity = 1
        $form.Show()
        $form.WindowState = 'Normal'
        $form.Location = New-Object Drawing.Point(0, 0)
        $form.Size = New-Object Drawing.Size($w, $h)
        $form.Activate()
        Pump 600
    }

    function Maximize($form) { $form.WindowState = 'Maximized'; $form.Activate(); Pump 600 }

    function Move-Cursor($control, [int]$dx = -1, [int]$dy = -1) {
        if ($dx -lt 0) { $dx = [int]($control.Width / 2) }
        if ($dy -lt 0) { $dy = [int]($control.Height / 2) }
        [Windows.Forms.Cursor]::Position = $control.PointToScreen((New-Object Drawing.Point($dx, $dy)))
        Pump 200
    }

    function Close-Form($f) { try { if ($f) { $f.TopMost = $false; $f.Close(); $f.Dispose() } } catch { } }

    function Find-Grid($parent) {
        foreach ($c in $parent.Controls) {
            if ($c -is [Windows.Forms.DataGridView]) { return $c }
            $r = Find-Grid $c
            if ($r) { return $r }
        }
        return $null
    }

    $cursorHome = [Windows.Forms.Cursor]::Position

    [EdenPOS.AppData]::Initialize()
    $users = [EdenPOS.AppData]::Users
    $owner = $users | Where-Object { $_.Role -eq [EdenPOS.UserRoles]::Owner } | Select-Object -First 1
    $worker = $users | Where-Object { $_.Name -eq 'CARLOS' -and $_.Active } | Select-Object -First 1
    if (-not $worker) { $worker = $users | Where-Object { $_.Role -ne [EdenPOS.UserRoles]::Owner -and $_.Active } | Select-Object -First 1 }
    $products = @([EdenPOS.AppData]::Products | Where-Object { $_.Active })
    $general = $products | Where-Object { $_.Name -eq 'GENERAL' } | Select-Object -First 1
    if (-not $general) { $general = $products | Where-Object { $_.Category -eq 'SAUNA' } | Select-Object -First 1 }
    $drinks = @($products | Where-Object { $_.Category -ne 'SAUNA' } | Select-Object -First 3)

    Write-Host "Salida: $OutDir"

    # ------------------------------------------------------------------ Duena
    [EdenPOS.AppSession]::SignIn($owner)
    $f = New-Obj 'EdenPOS.MainForm'
    try {
        Show-Real $f 1366 768
        $nav = Get-Priv $f 'navButtons'
        Snap $f 'd01-inventario-1366'
        $order = @('reports', 'audit', 'settings', 'inventory', 'settings', 'reports', 'inventory', 'audit')
        $i = 2
        foreach ($k in $order) {
            Invoke-Priv $f 'Navigate' @($k) | Out-Null
            Snap $f ('d{0:00}-nav-{1}-1366' -f $i, $k); $i++
        }
        # Cursor sobre cada boton de la barra lateral (hover real) y fuera.
        foreach ($k in @('inventory', 'reports', 'audit', 'settings')) { Move-Cursor $nav[$k] }
        Snap $f ('d{0:00}-hover-settings-1366' -f $i); $i++
        Move-Cursor $nav['reports']
        Snap $f ('d{0:00}-hover-reports-1366' -f $i); $i++
        Move-Cursor $f 900 400
        # Clic real (mensajes de raton) en Inventario
        Invoke-Priv $f 'Navigate' @('inventory') | Out-Null
        Pump 300
        $views = Get-Priv $f 'views'
        $grid = Get-Priv $views['inventory'] 'grid'
        $grid.Focus() | Out-Null
        $deo = $null
        foreach ($row in $grid.Rows) { if ([string]$row.Cells['Name'].Value -eq 'DESODORANTE') { $deo = $row.Index } }
        $targets = @(0, 3)
        if ($null -ne $deo) { $targets += $deo; $targets += [Math]::Min($grid.Rows.Count - 1, $deo + 1) }
        foreach ($r in $targets) {
            $grid.CurrentCell = $grid.Rows[$r].Cells[1]
            Snap $f ('d{0:00}-inventario-fila{1}-1366' -f $i, $r); $i++
        }
        # Cursor recorriendo la tabla (filas bajo el raton)
        $rect = $grid.GetCellDisplayRectangle(5, $grid.FirstDisplayedScrollingRowIndex, $false)
        for ($y = 0; $y -lt 6; $y++) { [Windows.Forms.Cursor]::Position = $grid.PointToScreen((New-Object Drawing.Point(($rect.X + 20), ($rect.Y + 10 + $y * 48)))); Pump 80 }
        if ($grid.Rows.Count -gt 12) {
            $grid.FirstDisplayedScrollingRowIndex = [Math]::Min($grid.Rows.Count - 1, 10)
            Snap $f ('d{0:00}-inventario-scroll-1366' -f $i); $i++
            $grid.FirstDisplayedScrollingRowIndex = 0
            Snap $f ('d{0:00}-inventario-scroll-vuelta-1366' -f $i); $i++
        }

        Maximize $f
        Snap $f ('d{0:00}-inventario-max' -f $i); $i++
        foreach ($k in @('reports', 'audit', 'settings', 'inventory')) {
            Invoke-Priv $f 'Navigate' @($k) | Out-Null
            Move-Cursor $nav[$k]
            Snap $f ('d{0:00}-max-{1}' -f $i, $k); $i++
        }
        # Configuracion > Usuarios (tabla con insignias pintadas a mano) y vuelta a Inventario
        Invoke-Priv $f 'Navigate' @('settings') | Out-Null
        Invoke-Priv $views['settings'] 'ShowSection' @('usuarios') | Out-Null
        Snap $f ('d{0:00}-max-config-usuarios' -f $i); $i++
        Invoke-Priv $f 'Navigate' @('inventory') | Out-Null
        Move-Cursor $f 1200 500
        if ($null -ne $deo) {
            $grid.CurrentCell = $grid.Rows[$deo].Cells[1]
            Snap $f ('d{0:00}-max-inventario-desodorante' -f $i); $i++
            $grid.CurrentCell = $grid.Rows[0].Cells[1]
            Snap $f ('d{0:00}-max-inventario-fila0' -f $i); $i++
        }
    } finally { Close-Form $f }

    # ------------------------------------------------------------------ Trabajador
    [EdenPOS.AppSession]::SignOut()
    [EdenPOS.AppSession]::SignIn($worker)
    $f = New-Obj 'EdenPOS.MainForm'
    try {
        Show-Real $f 1366 768
        $nav = Get-Priv $f 'navButtons'
        $sv = (Get-Priv $f 'views')['sales']
        $cart = Get-Priv $sv 'cart'
        if ($general) { $cart.Add((New-Object EdenPOS.ReceiptLine -Property @{ ProductId = $general.Id; Name = $general.Name; UnitPrice = $general.Price; Quantity = 2 })) }
        foreach ($d in $drinks) { $cart.Add((New-Object EdenPOS.ReceiptLine -Property @{ ProductId = $d.Id; Name = $d.Name; UnitPrice = $d.Price; Quantity = 1 })) }
        Invoke-Priv $sv 'RenderCart' | Out-Null
        Snap $f 't01-ventas-carrito-1366'
        $i = 2
        foreach ($k in @('receipts', 'shift', 'sales', 'shift', 'receipts', 'sales')) {
            Invoke-Priv $f 'Navigate' @($k) | Out-Null
            Move-Cursor $nav[$k]
            Snap $f ('t{0:00}-nav-{1}-1366' -f $i, $k); $i++
        }
        Move-Cursor $f 700 400
        Snap $f ('t{0:00}-ventas-cursor-fuera-1366' -f $i); $i++
        Maximize $f
        Snap $f ('t{0:00}-ventas-max' -f $i); $i++
        foreach ($k in @('receipts', 'shift', 'sales')) {
            Invoke-Priv $f 'Navigate' @($k) | Out-Null
            Move-Cursor $nav[$k]
            Snap $f ('t{0:00}-max-{1}' -f $i, $k); $i++
        }
        # Dialogo de cobro (no modal, para poder capturarlo y cerrarlo)
        $total = [decimal]0
        foreach ($l in $cart) { $total += $l.UnitPrice * $l.Quantity }
        $d = New-Obj 'EdenPOS.CheckoutDialog' @($total)
        try {
            $d.StartPosition = 'Manual'
            $d.TopMost = $true
            $d.Show($f)
            $d.Location = New-Object Drawing.Point(([int](($f.Width - $d.Width) / 2)), ([int](($f.Height - $d.Height) / 2)))
            $d.Activate()
            Pump 500
            Snap $d ('t{0:00}-dialogo-cobro' -f $i); $i++
            Snap $f ('t{0:00}-dialogo-cobro-ventana' -f $i); $i++
        } finally { Close-Form $d }
        Snap $f ('t{0:00}-tras-cerrar-cobro' -f $i); $i++
    } finally { Close-Form $f }

    [EdenPOS.AppSession]::SignOut()
    Write-Host ("Listo: {0} capturas en {1}" -f $script:made, $OutDir)
}
finally {
    if ($cursorHome) { [Windows.Forms.Cursor]::Position = $cursorHome }
    Remove-Item -Recurse -Force $dataPath -ErrorAction SilentlyContinue
    if ($snapshot) { Remove-Item -Recurse -Force $snapshot -ErrorAction SilentlyContinue }
}
