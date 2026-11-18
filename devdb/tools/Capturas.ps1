<#
.SYNOPSIS
  Captura PNG de las pantallas de EdenPOS sin abrir la aplicacion (verificacion visual del diseno).

.DESCRIPTION
  1. Copia la base `edenpos` del MariaDB 3306 (SOLO LECTURA, mysqldump) a `edenpos_capturas` en el MySQL 8.4 del 3307.
  2. Carga bin\Debug\net48\EdenPOS.exe por reflexion (por bytes, con resolvedor de ensamblados que ignora versiones).
  3. Inicia sesion como duena / trabajador (AppSession.SignIn), crea cada formulario/vista con opacidad 0 y fuera de
     pantalla, fuerza el layout y lo dibuja con DrawToBitmap a PNG.
  4. Borra `edenpos_capturas` al terminar (salvo -KeepDb). Nunca escribe en el 3306.

  Si una pantalla falla se registra el error (consola y errores.txt) y se sigue con las demas.

.PARAMETER Etiqueta
  Nombre de la carpeta de salida: devdb\capturas\<Etiqueta>\ (por defecto 'base').

.PARAMETER OutDir
  Carpeta de salida explicita (anula Etiqueta).

.PARAMETER BinDir
  Carpeta con EdenPOS.exe (por defecto ..\..\bin\Debug\net48; compile antes con dotnet build).

.PARAMETER Solo
  Filtro opcional (comodin -like) sobre el nombre de la captura, p. ej. -Solo '*dialogo*' o -Solo '03-*'.

.PARAMETER KeepDb
  No borrar edenpos_capturas al final.

.PARAMETER ReuseDb
  Si edenpos_capturas ya existe en el 3307, no la vuelve a copiar del 3306 (util con -KeepDb para repetir rapido).

.EXAMPLE
  powershell -NoProfile -STA -File devdb\tools\Capturas.ps1 -Etiqueta base

.NOTES
  Limitaciones de DrawToBitmap: no pinta ventanas hijas nativas desplegadas (listas de ComboBox abiertas, calendario del
  DateTimePicker), el cursor ni el foco de teclado; las sombras/transparencias de ventana (Opacity) no se reflejan.
  El proceso no tiene manifiesto DPI-aware, asi que se renderiza a 96 DPI (100 %): equivale a la app en un monitor sin escala.
#>
[CmdletBinding()]
param(
    [string]$Etiqueta = 'base',
    [string]$OutDir = '',
    [string]$BinDir = '',
    [string]$Solo = '',
    [switch]$KeepDb,
    [switch]$ReuseDb
)

$ErrorActionPreference = 'Stop'

