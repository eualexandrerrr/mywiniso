<#
  Roda ANTES de formatar, na conta que ainda existe.

    powershell -ExecutionPolicy Bypass -File .\exportar.ps1

  Tira do Chrome o que a formatacao destroi (senhas salvas) e grava CIFRADO em
  D:\Segredos\chrome-<data>.age. A chave privada nunca fica no disco: ela vive no
  pendrive, em dotfiles\chave.txt, e so o destinatario publico entra aqui.

  O texto claro NUNCA toca o disco: a saida do python vai por cano direto para o age,
  pelo cmd.exe. O pipe do PowerShell nao serve aqui, porque ele reencoda o fluxo.
#>
param(
    [string] $Saida = 'D:\Segredos',
    # chave publica do Alexandre; a privada correspondente esta no pendrive
    [string] $Destinatario = 'age1tagd2g2de97059q926qmfrjc33ljvujnp6agmdxcmgdv5k09uc2s4t380x'
)
$ErrorActionPreference = 'Stop'

# O Chrome mantem lock exclusivo nos SQLite; com ele aberto o export sai vazio ou trava.
if (Get-Process chrome -ErrorAction Ignore) {
    Write-Host 'Chrome esta aberto. Fechando para soltar o lock dos bancos.' -ForegroundColor Yellow
    Stop-Process -Name chrome -Force -ErrorAction Ignore
    Start-Sleep -Seconds 2
}

function Achar([string] $Nome) {
    $c = Get-Command $Nome -ErrorAction Ignore
    if ($c -and (Test-Path -LiteralPath $c.Source)) { return $c.Source }
    $p = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "$Nome.exe" -ErrorAction Ignore |
         Select-Object -First 1 -ExpandProperty FullName
    if ($p) { return $p }
    throw "nao achei $Nome"
}

$age    = Achar 'age'
$python = Achar 'python'
$script = Join-Path $PSScriptRoot 'segredos-chrome.py'
if (-not (Test-Path -LiteralPath $script)) { throw "nao achei $script" }

New-Item -ItemType Directory -Path $Saida -Force | Out-Null
$arquivo = Join-Path $Saida ("chrome-{0}.age" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

# cmd.exe e nao o pipe do PowerShell: o cmd passa os bytes intactos.
$linha = '"{0}" "{1}" exportar | "{2}" -r {3} -o "{4}"' -f $python, $script, $age, $Destinatario, $arquivo
cmd.exe /c $linha
if ($LASTEXITCODE -ne 0) { throw "o pipeline saiu com codigo $LASTEXITCODE" }

$tam = (Get-Item -LiteralPath $arquivo).Length
Write-Host ("gravado {0} ({1:n0} bytes), cifrado para {2}" -f $arquivo, $tam, $Destinatario) -ForegroundColor Green
Write-Host 'D: nao e formatado, entao este arquivo atravessa a reinstalacao.' -ForegroundColor Cyan
Write-Host 'Depois de formatar: abra o Chrome uma vez, feche, e rode importar.ps1.' -ForegroundColor Cyan
