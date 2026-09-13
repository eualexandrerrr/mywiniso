<#
  mywiniso: aplica resolução, frequência, orientação e posição dos monitores a partir de monitores.json.

    powershell -NoProfile -ExecutionPolicy Bypass -File monitores.ps1 [-Arquivo monitores.json] [-Conferir]

  Cada monitor do JSON é casado com um monitor ligado pelo nome amigável do EDID (ou pelo código PnP, plano B).
  A aplicação usa ChangeDisplaySettingsEx: primeiro grava o modo de cada monitor no registro sem aplicar
  (CDS_NORESET), marca o primário, e no fim manda o Windows aplicar tudo de uma vez. Assim os dois monitores
  mudam juntos e a posição relativa não passa por estados inválidos.

  -Conferir só mostra o que está ligado agora e sai, sem mexer em nada.
  -Modos lista as resoluções e frequências que o driver de cada monitor aceita, para montar o monitores.json.
#>
param(
    [string] $Arquivo = (Join-Path $PSScriptRoot 'monitores.json'),
    [switch] $Conferir,
    [switch] $Modos
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class MyWinIsoDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]  public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINTL { public int x; public int y; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int   dmFields;
        public POINTL dmPosition;
        public int   dmDisplayOrientation;
        public int   dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int   dmBitsPerPel;
        public int   dmPelsWidth;
        public int   dmPelsHeight;
        public int   dmDisplayFlags;
        public int   dmDisplayFrequency;
        public int   dmICMMethod;
        public int   dmICMIntent;
        public int   dmMediaType;
        public int   dmDitherType;
        public int   dmReserved1;
        public int   dmReserved2;
        public int   dmPanningWidth;
        public int   dmPanningHeight;
    }

    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int EDD_GET_DEVICE_INTERFACE_NAME = 0x00000001;
    public const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x00000001;

    public const int DM_BITSPERPEL = 0x00040000;
    public const int DM_PELSWIDTH  = 0x00080000;
    public const int DM_PELSHEIGHT = 0x00100000;
    public const int DM_DISPLAYFREQUENCY = 0x00400000;
    public const int DM_POSITION   = 0x00000020;
    public const int DM_DISPLAYORIENTATION = 0x00000080;

    public const int CDS_UPDATEREGISTRY = 0x00000001;
    public const int CDS_NORESET    = 0x10000000;
    public const int CDS_SET_PRIMARY = 0x00000010;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, IntPtr lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);

    public static DEVMODE NovoDevMode() {
        DEVMODE d = new DEVMODE();
        d.dmDeviceName = new string(new char[32]);
        d.dmFormName   = new string(new char[32]);
        d.dmSize       = (short)Marshal.SizeOf(typeof(DEVMODE));
        return d;
    }
}
'@

function Get-MonitoresLigados {
    $lista = @()
    for ($i = 0; ; $i++) {
        $ad = New-Object MyWinIsoDisplay+DISPLAY_DEVICE
        $ad.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($ad)
        if (-not [MyWinIsoDisplay]::EnumDisplayDevices([NullString]::Value, $i, [ref] $ad, 0)) { break }
        if (-not ($ad.StateFlags -band [MyWinIsoDisplay]::DISPLAY_DEVICE_ATTACHED_TO_DESKTOP)) { continue }

        $mon = New-Object MyWinIsoDisplay+DISPLAY_DEVICE
        $mon.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($mon)
        [void][MyWinIsoDisplay]::EnumDisplayDevices($ad.DeviceName, 0, [ref] $mon, [MyWinIsoDisplay]::EDD_GET_DEVICE_INTERFACE_NAME)

        $atual = [MyWinIsoDisplay]::NovoDevMode()
        [void][MyWinIsoDisplay]::EnumDisplaySettings($ad.DeviceName, [MyWinIsoDisplay]::ENUM_CURRENT_SETTINGS, [ref] $atual)

        # DeviceID vem como \\?\DISPLAY#AUS27FE#5&abc&UID4353#{guid}; o miolo é o PnP do monitor
        $pnp = ''
        if ($mon.DeviceID -match 'DISPLAY#([^#]+)#([^#]+)#') { $pnp = $Matches[1]; $instancia = "DISPLAY\$($Matches[1])\$($Matches[2])" } else { $instancia = '' }

        $lista += [pscustomobject]@{
            Dispositivo = $ad.DeviceName
            Adaptador   = $ad.DeviceString
            Monitor     = $mon.DeviceString
            Pnp         = $pnp
            Instancia   = $instancia
            Nome        = ''
            Largura     = $atual.dmPelsWidth
            Altura      = $atual.dmPelsHeight
            Hz          = $atual.dmDisplayFrequency
            Orientacao  = $atual.dmDisplayOrientation * 90
            X           = $atual.dmPosition.x
            Y           = $atual.dmPosition.y
        }
    }
    # nome amigável do EDID, quando o WMI responde
    try {
        foreach ($id in Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop) {
            $amigavel = -join ($id.UserFriendlyName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })
            foreach ($m in $lista) {
                if ($m.Instancia -and $id.InstanceName -like "$($m.Instancia)*") { $m.Nome = $amigavel.Trim() }
            }
        }
    } catch {
        # monitor genérico (VM) não responde a WmiMonitorID; sem o nome do EDID o casamento cai no plano B ou C
        if ($Error.Count) { $Error.RemoveAt(0) }
    }
    $lista
}