# Necesita STA para WinForms.
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $argsList = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $MyInvocation.MyCommand.Path, '-Etiqueta', $Etiqueta)
    if ($OutDir) { $argsList += @('-OutDir', $OutDir) }
    if ($BinDir) { $argsList += @('-BinDir', $BinDir) }
    if ($Solo) { $argsList += @('-Solo', $Solo) }
    if ($KeepDb) { $argsList += '-KeepDb' }
    if ($ReuseDb) { $argsList += '-ReuseDb' }
    & powershell.exe @argsList
    exit $LASTEXITCODE
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $BinDir) { $BinDir = Join-Path $root 'bin\Debug\net48' }
$BinDir = (Resolve-Path $BinDir).Path
if (-not $OutDir) { $OutDir = Join-Path $root ("devdb\capturas\" + $Etiqueta) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$errorFile = Join-Path $OutDir 'errores.txt'
if (Test-Path $errorFile) { Remove-Item $errorFile -Force }

$mysqlDir = 'C:\Program Files\MySQL\MySQL Server 8.4\bin'
$mysql = Join-Path $mysqlDir 'mysql.exe'
$mysqldump = Join-Path $mysqlDir 'mysqldump.exe'
$captureDb = 'edenpos_capturas'
$connection = "Server=127.0.0.1;Port=3307;Database=$captureDb;User ID=root;Password=;"

# ---------------------------------------------------------------------------------------------------------------------
# 1. Base de capturas en el 3307 (copia de la 3306; la 3306 solo se LEE)
# ---------------------------------------------------------------------------------------------------------------------
function Invoke-Mysql([string]$sql, [int]$port = 3307) {
    $out = & $mysql -h 127.0.0.1 -P $port -u root -N -B -e $sql 2>&1
    if ($LASTEXITCODE -ne 0) { throw "mysql ($port) fallo: $out" }
    return $out
}

$dbExists = [bool](Invoke-Mysql "SHOW DATABASES LIKE '$captureDb'")
if ($ReuseDb -and $dbExists) {
    Write-Host "Reutilizando $captureDb (3307)."
} else {
    $dump = Join-Path ([IO.Path]::GetTempPath()) ('edenpos-capturas-' + [Guid]::NewGuid().ToString('N') + '.sql')
    Write-Host 'Copiando edenpos (3306, solo lectura) -> edenpos_capturas (3307)...'
    & $mysqldump -h 127.0.0.1 -P 3306 -u root --single-transaction --no-tablespaces --default-character-set=utf8mb4 --result-file=$dump edenpos
    if ($LASTEXITCODE -ne 0) { throw 'mysqldump del 3306 fallo.' }
    Invoke-Mysql "DROP DATABASE IF EXISTS $captureDb; CREATE DATABASE $captureDb CHARACTER SET utf8mb4;" | Out-Null
    $cmd = '"' + $mysql + '" -h 127.0.0.1 -P 3307 -u root --default-character-set=utf8mb4 ' + $captureDb + ' < "' + $dump + '"'
    & cmd.exe /c $cmd
    if ($LASTEXITCODE -ne 0) { throw 'La importacion en el 3307 fallo.' }
    Remove-Item $dump -Force -ErrorAction SilentlyContinue
}

$dataPath = Join-Path ([IO.Path]::GetTempPath()) ('edenpos-capturas-data-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $dataPath | Out-Null
$env:EDENPOS_DATA_PATH = $dataPath
$env:EDENPOS_MYSQL_CONNECTION = $connection

try {
    # -----------------------------------------------------------------------------------------------------------------
    # 2. Carga por bytes
    # -----------------------------------------------------------------------------------------------------------------
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
    if (-not ('EdenCapMinMaxHook' -as [type])) {
        Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class EdenCapMinMaxHook : NativeWindow
{
    public int MaxW = 8000, MaxH = 8000;
    [StructLayout(LayoutKind.Sequential)] struct PT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] struct MMI { public PT reserved, maxSize, maxPosition, minTrack, maxTrack; }
    protected override void WndProc(ref Message m)
    {
        base.WndProc(ref m);
        if (m.Msg == 0x24) // WM_GETMINMAXINFO: Windows limita la ventana al tamano de la pantalla
        {
            MMI info = (MMI)Marshal.PtrToStructure(m.LParam, typeof(MMI));
            info.maxTrack.x = MaxW; info.maxTrack.y = MaxH; info.maxSize.x = MaxW; info.maxSize.y = MaxH;
            Marshal.StructureToPtr(info, m.LParam, false);
        }
    }
}
"@
    }
    $script:hooks = @()
    # Se trabaja sobre una copia de la carpeta de binarios para no bloquear el .exe (otros pueden compilar mientras corre el script).
    Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'edenpos-capturas-bin-*' -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue }
    $snapshot = Join-Path ([IO.Path]::GetTempPath()) ('edenpos-capturas-bin-' + [Guid]::NewGuid().ToString('N'))
    Copy-Item -Recurse -Force $BinDir $snapshot
    $BinDir = $snapshot
    [EdenCapResolver]::Install($BinDir)
    # Los assets (AssetsCatalog, logo) se resuelven desde AppDomain.BaseDirectory: se apunta a la carpeta de la app.
    try { [AppDomain]::CurrentDomain.SetData('APPBASE', $BinDir + '') } catch { }
    [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $BinDir 'MySqlConnector.dll')))
    # LoadFile (con Location real: LoginForm la necesita para encontrar el logo); si Windows lo bloquea, se carga por bytes.
    try { $appAsm = [Reflection.Assembly]::LoadFile((Join-Path $BinDir 'EdenPOS.exe')) }
    catch { $appAsm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $BinDir 'EdenPOS.exe'))) }
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
    function Pump { for ($i = 0; $i -lt 4; $i++) { [Windows.Forms.Application]::DoEvents() } }

    $script:made = 0
    $script:failed = 0
    function Log-Error([string]$name, $err) {
        $script:failed++
        $msg = "[$name] " + $err.Exception.GetType().Name + ': ' + $err.Exception.Message
        Write-Warning $msg
        Add-Content -Path $errorFile -Value ($msg + "`r`n" + $err.ScriptStackTrace + "`r`n") -Encoding UTF8
    }

    function Save-Control($control, [string]$name) {
        $w = $control.Width; $h = $control.Height
        $bmp = New-Object Drawing.Bitmap($w, $h)
        try {
            $control.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $w, $h)))
            $bmp.Save((Join-Path $OutDir ($name + '.png')), [Drawing.Imaging.ImageFormat]::Png)
            $script:made++
            Write-Host ("  ok  {0}.png ({1}x{2})" -f $name, $w, $h)
        } finally { $bmp.Dispose() }
    }

    # Muestra el formulario fuera de pantalla y con opacidad 0 (no se ve), fuerza layout y lo dibuja.
    function Show-Hidden($form, [int]$cw = 0, [int]$ch = 0) {
        $form.StartPosition = 'Manual'
        $form.ShowInTaskbar = $false
        $form.Opacity = 0
        $form.Location = New-Object Drawing.Point(-12000, -12000)
        if ($cw -gt 0) {
            # Tamano fijo: ventana sin borde; el hook sube el limite maximo de Windows (la pantalla) para poder pasar de 1920x1080.
            $form.WindowState = 'Normal'; $form.FormBorderStyle = 'None'
            [void]$form.Handle
            $hook = New-Object EdenCapMinMaxHook
            $hook.MaxW = 8000; $hook.MaxH = 8000
            $hook.AssignHandle($form.Handle)
            $script:hooks += $hook
            $form.MaximumSize = New-Object Drawing.Size(0, 0)
            $form.ClientSize = New-Object Drawing.Size($cw, $ch)
        }
        $form.Show()
        Pump
        $form.Location = New-Object Drawing.Point(-12000, -12000)
        $form.PerformLayout()
        Pump
    }

    function Save-Form($form, [string]$name, [int]$cw = 0, [int]$ch = 0) {
        Show-Hidden $form $cw $ch
        Save-Control $form $name
    }

    function Want([string]$name) { return (-not $Solo) -or ($name -like $Solo) }

    function Step([string]$name, [scriptblock]$body) {
        if (-not (Want $name)) { return }
        try { & $body } catch { Log-Error $name $_ }
        Pump
    }

    function Close-Form($f) { try { if ($f) { $f.Close(); $f.Dispose() } } catch { } }

    function Find-Control($parent, [scriptblock]$pred) {
        foreach ($c in $parent.Controls) {
            if (& $pred $c) { return $c }
            $r = Find-Control $c $pred
            if ($r) { return $r }
        }
        return $null
    }

    # Datos de la base de capturas
    [EdenPOS.AppData]::Initialize()
    $users = [EdenPOS.AppData]::Users
    $owner = $users | Where-Object { $_.Role -eq [EdenPOS.UserRoles]::Owner } | Select-Object -First 1
    $worker = $users | Where-Object { $_.Name -eq 'CARLOS' -and $_.Active } | Select-Object -First 1
    if (-not $worker) { $worker = $users | Where-Object { $_.Role -ne [EdenPOS.UserRoles]::Owner -and $_.Active } | Select-Object -First 1 }
    if (-not $owner -or -not $worker) { throw 'No se encontraron la duena o un trabajador en la base de capturas.' }
    $products = @([EdenPOS.AppData]::Products | Where-Object { $_.Active })
    $categories = [string[]]@($products | ForEach-Object { $_.Category } | Select-Object -Unique)
    $general = $products | Where-Object { $_.Name -eq 'GENERAL' } | Select-Object -First 1
    if (-not $general) { $general = $products | Where-Object { $_.Category -eq 'SAUNA' } | Select-Object -First 1 }
    $drinks = @($products | Where-Object { $_.Category -ne 'SAUNA' } | Select-Object -First 3)
    $withOptions = $products | Where-Object { $_.Options -and $_.Options.Count -gt 0 } | Select-Object -First 1
    $receipt = [EdenPOS.AppData]::Receipts | Where-Object { $_.Status -eq 'Pagado' } | Select-Object -First 1
    if (-not $receipt) { $receipt = [EdenPOS.AppData]::Receipts | Select-Object -First 1 }
    $openShift = [EdenPOS.AppData]::Shifts | Where-Object { $_.IsOpen } | Select-Object -First 1
    if (-not $openShift) { $openShift = [EdenPOS.AppData]::Shifts | Select-Object -First 1 }

    function New-Line($p, [int]$qty) {
        $l = New-Object EdenPOS.ReceiptLine
        $l.ProductId = $p.Id; $l.Name = $p.Name; $l.UnitPrice = $p.Price; $l.Quantity = $qty
        return $l
    }

    function New-Main([int]$w, [int]$h) {
        $m = New-Obj 'EdenPOS.MainForm'
        Show-Hidden $m $w $h
        return $m
    }

    # -----------------------------------------------------------------------------------------------------------------
    # 3. Capturas
    # -----------------------------------------------------------------------------------------------------------------
    Write-Host "Salida: $OutDir"
    $sizes = @(@(1366, 768), @(1920, 1080))

    # --- 00: galeria del sistema de diseno (botones en cada estado, campos, tabla, insignias, banners, estado vacio)
    Step '00-galeria-diseno' {
        $T = [EdenPOS.Theme]
        # Panel raiz sin ventana: un Form no puede pasar de la altura de la pantalla, un Panel si.
        $form = New-Object Windows.Forms.Panel
        $form.BackColor = $T::Canvas; $form.Font = $T::Body; $form.Size = New-Object Drawing.Size(1100, 1200)

        $hdr = New-Object EdenPOS.ScreenHeader
        $hdr.Title = 'Recibos'; $hdr.Subtitle = 'Ventas cobradas, agrupadas por fecha'
        $hdr.AddAction($T::Button('Resumen de hoy', [EdenPOS.ButtonVariant]::Primary))
        $hdr.AddAction($T::Button('Exportar copia', [EdenPOS.ButtonVariant]::Secondary))
        $form.Controls.Add($hdr)

        function New-Card($x, $y, $w, $h) { $c = New-Object EdenPOS.CardPanel; $c.SetBounds($x, $y, $w, $h); $form.Controls.Add($c); return $c }
        function Add-Label($parent, $text, $x, $y, [bool]$field = $false) {
            if ($field) { $l = $T::LabelField($text) } else { $l = $T::Label($text, 11, [Drawing.FontStyle]::Bold) }
            $l.Location = New-Object Drawing.Point($x, $y); $parent.Controls.Add($l)
        }
        $flags = [Reflection.BindingFlags]'Instance,NonPublic'
        function Set-State($b, [string]$state) {
            if ($state -eq 'hover') { $b.GetType().GetField('hover', $flags).SetValue($b, $true) }
            if ($state -eq 'pressed') { $b.GetType().GetField('hover', $flags).SetValue($b, $true); $b.GetType().GetField('pressed', $flags).SetValue($b, $true) }
            if ($state -eq 'disabled') { $b.Enabled = $false }
        }

        # Botones: 4 variantes x 4 estados
        $card1 = New-Card 32 104 1036 250
        Add-Label $card1 'Botones' 24 16
        $variants = @('Primary', 'Secondary', 'Destructive', 'Ghost'); $states = @('normal', 'hover', 'pressed', 'disabled')
        $labels = @('Registrar entrada', 'Guardar cambios', 'Eliminar producto', 'Limpiar')
        for ($r = 0; $r -lt 4; $r++) {
            $s = $states[$r]
            $sl = $T::LabelField($s); $sl.Location = New-Object Drawing.Point(24, (60 + $r * 46 + 12)); $card1.Controls.Add($sl)
            for ($c = 0; $c -lt 4; $c++) {
                $vv = [EdenPOS.ButtonVariant]$variants[$c]
                $b = $T::Button($labels[$c], $vv)
                $b.SetBounds((110 + $c * 190), (60 + $r * 46), 176, 40)
                Set-State $b $s
                $card1.Controls.Add($b)
            }
        }
        # Botones con color propio (compatibilidad): relleno claro, rojo, verde oscuro, blanco
        $b1 = $T::Button('Pagos', $false); $b1.BackColor = $T::GreenSoft; $b1.ForeColor = $T::GreenDark; $b1.FlatAppearance.BorderColor = $T::Green; $b1.SetBounds(880, 60, 130, 40); $card1.Controls.Add($b1)
        $b2 = $T::Button('Ocupado', $false); $b2.BackColor = $T::Danger; $b2.ForeColor = [Drawing.Color]::White; $b2.SetBounds(880, 106, 130, 40); $card1.Controls.Add($b2)
        $b3 = $T::Button('Seleccionado', $true); $b3.BackColor = $T::GreenDark; $b3.SetBounds(880, 152, 130, 40); $card1.Controls.Add($b3)
        $b4 = $T::Button('Sin color', $false); $b4.BackColor = [Drawing.Color]::White; $b4.SetBounds(880, 198, 130, 40); $card1.Controls.Add($b4)

        # Campos
        $card2 = New-Card 32 374 1036 190
        Add-Label $card2 'Campos' 24 16
        $tb = $T::TextBox('Buscar por nombre o DNI'); $tb.SetBounds(24, 70, 240, 40); $card2.Controls.Add($tb); [void]$T::Field($tb, 40)
        Add-Label $card2 'Con marca de agua' 24 50 $true
        $tb2 = $T::TextBox(''); $tb2.Text = 'Con foco (verde)'; $tb2.SetBounds(284, 70, 240, 40); $card2.Controls.Add($tb2)
        $f2 = $T::Field($tb2, 40)
        $f2.GetType().GetField('focused', $flags).SetValue($f2, $true)
        Add-Label $card2 'Con foco' 284 50 $true
        $num = New-Object Windows.Forms.NumericUpDown; $num.Font = New-Object Drawing.Font('Segoe UI', 12); $num.Maximum = 100000; $num.DecimalPlaces = 2; $num.Value = 108; $num.SetBounds(544, 70, 180, 40)
        $card2.Controls.Add($num); [void]$T::Field($num, 40); Add-Label $card2 'Importe (NumericUpDown)' 544 50 $true
        $dtp = New-Object Windows.Forms.DateTimePicker; $dtp.Format = 'Short'; $dtp.SetBounds(744, 70, 150, 40)
        $card2.Controls.Add($dtp); [void]$T::Field($dtp, 40); Add-Label $card2 'Fecha (DateTimePicker)' 744 50 $true
        $cmb = $T::Combo(); $cmb.SetBounds(24, 140, 240, 40); [void]$cmb.Items.AddRange(@('Todas las categorias', 'Sauna', 'Cafeteria', 'Alquileres')); $cmb.SelectedIndex = 0
        $card2.Controls.Add($cmb); Add-Label $card2 'Lista (EdenComboBox)' 24 120 $true
        $tb3 = $T::TextBox(''); $tb3.Text = 'Deshabilitado'; $tb3.SetBounds(284, 140, 240, 40); $card2.Controls.Add($tb3)
        $f3 = $T::Field($tb3, 40); $f3.Enabled = $false; Add-Label $card2 'Deshabilitado' 284 120 $true

        # Tabla
        $card3 = New-Card 32 584 1036 300
        Add-Label $card3 'Tabla' 24 16
        $grid = New-Object Windows.Forms.DataGridView; $grid.SetBounds(24, 52, 988, 230)
        $T::StyleGrid($grid)
        [void]$grid.Columns.Add('c1', 'Producto'); [void]$grid.Columns.Add('c2', 'Categoria'); [void]$grid.Columns.Add('c3', 'Saldo'); [void]$grid.Columns.Add('c4', 'Precio')
        [void]$grid.Rows.Add('GENERAL', 'SAUNA', '-', 'S/ 18.00'); [void]$grid.Rows.Add('MARCIANOS', 'CAFETERIA', '26', 'S/ 2.50')
        [void]$grid.Rows.Add('ALQ TOALLA', 'ALQUILERES', '-', 'S/ 3.00'); [void]$grid.Rows.Add('DESODORANTE', 'ASEO', '12', 'S/ 6.00')
        $grid.Rows[1].Selected = $true
        $card3.Controls.Add($grid)

        # Insignias y banners
        $card4 = New-Card 32 904 1036 150
        Add-Label $card4 'Insignias y mensajes' 24 12
        $x = 24
        foreach ($p in @(@('Aceptado', 'Success'), @('Pendiente', 'Warning'), @('Rechazado', 'Danger'), @('Simulado', 'Info'), @('Activo', 'Brand'), @('Anulado', 'Neutral'))) {
            $pill = $T::Pill($p[0], [EdenPOS.Tone]$p[1], $true); $pill.Location = New-Object Drawing.Point($x, 42); $card4.Controls.Add($pill); $x += $pill.Width + 12
        }
        $pill2 = $T::Pill('Sin punto', [EdenPOS.Tone]::Success, $false); $pill2.Location = New-Object Drawing.Point($x, 42); $card4.Controls.Add($pill2)
        $bn = $T::Banner('Venta registrada. El comprobante simulado fue aceptado.', [EdenPOS.Tone]::Success); $bn.SetBounds(24, 76, 322, 44); $card4.Controls.Add($bn)
        $bn2 = $T::Banner('El stock de Marcianos llego al minimo.', [EdenPOS.Tone]::Warning); $bn2.SetBounds(356, 76, 322, 44); $card4.Controls.Add($bn2)
        $bn3 = $T::Banner('No se pudo guardar el ticket.', [EdenPOS.Tone]::Danger); $bn3.SetBounds(688, 76, 322, 44); $card4.Controls.Add($bn3)

        # Estado vacio en tarjeta con sombra sutil
        $card5 = New-Card 32 1074 1036 110
        $card5.Elevated = $true
        $es = $T::EmptyState('Todavia no hay recibos', 'Cuando cobres una venta aparecera aqui.', $null); $card5.Controls.Add($es)
        $form.CreateControl(); Pump; $form.PerformLayout(); Pump
        Save-Control $form '00-galeria-diseno'
        $form.Dispose()
    }

    [EdenPOS.AppSession]::SignOut()
    Step '01-login' { $f = New-Obj 'EdenPOS.LoginForm'; Save-Form $f '01-login'; Close-Form $f }

    # --- Ventana principal: duena
    [EdenPOS.AppSession]::SignIn($owner)
    foreach ($sz in $sizes) {
        $sfx = '{0}x{1}' -f $sz[0], $sz[1]
        $n = "02-duena-inventario-$sfx"
        Step $n { $f = New-Main $sz[0] $sz[1]; Save-Control $f $n; Close-Form $f }
    }
    if ((Want '03-*') -or (Want '04-*') -or (Want '05-*')) {
        $f = $null
        try {
            $f = New-Main 1366 768
            $views = Get-Priv $f 'views'
            foreach ($sec in @('caja', 'ventas', 'inventario')) {
                $n = "03-duena-reportes-$sec"
                Step $n {
                    Invoke-Priv $f 'Navigate' @('reports') | Out-Null; Pump
                    $tabs = Get-Priv $views['reports'] 'tabButtons'
                    $tabs[$sec].PerformClick()
                    Pump; $f.PerformLayout(); Pump
                    Save-Control $f $n
                }
            }
            Step '04-duena-auditoria' { Invoke-Priv $f 'Navigate' @('audit') | Out-Null; Pump; $f.PerformLayout(); Pump; Save-Control $f '04-duena-auditoria' }
            # Configuración: una captura por sección (navegación a la izquierda; ShowSection es privado, se invoca por reflexión).
            foreach ($sec in @('negocio', 'usuarios', 'promociones', 'facturacion', 'dni', 'copias', 'supabase')) {
                $n = "05-duena-configuracion-$sec"
                Step $n {
                    Invoke-Priv $f 'Navigate' @('settings') | Out-Null; Pump
                    Invoke-Priv $views['settings'] 'ShowSection' @($sec) | Out-Null
                    Pump; $f.PerformLayout(); Pump
                    Save-Control $f $n
                }
            }
            # Réplica en Supabase: la sección es más alta que la ventana; segunda captura desplazada al final.
            $n = '05-duena-configuracion-supabase-abajo'
            Step $n {
                Invoke-Priv $f 'Navigate' @('settings') | Out-Null; Pump
                Invoke-Priv $views['settings'] 'ShowSection' @('supabase') | Out-Null
                Pump; $f.PerformLayout(); Pump
                $page = (Get-Priv $views['settings'] 'pages')['supabase']
                $page.AutoScrollPosition = New-Object System.Drawing.Point(0, 5000)
                Pump; Pump
                Save-Control $f $n
            }
            $n = '05-duena-configuracion-supabase-medio'
            Step $n {
                Invoke-Priv $f 'Navigate' @('settings') | Out-Null; Pump
                Invoke-Priv $views['settings'] 'ShowSection' @('supabase') | Out-Null
                Pump; $f.PerformLayout(); Pump
                $page = (Get-Priv $views['settings'] 'pages')['supabase']
                $page.AutoScrollPosition = New-Object System.Drawing.Point(0, 560)
                Pump; Pump
                Save-Control $f $n
            }
        } catch { Log-Error '03-05-duena' $_ }
        finally { Close-Form $f }
    }

    # --- Ventana principal: trabajador
    [EdenPOS.AppSession]::SignOut()
    [EdenPOS.AppSession]::SignIn($worker)
    foreach ($sz in $sizes) {
        $sfx = '{0}x{1}' -f $sz[0], $sz[1]
        $n = "06-trabajador-ventas-carrito-$sfx"
        Step $n {
            $f = New-Main $sz[0] $sz[1]
            try {
                $sv = (Get-Priv $f 'views')['sales']
                $cart = Get-Priv $sv 'cart'
                $cart.Add((New-Line $general 2))
                foreach ($d in $drinks) { $cart.Add((New-Line $d 1)) }
                (Get-Priv $sv 'customerBox').Text = 'Cliente de prueba'
                Invoke-Priv $sv 'RenderCart' | Out-Null
                Pump; $f.PerformLayout(); Pump
                Save-Control $f $n
            } finally { Close-Form $f }
        }
    }
    if ((Want '06-trabajador-ventas-vacio') -or (Want '07-*') -or (Want '08-*')) {
        $f = $null
        try {
            $f = New-Main 1366 768
            Step '06-trabajador-ventas-vacio' { Invoke-Priv $f 'Navigate' @('sales') | Out-Null; Pump; $f.PerformLayout(); Pump; Save-Control $f '06-trabajador-ventas-vacio' }
            Step '07-trabajador-recibos' { Invoke-Priv $f 'Navigate' @('receipts') | Out-Null; Pump; $f.PerformLayout(); Pump; Save-Control $f '07-trabajador-recibos' }
            Step '08-trabajador-turno' { Invoke-Priv $f 'Navigate' @('shift') | Out-Null; Pump; $f.PerformLayout(); Pump; Save-Control $f '08-trabajador-turno' }
        } catch { Log-Error '06-08-trabajador' $_ }
        finally { Close-Form $f }
    }

    # --- Dialogos (sesion de trabajador)
    Step '10-dialogo-cobro-sin-promo' { $d = New-Obj 'EdenPOS.CheckoutDialog' @([decimal]120); Save-Form $d '10-dialogo-cobro-sin-promo'; Close-Form $d }
    Step '10-dialogo-cobro-con-promo' {
        $promo = New-Object EdenPOS.PromocionResultado
        $promo.Descuento = [decimal]12; $promo.PromocionId = 'GRUPAL'; $promo.Descripcion = 'Descuento grupal 10 %'
        $d = New-Obj 'EdenPOS.CheckoutDialog' @([decimal]120, $promo, '99000001')
        Save-Form $d '10-dialogo-cobro-con-promo'; Close-Form $d
    }
    Step '11-dialogo-venta-completada' { $d = New-Obj 'EdenPOS.SaleCompleteDialog' @($receipt, [decimal]5); Save-Form $d '11-dialogo-venta-completada'; Close-Form $d }
    Step '12-dialogo-guardar-ticket' {
        $d = New-Obj 'EdenPOS.SaveTicketDialog' @('Mesa 1', [int[]]@(4, 7), 2, 1, $null)
        Save-Form $d '12-dialogo-guardar-ticket'; Close-Form $d
    }
    Step '13-dialogo-casilleros' {
        $d = New-Obj 'EdenPOS.LockerSelectionDialog' @([int[]]@(3, 5, 8, 12), [int[]]@(4, 7))
        Save-Form $d '13-dialogo-casilleros'; Close-Form $d
    }
    Step '14-dialogo-tickets-guardados' { $d = New-Obj 'EdenPOS.SavedTicketsDialog'; Save-Form $d '14-dialogo-tickets-guardados'; Close-Form $d }
    Step '15-dialogo-resumen-cobros' { $d = New-Obj 'EdenPOS.PaymentDateSummaryDialog' @([DateTime]::Today); Save-Form $d '15-dialogo-resumen-cobros'; Close-Form $d }
    Step '16-dialogo-recordatorio-alquiler' { $d = New-Obj 'EdenPOS.RentalReminderDialog'; Save-Form $d '16-dialogo-recordatorio-alquiler'; Close-Form $d }
    Step '17-dialogo-tesoreria' { $d = New-Obj 'EdenPOS.TreasuryDialog' @($openShift); Save-Form $d '17-dialogo-tesoreria'; Close-Form $d }

    # --- Dialogos de la duena
    [EdenPOS.AppSession]::SignOut()
    [EdenPOS.AppSession]::SignIn($owner)
    Step '20-dialogo-producto-nuevo' { $d = New-Obj 'EdenPOS.ProductEditorDialog' @($null, $categories); Save-Form $d '20-dialogo-producto-nuevo'; Close-Form $d }
    Step '20-dialogo-producto-editar' { $d = New-Obj 'EdenPOS.ProductEditorDialog' @($general, $categories); Save-Form $d '20-dialogo-producto-editar'; Close-Form $d }
    Step '21-dialogo-entrada-inventario' {
        $p = $products | Where-Object { $_.TrackInventory } | Select-Object -First 1
        $d = New-Obj 'EdenPOS.InventoryEntryDialog' @($p); Save-Form $d '21-dialogo-entrada-inventario'; Close-Form $d
    }
    Step '22-dialogo-variante-nueva' { $d = New-Obj 'EdenPOS.ProductOptionEditorDialog' @('MARCIANOS', $null); Save-Form $d '22-dialogo-variante-nueva'; Close-Form $d }
    Step '23-dialogo-elegir-variante' {
        if (-not $withOptions) { throw 'La base de capturas no tiene productos con variantes.' }
        $d = New-Obj 'EdenPOS.ProductOptionsDialog' @($withOptions); Save-Form $d '23-dialogo-elegir-variante'; Close-Form $d
    }
    Step '24-dialogo-usuario-nuevo' { $d = New-Obj 'EdenPOS.UserEditorDialog' @($null); Save-Form $d '24-dialogo-usuario-nuevo'; Close-Form $d }
    Step '24-dialogo-usuario-editar' { $d = New-Obj 'EdenPOS.UserEditorDialog' @($worker); Save-Form $d '24-dialogo-usuario-editar'; Close-Form $d }

    [EdenPOS.AppSession]::SignOut()
    Write-Host ("Listo: {0} capturas, {1} errores. Carpeta: {2}" -f $script:made, $script:failed, $OutDir)
}
finally {
    Remove-Item -Recurse -Force $dataPath -ErrorAction SilentlyContinue
    if (-not $KeepDb) {
        try { Invoke-Mysql "DROP DATABASE IF EXISTS $captureDb;" | Out-Null; Write-Host "Base $captureDb eliminada." } catch { Write-Warning $_ }
    } else { Write-Host "Base $captureDb conservada (-KeepDb)." }
}
