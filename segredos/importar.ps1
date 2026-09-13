<#
  Roda DEPOIS de formatar, com o pendrive espetado.

    powershell -ExecutionPolicy Bypass -File .\importar.ps1

  Decifra o ultimo D:\Segredos\chrome-*.age com a chave privada do pendrive e regrava
  as senhas no perfil novo do Chrome, recifradas com a chave da conta ATUAL.

  Abra o Chrome uma vez antes: os bancos Login Data e Cookies so nascem no primeiro
  arranque. Depois feche, senao o lock exclusivo impede a escrita.
#>
param(
    [string] $Entrada,
    [string] $Chave
)
$ErrorActionPreference = 'Stop'

function Achar([string] $Nome) {
    $c = Get-Command $Nome -ErrorAction Ignore
    if ($c -and (Test-Path -LiteralPath $c.Source)) { return $c.Source }
    $p = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "$Nome.exe" -ErrorAction Ignore |
         Select-Object -First 1 -ExpandProperty FullName
    if ($p) { return $p }
    throw "nao achei $Nome"
}

# A chave privada mora no pendrive; a letra muda de porta para porta, entao procura-se.
if (-not $Chave) {
    foreach ($v in (Get-Volume | Where-Object DriveLetter)) {
        $tentativa = "$($v.DriveLetter):\dotfiles\chave.txt"
        if (Test-Path -LiteralPath $tentativa) { $Chave = $tentativa; break }
    }
}
if (-not $Chave) { throw 'nao achei dotfiles\chave.txt em nenhuma unidade; espete o pendrive' }

if (-not $Entrada) {
    $Entrada = Get-ChildItem 'D:\Segredos\chrome-*.age' -ErrorAction Ignore |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Entrada) { throw 'nao achei D:\Segredos\chrome-*.age' }

if (Get-Process chrome -ErrorAction Ignore) {
    Write-Host 'Chrome esta aberto. Fechando para soltar o lock dos bancos.' -ForegroundColor Yellow
    Stop-Process -Name chrome -Force -ErrorAction Ignore
    Start-Sleep -Seconds 2
}

$age    = Achar 'age'
$python = Achar 'python'
$script = Join-Path $PSScriptRoot 'segredos-chrome.py'

Write-Host "decifrando $Entrada com $Chave" -ForegroundColor Cyan
$linha = '"{0}" -d -i "{1}" "{2}" | "{3}" "{4}" importar' -f $age, $Chave, $Entrada, $python, $script
cmd.exe /c $linha
if ($LASTEXITCODE -ne 0) { throw "o pipeline saiu com codigo $LASTEXITCODE" }
Write-Host 'pronto; abra o Chrome e confira em chrome://password-manager/passwords' -ForegroundColor Green