function Format-Monitor($m) {
    "{0} [{1}] {2}x{3} @ {4} Hz, {5} graus, em {6},{7}" -f `
        $(if ($m.Nome) { $m.Nome } else { $m.Monitor }), $m.Dispositivo, $m.Largura, $m.Altura, $m.Hz, $m.Orientacao, $m.X, $m.Y
}

$ligados = Get-MonitoresLigados
Write-Host "monitores ligados: $($ligados.Count)"
foreach ($m in $ligados) { Write-Host "  - $(Format-Monitor $m)" }

if ($Modos) {
    foreach ($m in $ligados) {
        Write-Host "modos de $(if ($m.Nome) { $m.Nome } else { $m.Monitor }) [$($m.Dispositivo)]:"
        $vistos = @{}
        for ($i = 0; ; $i++) {
            $dm = [MyWinIsoDisplay]::NovoDevMode()
            if (-not [MyWinIsoDisplay]::EnumDisplaySettings($m.Dispositivo, $i, [ref] $dm)) { break }
            if ($dm.dmBitsPerPel -ne 32) { continue }
            $chave = "$($dm.dmPelsWidth)x$($dm.dmPelsHeight)@$($dm.dmDisplayFrequency)"
            if ($vistos.ContainsKey($chave)) { continue }
            $vistos[$chave] = $true
            Write-Host "  $chave Hz"
        }
    }
    exit 0
}

if ($Conferir) { exit 0 }

if (-not (Test-Path -LiteralPath $Arquivo)) { throw "não achei $Arquivo" }
$cfg = Get-Content -LiteralPath $Arquivo -Raw -Encoding UTF8 | ConvertFrom-Json

$erros = 0
$ausentes = 0
$aplicar = @()
# Código de saída: 0 tudo no lugar; 1..99 erro de verdade (o driver recusou o modo); 100+N quando os
# N que faltam só não estão ligados. Quem chama precisa da diferença: monitor desligado é o cabo ou o
# botão do monitor, não uma falha do setup, e não faz sentido sair como FALHOU no resumo por causa disso.
function Codigo { if ($erros) { $erros } elseif ($ausentes) { 100 + $ausentes } else { 0 } }
foreach ($q in $cfg.monitores) {
    $alvo = $ligados | Where-Object { $_.Nome -and $_.Nome -eq $q.nome } | Select-Object -First 1
    if (-not $alvo) { $alvo = $ligados | Where-Object { $_.Pnp -eq $q.pnp } | Select-Object -First 1 }
    # plano C: monitor sem nome no EDID (genérico, VM); casa pelo nome que o driver reporta
    if (-not $alvo) { $alvo = $ligados | Where-Object { $_.Monitor -eq $q.nome } | Select-Object -First 1 }
    if (-not $alvo) {
        Write-Host "  AVISO: '$($q.nome)' ($($q.apelido)) não está ligado; pulando" -ForegroundColor Yellow
        $ausentes++
        continue
    }
    $aplicar += [pscustomobject]@{ Alvo = $alvo; Quer = $q }
}

if ($aplicar.Count -eq 0) {
    # noutra máquina (ou numa VM) nenhum destes monitores existe; isso é aviso, não falha do script
    Write-Host '  nenhum monitor do monitores.json está ligado; nada a aplicar' -ForegroundColor Yellow
    exit (Codigo)
}

# 1) grava o modo de cada monitor sem aplicar; o primário primeiro, para as posições relativas fecharem
foreach ($par in ($aplicar | Sort-Object { -not $_.Quer.primario })) {
    $alvo = $par.Alvo; $q = $par.Quer
    $dm = [MyWinIsoDisplay]::NovoDevMode()
    if (-not [MyWinIsoDisplay]::EnumDisplaySettings($alvo.Dispositivo, [MyWinIsoDisplay]::ENUM_CURRENT_SETTINGS, [ref] $dm)) {
        throw "não consegui ler o modo atual de $($alvo.Dispositivo)"
    }
    $giro = [int]$q.orientacao
    if ($giro -notin 0, 90, 180, 270) { throw "orientação inválida para '$($q.nome)': $giro" }
    $dm.dmDisplayOrientation = $giro / 90
    # com 90 ou 270 graus a largura e a altura entram trocadas
    if ($giro -eq 90 -or $giro -eq 270) { $dm.dmPelsWidth = [int]$q.altura; $dm.dmPelsHeight = [int]$q.largura }
    else                                { $dm.dmPelsWidth = [int]$q.largura; $dm.dmPelsHeight = [int]$q.altura }
    $dm.dmDisplayFrequency = [int]$q.hz
    $dm.dmBitsPerPel = 32
    # POINTL e struct (tipo de valor): "$dm.dmPosition.x = ..." mexe numa COPIA e o $dm continua em 0,0. Foi
    # assim que os dois monitores foram parar em 0,0 e o Windows, desfazendo a sobreposicao, promoveu a LG a
    # principal. Monta-se o ponto numa variavel e so entao se grava o struct inteiro no campo.
    $pos = New-Object MyWinIsoDisplay+POINTL
    $pos.x = [int]$q.x
    $pos.y = [int]$q.y
    $dm.dmPosition = $pos
    $dm.dmFields = [MyWinIsoDisplay]::DM_BITSPERPEL -bor [MyWinIsoDisplay]::DM_PELSWIDTH -bor [MyWinIsoDisplay]::DM_PELSHEIGHT `
        -bor [MyWinIsoDisplay]::DM_DISPLAYFREQUENCY -bor [MyWinIsoDisplay]::DM_POSITION -bor [MyWinIsoDisplay]::DM_DISPLAYORIENTATION

    $flags = [MyWinIsoDisplay]::CDS_UPDATEREGISTRY -bor [MyWinIsoDisplay]::CDS_NORESET
    if ($q.primario) { $flags = $flags -bor [MyWinIsoDisplay]::CDS_SET_PRIMARY }
    $r = [MyWinIsoDisplay]::ChangeDisplaySettingsEx($alvo.Dispositivo, [ref] $dm, [IntPtr]::Zero, $flags, [IntPtr]::Zero)
    $comoFica = "{0}x{1} @ {2} Hz, {3} graus, em {4},{5}" -f $dm.dmPelsWidth, $dm.dmPelsHeight, $dm.dmDisplayFrequency, $giro, $dm.dmPosition.x, $dm.dmPosition.y
    if ($r -eq 0) { Write-Host "  $($q.nome): $comoFica$(if ($q.primario) { ' (primário)' })" }
    else {
        $motivo = switch ($r) { -2 { 'o driver recusou o modo (DISP_CHANGE_BADMODE)' } -1 { 'DISP_CHANGE_RESTART' } -4 { 'DISP_CHANGE_FAILED' } -5 { 'DISP_CHANGE_BADFLAGS' } -6 { 'DISP_CHANGE_BADPARAM' } default { "código $r" } }
        Write-Host "  ERRO em $($q.nome) ($comoFica): $motivo" -ForegroundColor Red
        $erros++
    }
}

# 2) manda aplicar o conjunto de uma vez
$r = [MyWinIsoDisplay]::ChangeDisplaySettingsEx([NullString]::Value, [IntPtr]::Zero, [IntPtr]::Zero, 0, [IntPtr]::Zero)
if ($r -ne 0) { Write-Host "  ERRO ao aplicar o conjunto: código $r" -ForegroundColor Red; $erros++ }

Start-Sleep -Seconds 2
Write-Host 'como ficou:'
foreach ($m in (Get-MonitoresLigados)) { Write-Host "  - $(Format-Monitor $m)" }
exit (Codigo)
