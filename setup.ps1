<#
  mywiniso: pós-instalação. Roda como administrador em qualquer Windows 11, não só no instalado pelo pendrive.

    irm https://raw.githubusercontent.com/eualexandrerrr/MyWinISO/main/setup.ps1 | iex

  Senha: o primeiro-logon.ps1 recebe a senha da conta (injetada pelo pendrive.ps1 -Senha) e repassa em
  $env:MYWINISO_SENHA; aqui ela vira a senha do root do MariaDB. Sem senha, o root fica sem senha e só local.

  O console mostra cada etapa como [n/28], o que ela está fazendo e, no fim dela, OK, AVISO (erros não fatais,
  listados) ou ERRO (a etapa parou; a mensagem aparece). Nenhuma etapa derruba as seguintes. No final sai um
  resumo de todas as etapas e dos programas que falharam. Tudo vai também para ~\mywiniso-setup.log.

  O Claude Code vem na etapa 4, antes de tudo que é longo: com ele na mão dá para consertar o que der
  errado nas etapas seguintes sem esperar o resto. Depois, as etapas 5 a 12 são as que mudam o que se
  vê (driver, monitores, tema, wallpaper, barra), e só então vêm os programas, que sozinhos levam uns
  treze minutos. Em uns cinco minutos a máquina já está na cara certa e o resto instala por baixo.

   1. ponto de restauração antes de mexer    15. Lightshot: só Shift+PrintScreen
   2. garante que o winget funciona          16. Chrome (Proton Pass) e Discord (Vencord do fork)
   3. Git e clone em ~\Projetos\MyWinISO     17. Jogos: RedM e biblioteca do Steam em D:
   4. Claude Code (CLI)                      18. git config
   5. driver de vídeo, direto da NVIDIA      19. Office
   6. monitores: resolução, Hz e posição     20. Área de Trabalho Remota e política de senha
   7. preferências do usuário (tema escuro)  21. NVIDIA App (instalador silencioso)
   8. wallpaper, um por monitor              22. MariaDB: serviço e root
   9. foto do perfil                         23. fontes, console e VS Code
  10. Explorer em Detalhes (WinSetView)      24. um perfil só para todo PowerShell
  11. Windhawk: tema Translucent             25. barra de tarefas e tarefa de logon
  12. energia: tela apaga em 5 min           26. Windows Update (resto dos drivers)
  13. programas do apps.json, um a um        27. Windows Terminal como terminal único
  14. Claude Code: MCPs, plugins e skills    28. manutenção: limpeza e telemetria

  -So 'nome da etapa'[,'outra']: roda só essas (as outras saem como puladas, com a numeração de sempre) e não
  arma reinício. Para testar uma etapa sem esperar as 28.

  -Perfil vm-jogo: a VM de passthrough onde só rodam RedM, Steam e Red Dead 2. Mesmo Windows enxuto,
  sem nada de trabalho: 13 das 28 etapas, e o apps-vm.json no lugar do apps.json. Ao contrário do -So,
  é instalação de verdade -- reinicia e retoma como sempre.

  A etapa 8 termina esperando o Explorer gravar o TranscodedImageCache. Sem essa espera, o reinício do
  Explorer na etapa 10 desfaz a atribuição de wallpaper por monitor e o monitor em pé perde a imagem
  dele. Com ela, sobrevive. Medido, não suposto.
#>
param(
    [string] $Senha = $env:MYWINISO_SENHA,
    [string[]] $So = $(if ($env:MYWINISO_SO) { $env:MYWINISO_SO -split ';' }),
    [ValidateSet('completo', 'vm-jogo')] [string] $Perfil = $(if ($env:MYWINISO_PERFIL) { $env:MYWINISO_PERFIL } else { 'completo' })
)

# Este arquivo é UTF-8 sem BOM: com BOM, "irm | iex" no Windows PowerShell engasga no primeiro caractere. Só que
# sem BOM o Windows PowerShell lê .ps1 pelo -File (ou por &) como ANSI e os acentos viram "Ã¡". Se o texto chegou
# aqui assim, relê o próprio arquivo como UTF-8 e roda de novo, passando a pasta e a senha por variáveis de ambiente.
# Regra para quem edita: fora de comentário, nada de Ó Ô Â Ä Ñ Ò, travessão, seta, cifrão de euro ou emoji dentro de
# strings; lidos como ANSI esses caracteres viram aspas curvas e o arquivo nem chega a rodar.
if ($PSCommandPath -and 'á'.Length -ne 1) {
    $env:MYWINISO_SENHA = $Senha
    $env:MYWINISO_RAIZ  = $PSScriptRoot
    $env:MYWINISO_SO    = ($So -join ';')   # a releitura não repassa parâmetros
    $env:MYWINISO_PERFIL = $Perfil
    # dot-source, não &: com & o bloco roda em escopo filho e $script:Resultado/$script:Falhas das funções ficam nulos
    . ([scriptblock]::Create([System.IO.File]::ReadAllText($PSCommandPath, [System.Text.Encoding]::UTF8)))
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try { $Host.UI.RawUI.WindowTitle = 'mywiniso: setup' } catch { }

# ---------------------------------------------------------------------------------------------------
# Pulso: nada aqui pode parecer travado. Enquanto uma operacao longa nao imprime nada (winget baixando,
# driver instalando, Office), uma thread a parte escreve uma linha a cada 10 s de silencio dizendo
# em que etapa esta, ha quanto tempo e que horas sao. O Write-Host abaixo e um proxy do cmdlet real: ele
# so marca a hora da ultima saida e repassa, entao qualquer linha impressa por qualquer parte do script
# ja conta como sinal de vida sem precisar mudar nenhuma chamada.
# ---------------------------------------------------------------------------------------------------
# $global: e nao $script:. O proxy do Write-Host logo abaixo tambem e chamado de dentro dos .ps1 filhos
# (& $mon na etapa 6, & $PerfilNoD nas 7/13/28, o WinSetView na 10), e ali $script: resolve o escopo
# DAQUELE arquivo, onde Pulso nao existe: $script:Pulso virava $null e a atribuicao morria com "a
# propriedade 'Ultimo' nao foi encontrada neste objeto", derrubando a etapa inteira em ERRO.
$global:Pulso = [hashtable]::Synchronized(@{ Nome = 'iniciando'; Desde = Get-Date; Ultimo = Get-Date; Ligado = $true })

function Write-Host {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromRemainingArguments)] [object[]] $Object,
        [switch] $NoNewline,
        [object] $Separator,
        [System.ConsoleColor] $ForegroundColor,
        [System.ConsoleColor] $BackgroundColor
    )
    process {
        if ($global:Pulso) { $global:Pulso.Ultimo = Get-Date }
        Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
    }
}

$PulsoPS = $null
try {
    $espaco = [runspacefactory]::CreateRunspace()
    $espaco.Open()
    $PulsoPS = [powershell]::Create()
    $PulsoPS.Runspace = $espaco
    [void]$PulsoPS.AddScript({
        param($P)
        # o proxy do Write-Host so ve o que o script imprime. Programa nativo (git, winget, dism) escreve
        # direto no console, e sem isto o pulso acha que esta tudo em silencio e fala por cima. A posicao
        # do cursor mudando e a prova de que alguem escreveu, inclusive o \r do progresso do git.
        $ondeEstava = ''
        while ($P.Ligado) {
            Start-Sleep -Milliseconds 500
            try {
                $agora = Get-Date
                $onde = "$([Console]::CursorTop),$([Console]::CursorLeft)"
                if ($onde -ne $ondeEstava) { $ondeEstava = $onde; $P.Ultimo = $agora; continue }
                if (($agora - $P.Ultimo).TotalSeconds -ge 10) {
                    $P.Ultimo = $agora
                    [Console]::WriteLine(("     ... {0} | {1} s nesta etapa | {2}" -f $P.Nome, [int]($agora - $P.Desde).TotalSeconds, $agora.ToString('HH:mm:ss')))
                    $ondeEstava = "$([Console]::CursorTop),$([Console]::CursorLeft)"
                }
            } catch { }
        }
    }).AddArgument($Pulso)
    [void]$PulsoPS.BeginInvoke()
} catch { $Pulso.Ligado = $false }

$Repo = 'https://github.com/eualexandrerrr/MyWinISO'
# Disco de dados. O instala.vbs cria uma partição "Files" (rótulo) no fim do disco que sobrevive à formatação, e é
# nela que mora o que é seu: os jogos e a pasta Downloads. Projetos não: essa
# pasta o Alexandre monta na mão depois, e este clone continua em ~\Projetos no C:. Aqui só se garante a
# letra D: (no primeiro boot o Windows pode ter dado D: ao pendrive Ventoy). Num Windows sem essa
# partição, o setup roda em qualquer Windows 11, tudo fica nas pastas de sempre no C:.
$Dados = $null
try {
    $volDados = @(Get-Volume -FileSystemLabel 'Files' -ErrorAction Ignore | Where-Object DriveType -eq 'Fixed')[0]
    if ($volDados) {
        if ($volDados.DriveLetter -ne 'D') {
            if (Get-Volume -DriveLetter D -ErrorAction Ignore) {
                # quem estiver em D: vai para a última letra livre, de Z para trás
                $livre = @([char[]](90..69) | Where-Object { -not (Get-Volume -DriveLetter $_ -ErrorAction Ignore) })[0]
                Get-Partition -DriveLetter D | Set-Partition -NewDriveLetter $livre
            }
            $volDados | Get-Partition | Set-Partition -NewDriveLetter D
        }
        $Dados = 'D:\'
        Write-Host ("disco de dados: D: (rótulo Alexandre, {0:n0} GB)" -f ($volDados.Size / 1GB))
    } else { Write-Host 'sem partição "Files": pastas do usuário e jogos ficam no C:' }
} catch { Write-Host "disco de dados: não consegui deixar em D: ($($_.Exception.Message)); seguindo sem" -ForegroundColor Yellow }
$Dir  = Join-Path $env:USERPROFILE 'Projetos\MyWinISO'
$Log  = Join-Path $env:USERPROFILE 'mywiniso-setup.log'
$desktop = [Environment]::GetFolderPath('Desktop')     # usado pela etapa de preferências (ícone do Edge) e pela do RedM
try { Start-Transcript -Path $Log -Append | Out-Null } catch { }

# ---------------------------------------------------------------------------------------------------
# Console: Etapa envolve cada bloco; Passo é uma linha do que está acontecendo; Falha registra item que
# falhou sem parar a etapa. Erro terminante = ERRO; erro não terminante que sobrou em $Error = AVISO.
# ---------------------------------------------------------------------------------------------------
$global:TotalEtapas = 28
# -So e para depurar: roda só as etapas escolhidas e não mexe em reinício nem no contador de
# retomadas. -Perfil escolhe um conjunto de etapas, mas é uma instalação de verdade -- reinicia e
# retoma como sempre. Os dois usam a mesma engrenagem de "pular etapa"; só o efeito colateral muda.
$global:Depurando   = [bool]$So

# vm-jogo: a VM de passthrough onde só rodam RedM, Steam e Red Dead 2. Mesmo Windows enxuto de
# sempre -- telemetria fora, energia sem suspender, Explorer arrumado --, mas sem nada de trabalho:
# sai Office, VS Code, MariaDB, Claude Code, Chrome, Discord, Proton Pass, fontes de código, perfil
# do PowerShell e Windows Terminal. Fica o que um PC de jogo precisa: driver de vídeo, monitores,
# energia, Steam, RedM, barra de tarefas e a manutenção que mantém a VM leve.
# Ponto de restauração sai porque a VM já tem instantâneo do hipervisor, que é melhor e mais rápido.
$PERFIS = @{
    'vm-jogo' = @(
        'winget'
        'Git e clone do repositório'
        'Driver de vídeo (NVIDIA)'
        'Monitores (resolução, Hz, posição)'
        'Preferências do usuário'
        'Energia'
        'Programas (apps.json)'
        'Jogos: RedM e biblioteca do Steam'
        'Área de Trabalho Remota e contas'
        'NVIDIA App'
        'Barra de tarefas e tarefa de logon'
        'Windows Update (drivers)'
        'Manutenção e telemetria de fundo'
    )
}
if ($Perfil -ne 'completo' -and -not $So) { $So = $PERFIS[$Perfil] }
# O apps.json enxuto do perfil: só o que um jogo precisa (VCRedist, DirectX e Steam).
$AppsArquivo = if ($Perfil -eq 'vm-jogo') { 'apps-vm.json' } else { 'apps.json' }
$global:So          = $So
$global:NumEtapa    = 0
$global:Resultado   = New-Object System.Collections.Generic.List[object]
$global:Falhas      = New-Object System.Collections.Generic.List[string]
# Qualquer etapa que perceba que o Windows precisa reiniciar liga isto; quem trata é o fim do arquivo.
$global:PedeReinicio = $false

function Passo([string] $m) { Write-Host "  - $m" -ForegroundColor Gray }
function Falha([string] $m) { Write-Host "  FALHOU: $m" -ForegroundColor Red; $global:Falhas.Add($m) }
function Etapa([string] $Nome, [scriptblock] $Corpo) {
    $global:NumEtapa++
    if ($global:So -and $global:So -notcontains $Nome) {
        Write-Host ("[{0}/{1}] {2} | pulada (-So)" -f $global:NumEtapa, $global:TotalEtapas, $Nome) -ForegroundColor DarkGray
        return
    }
    $global:Pulso.Nome  = "[$($global:NumEtapa)/$($global:TotalEtapas)] $Nome"
    $global:Pulso.Desde = Get-Date
    Write-Host ''
    Write-Host ("[{0}/{1}] {2} | {3}" -f $global:NumEtapa, $global:TotalEtapas, $Nome, (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Cyan
    $antes  = $Error.Count
    $sw     = [System.Diagnostics.Stopwatch]::StartNew()
    $estado = 'OK'
    $detalhe = ''
    try {
        & $Corpo
    } catch {
        $estado  = 'ERRO'
        $detalhe = $_.Exception.Message
        Write-Host "  ERRO: $detalhe" -ForegroundColor Red
    }
    $novos = $Error.Count - $antes
    if ($estado -eq 'OK' -and $novos -gt 0) {
        $estado = 'AVISO'
        $msgs = @(0..($novos - 1) | ForEach-Object { $Error[$_].Exception.Message })
        $detalhe = $msgs -join ' | '
        Write-Host "  AVISO: $novos erro(s) não fatal(is):" -ForegroundColor Yellow
        $msgs | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    }
    $sw.Stop()
    $cor = @{ OK = 'Green'; AVISO = 'Yellow'; ERRO = 'Red' }[$estado]
    Write-Host ("  {0} em {1:n0} s" -f $estado, $sw.Elapsed.TotalSeconds) -ForegroundColor $cor
    $global:Resultado.Add([pscustomobject]@{ Etapa = $Nome; Estado = $estado; Segundos = [int]$sw.Elapsed.TotalSeconds; Detalhe = $detalhe })
}
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Set-Reg([string] $Path, [string] $Name, $Value, [string] $Type = 'DWord') {
    # tolerante: valor protegido (TaskbarDa depois de o pacote Widgets sair, por exemplo) entra na lista de falhas
    # com nome e motivo, em vez de sujar $Error e virar um AVISO sem contexto no fim da etapa
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
    } catch {
        Falha ("registro {0}\{1}: {2}" -f ($Path -replace '^HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\', 'HKCU:...\'), $Name, $_.Exception.Message)
    }
}
function Baixar([string] $Url, [string] $Destino) {
    # Download por stream, e nao Invoke-WebRequest -OutFile, para poder mostrar de onde vem, quanto tem e
    # quanto ja veio. Sem isso um arquivo de 600 MB e uma janela parada por minutos sem nenhuma prova de
    # que a rede esta trabalhando.
    $uri = [uri]$Url
    Passo "baixando de $($uri.Host): $($uri.AbsolutePath.TrimStart('/'))"
    $req = [System.Net.HttpWebRequest]::Create($uri)
    $req.UserAgent = 'Mozilla/5.0'
    $req.Timeout = 60000
    $req.ReadWriteTimeout = 120000
    $resp = $req.GetResponse()
    $total = $resp.ContentLength
    Passo ("HTTP {0} | servidor {1} | {2}" -f [int]$resp.StatusCode, $(if ($resp.Headers['Server']) { $resp.Headers['Server'] } else { 'sem cabecalho Server' }), $(if ($total -gt 0) { '{0:n1} MB' -f ($total / 1MB) } else { 'tamanho nao informado' }))
    $entrada = $resp.GetResponseStream()
    $saida   = [System.IO.File]::Create($Destino)
    $buffer  = New-Object byte[] 262144
    $lidos   = 0L
    $marco   = 0
    $sw      = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        while (($n = $entrada.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $saida.Write($buffer, 0, $n)
            $lidos += $n
            $seg = [math]::Max($sw.Elapsed.TotalSeconds, 0.1)
            if ($total -gt 0) {
                $pct = [int](100 * $lidos / $total)
                if ($pct -ge $marco + 10) {
                    $marco = $pct - ($pct % 10)
                    Passo ("  {0}% | {1:n1} de {2:n1} MB | {3:n1} MB/s" -f $pct, ($lidos / 1MB), ($total / 1MB), ($lidos / 1MB / $seg))
                }
            } elseif (($lidos / 1MB) -ge $marco + 10) {
                $marco = [int]($lidos / 1MB)
                Passo ("  {0:n1} MB | {1:n1} MB/s" -f ($lidos / 1MB), ($lidos / 1MB / $seg))
            }
        }
    } finally {
        $saida.Close(); $entrada.Close(); $resp.Close(); $sw.Stop()
    }
    Passo ("pronto: {0:n1} MB em {1:n0} s -> {2}" -f ((Get-Item -LiteralPath $Destino).Length / 1MB), $sw.Elapsed.TotalSeconds, $Destino)
}
function Silencioso([scriptblock] $Corpo) {
    # Roda o bloco e apaga o que ele deixou em $Error. É para comando que escreve em stderr sem ter falhado:
    # o wsl.exe antes do primeiro reinício, o Set-PSRepository do PowerShellGet 5.1. O Windows PowerShell
    # transforma cada linha de stderr de programa nativo em registro de erro, e sem isto a Etapa conta essas
    # linhas como erro não fatal e fecha em AVISO sem nada de errado ter acontecido.
    $antes = $Error.Count
    try { & $Corpo } catch { }
    while ($Error.Count -gt $antes) { $Error.RemoveAt(0) }
}
function Junction([string] $Alvo, [string] $Destino) {
    # $Alvo (no C:) vira uma junção para $Destino (em D:), e todo programa continua lendo e gravando no caminho
    # de sempre sem saber que está em D:. Conteúdo: se só o C: tem, vai para D:; se os dois têm, o de D: manda
    # (é o que sobreviveu à formatação) e o de C: vai para <nome>.antigo; se nenhum tem, D: nasce vazio.
    # Junção e não symlink: dispensa privilégio e todo programa a enxerga como pasta comum. Devolve o que fez.
    $item = Get-Item -LiteralPath $Alvo -ErrorAction Ignore
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return 'já era junção' }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destino), (Split-Path -Parent $Alvo) -Force | Out-Null
    if ($item) {
        if (Test-Path -LiteralPath $Destino) {
            Remove-Item -LiteralPath "$Alvo.antigo" -Recurse -Force -ErrorAction Ignore
            Move-Item -LiteralPath $Alvo -Destination "$Alvo.antigo" -Force
            $como = 'D: manda; o que havia no C: ficou em .antigo'
        } else {
            Move-Item -LiteralPath $Alvo -Destination $Destino -Force
            $como = 'o conteúdo do C: foi para D:'
        }
    } else {
        New-Item -ItemType Directory -Path $Destino -Force | Out-Null
        $como = if ((Get-ChildItem -LiteralPath $Destino -Force | Measure-Object).Count) { 'voltou de D:' } else { 'novo, vazio' }
    }
    New-Item -ItemType Junction -Path $Alvo -Target $Destino -ErrorAction Stop | Out-Null
    return $como
}
function Invoke-SemElevacao([string] $Exe, [string] $Argumentos, [int] $TimeoutSeg = 1800) {
    # Alguns instaladores recusam rodar como administrador e o winget devolve 0x8A150056 (o do Spotify faz
    # isso). O setup todo roda elevado, então o jeito de chamar um deles é por uma tarefa agendada com
    # RunLevel Limited, que nasce no nível médio de integridade do próprio usuário. Devolve o código de saída.
    $nome  = 'mywiniso-sem-elevacao'
    # com a barra no fim: o Agendador guarda a tarefa em '\mywiniso\', e o Get-ScheduledTask consulta o
    # TaskPath por igualdade. Sem a barra ele não acha a tarefa que ele mesmo acabou de registrar, os dois
    # laços abaixo saem na hora e o LastTaskResult volta nulo.
    $pasta = '\mywiniso\'
    $config    = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::FromSeconds($TimeoutSeg)) -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $nome -TaskPath $pasta -Force -Settings $config -Principal $principal `
        -Action (New-ScheduledTaskAction -Execute $Exe -Argument $Argumentos) | Out-Null
    try {
        $antes = (Get-ScheduledTaskInfo -TaskName $nome -TaskPath $pasta).LastRunTime
        Start-ScheduledTask -TaskName $nome -TaskPath $pasta
        # espera começar. A saída pelo LastRunTime é para a tarefa curta, que pode terminar antes de o
        # primeiro Get-ScheduledTask acontecer e portanto nunca ser vista em Running.
        $limite = (Get-Date).AddSeconds(60)
        while ((Get-ScheduledTask -TaskName $nome -TaskPath $pasta).State -ne 'Running' -and
               (Get-ScheduledTaskInfo -TaskName $nome -TaskPath $pasta).LastRunTime -eq $antes -and
               (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 500 }
        # espera terminar
        $limite = (Get-Date).AddSeconds($TimeoutSeg)
        while ((Get-ScheduledTask -TaskName $nome -TaskPath $pasta).State -eq 'Running' -and (Get-Date) -lt $limite) {
            Start-Sleep -Seconds 3
        }
        return (Get-ScheduledTaskInfo -TaskName $nome -TaskPath $pasta).LastTaskResult
    } finally { Unregister-ScheduledTask -TaskName $nome -TaskPath $pasta -Confirm:$false -ErrorAction Ignore }
}

$eu = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $eu.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Rode como administrador.'
}
Write-Host "mywiniso setup | $(Get-Date -Format 'dd/MM/yyyy HH:mm') | usuário $env:USERNAME | senha: $(if ($Senha) { 'sim' } else { 'não' })$(if ($Perfil -ne 'completo') { " | perfil: $Perfil" }) | log: $Log"

# --- 1. Ponto de restauração antes de mexer em qualquer coisa ----------------------------------------
# O setup grava mais de cem valores de registro. Um ponto de restauração é a única forma barata de voltar
# atrás se algo sair errado. O Sophia Script e o WinUtil fazem isso como primeira ação, e por isso está aqui.
Etapa 'Ponto de restauração' {
    $sr = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
    Set-Reg $sr 'SystemRestorePointCreationFrequency' 0      # sem o limite de um ponto a cada 24 h
    Passo 'criando o ponto (pode levar um minuto)'
    Checkpoint-Computer -Description 'mywiniso: antes do setup' -RestorePointType MODIFY_SETTINGS
    Set-Reg $sr 'SystemRestorePointCreationFrequency' 1440   # volta ao padrão
    $ponto = Get-ComputerRestorePoint -ErrorAction Ignore | Select-Object -Last 1
    if ($ponto) { Passo "ponto $($ponto.SequenceNumber): $($ponto.Description)" }
}

# --- 2. winget --------------------------------------------------------------------------------------
# A ISO traz um App Installer velho (1.9 na 25H2) que não fala mais com a fonte msstore (certificado, 0x8a15005e)
# e faz qualquer "winget install" sem --source parar pedindo para escolher fonte. Então, além de garantir que o
# winget existe, esta etapa o troca pelo release atual do GitHub quando ele estiver mais de uma versão atrás.
function Test-Winget { [bool](Get-Command winget.exe -ErrorAction Ignore) }
function Get-WingetVersao {
    try {
        $txt = @(winget.exe --version 2>$null | Where-Object { $_ -match '\d+\.\d+' })[-1]
        [version](($txt -replace '^\s*v', '' -replace '-.*$', '').Trim())
    } catch { [version]'0.0' }
}
function Update-Winget {
    $rel   = Invoke-RestMethod -UseBasicParsing -UserAgent 'mywiniso' -TimeoutSec 30 -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    $alvo  = [version]($rel.tag_name -replace '^v', '' -replace '-.*$', '')
    $atual = if (Test-Winget) { Get-WingetVersao } else { [version]'0.0' }
    if ($atual.Major -gt $alvo.Major -or ($atual.Major -eq $alvo.Major -and $atual.Minor -ge ($alvo.Minor - 1))) {
        Passo "winget $atual está em dia (release atual: $alvo)"
        return
    }
    Passo "winget $atual é antigo; instalando o $alvo do GitHub (microsoft/winget-cli, release $($rel.tag_name) de $([datetime]$rel.published_at | Get-Date -Format 'dd/MM/yyyy'))"
    $bundle = @($rel.assets | Where-Object { $_.name -like '*.msixbundle' })[0]
    $deps   = @($rel.assets | Where-Object { $_.name -eq 'DesktopAppInstaller_Dependencies.zip' })[0]
    if (-not $bundle -or -not $deps) { throw "release $($rel.tag_name) sem msixbundle ou sem DesktopAppInstaller_Dependencies.zip" }
    $tmp = Join-Path $env:TEMP 'mywiniso-winget'
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction Ignore
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    Baixar $bundle.browser_download_url (Join-Path $tmp $bundle.name)
    Baixar $deps.browser_download_url (Join-Path $tmp 'deps.zip')
    Expand-Archive -Path (Join-Path $tmp 'deps.zip') -DestinationPath (Join-Path $tmp 'deps') -Force
    $appx = @(Get-ChildItem -Path (Join-Path $tmp 'deps\x64') -Filter '*.appx' | Select-Object -ExpandProperty FullName)
    Passo "Add-AppxPackage $($bundle.name) com $($appx.Count) dependências: $(($appx | Split-Path -Leaf) -join ', ')"
    # -ErrorAction Stop: o erro real vira exceção aqui em vez de só AVISO; 3 tentativas porque no primeiro logon a Loja
    # e o AppReadiness podem estar mexendo no mesmo pacote
    for ($t = 1; $t -le 3; $t++) {
        try { Add-AppxPackage -Path (Join-Path $tmp $bundle.name) -DependencyPath $appx -ForceApplicationShutdown -ErrorAction Stop; break }
        catch { if ($t -eq 3) { throw }; Passo "Add-AppxPackage falhou (tentativa $t/3): $($_.Exception.Message); de novo em 20 s"; Start-Sleep -Seconds 20 }
    }
    Refresh-Path
    for ($i = 0; $i -lt 10 -and (Get-WingetVersao) -lt $alvo; $i++) { Start-Sleep -Seconds 3 }   # o alias winget.exe leva uns segundos para apontar para o novo
    $agora = Get-WingetVersao
    if ($agora -lt $alvo) { throw "instalei o $alvo mas 'winget --version' ainda responde $agora" }
    Passo "winget agora é $agora"
}
Etapa 'winget' {
    if (-not (Test-Winget)) {
        Passo 'winget não responde; registrando o App Installer'
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Ignore
        Refresh-Path
    }
    try { Update-Winget } catch { Falha "atualização do winget: $($_.Exception.Message)" }
    if (-not (Test-Winget)) {
        Passo 'ainda não; instalando pelo módulo Microsoft.WinGet.Client (demora uns minutos)'
        Install-PackageProvider -Name NuGet -Force -Scope AllUsers | Out-Null
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Install-Module -Name Microsoft.WinGet.Client -Force -Scope AllUsers
        Repair-WinGetPackageManager -AllUsers -Latest -Force
        Refresh-Path
    }
    if (-not (Test-Winget)) { throw 'winget não ficou disponível. Abra a Microsoft Store, atualize o "Instalador de Aplicativo" e rode de novo.' }
    Passo "winget $(Get-WingetVersao)"
    winget.exe source update --disable-interactivity | Out-Null
}

# --- 3. Git e clone ----------------------------------------------------------------------------------
# Rodando pelo irm/-File (sem apps.json ao lado): instala o Git, clona o repositório e continua pela cópia clonada.
# Se o Git não entrar, baixa o repositório como zip, para que o resto do setup não dependa dele; o Git é tentado
# de novo na etapa 3, porque está no apps.json.
$aqui = if ($PSScriptRoot) { $PSScriptRoot } elseif ($env:MYWINISO_RAIZ) { $env:MYWINISO_RAIZ } else { '' }
# vazio quando o setup vem pelo irm, que nao tem PSScriptRoot: ai esta instancia so clona e passa o
# bastao, e quem usa o caminho e a copia local. Join-Path com string vazia lanca.
$PerfilNoD = if ($aqui) { Join-Path $aqui 'manutencao\perfil.ps1' } else { '' }   # regra que leva o perfil de todo programa para D: (etapas 7, 13 e 28)
if (-not ($aqui -and (Test-Path -LiteralPath (Join-Path $aqui 'apps.json')))) {
    Etapa 'Git e clone do repositório' {
        if (-not (Get-Command git.exe -ErrorAction Ignore)) {
            if (Test-Winget) {
                Passo 'instalando Git (winget, fonte winget)'
                winget.exe install --id Git.Git --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
                if ($LASTEXITCODE -ne 0) { Falha ("Git.Git: winget saiu com código {0} (0x{0:X8})" -f $LASTEXITCODE) }
                Refresh-Path
            } else { Passo 'sem winget; o Git fica para a etapa 3 e o repositório vem pelo zip' }
        }
        if (Get-Command git.exe -ErrorAction Ignore) {
            if (Test-Path -LiteralPath (Join-Path $Dir '.git')) {
                Passo "git pull em $Dir"
                git.exe -C $Dir pull --ff-only
            } else {
                if (Test-Path -LiteralPath $Dir) { Passo "$Dir existe sem .git (veio do zip); trocando pelo clone"; Remove-Item -LiteralPath $Dir -Recurse -Force }
                Passo "git clone $Repo -> $Dir"
                New-Item -ItemType Directory -Path (Split-Path -Parent $Dir) -Force | Out-Null
                # --progress sem 2>&1: o git escreve progresso em stderr e, redirecionado, cada linha vira
                # registro de erro no PowerShell 5.1 (a etapa fecha em AVISO com centenas de erros falsos).
                # Direto no console ele sai em cor normal e sobrescreve a mesma linha, como no terminal.
                git.exe clone --progress $Repo $Dir
            }
            if (Test-Path -LiteralPath (Join-Path $Dir '.git')) {
                Passo ("no commit " + (git.exe -C $Dir log -1 --format='%h %ad %s' --date=format:'%d/%m/%Y %H:%M'))
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $Dir 'apps.json'))) {
            Passo 'sem Git ou sem clone; baixando o repositório como zip'
            $zip = Join-Path $env:TEMP 'mywiniso-main.zip'
            $tmp = Join-Path $env:TEMP 'mywiniso-main'
            Remove-Item -LiteralPath $zip, $tmp -Recurse -Force -ErrorAction Ignore
            Baixar "$Repo/archive/refs/heads/main.zip" $zip
            Expand-Archive -Path $zip -DestinationPath $tmp -Force
            New-Item -ItemType Directory -Path (Split-Path -Parent $Dir) -Force | Out-Null
            Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction Ignore
            if (Test-Path -LiteralPath $Dir) {
                Passo "$Dir não pôde ser apagado (pasta aberta em algum terminal ou arquivo em uso); copiando por cima"
                Copy-Item -Path (Join-Path $tmp 'mywiniso-main\*') -Destination $Dir -Recurse -Force
            } else {
                Move-Item -LiteralPath (Join-Path $tmp 'mywiniso-main') -Destination $Dir
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $Dir 'apps.json'))) { throw "não consegui obter $Repo em $Dir" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Dir 'setup.ps1')) -or -not (Test-Path -LiteralPath (Join-Path $Dir 'apps.json'))) {
        Write-Host "Sem setup.ps1 e apps.json em $Dir não dá para continuar. Veja o erro acima; com internet, rode mywiniso-setup.cmd de novo." -ForegroundColor Red
        try { Stop-Transcript | Out-Null } catch { }
        exit 1
    }
    Passo "continuando pela cópia em $Dir, que tem os arquivos ao lado"
    # o pulso morre aqui: daqui pra frente quem fala e a copia local, com o pulso dela. Sem isto os dois
    # ficam escrevendo no mesmo console e este, parado no bastao, repete a etapa 3 ate o fim de tudo.
    $Pulso.Ligado = $false
    if ($PulsoPS) { try { $PulsoPS.Runspace.Close() } catch { } }
    try { Stop-Transcript | Out-Null } catch { }
    & (Join-Path $Dir 'setup.ps1') -Senha $Senha
    exit $LASTEXITCODE
}
Etapa 'Git e clone do repositório' {
    Passo "rodando de $aqui"
    if ((Get-Command git.exe -ErrorAction Ignore) -and (Test-Path -LiteralPath (Join-Path $aqui '.git'))) {
        # -q e sem 2>&1: no Windows PowerShell 5.1 cada linha de stderr redirecionada do git entraria em $Error e a etapa sairia como AVISO
        git.exe -C $aqui pull --ff-only -q
        if ($LASTEXITCODE -ne 0) { Falha "git pull em $aqui saiu com código $LASTEXITCODE" }
        Passo "commit: $(git.exe -C $aqui log -1 --format='%h %s')"
    } else { Passo 'cópia sem .git ou sem Git; nada a atualizar' }
}

# --- 4. Claude Code (CLI) -------------------------------------------------------------------------
# Cedo de propósito: com o Claude na mão dá para consertar o que der errado nas etapas seguintes sem
# esperar os treze minutos da instalação dos programas. Custa uns 30 s, então não atrasa o driver e os
# monitores de forma sentida. Não está mais no apps.json, justamente para não instalar duas vezes.
Etapa 'Claude Code (CLI)' {
    winget.exe install --id Anthropic.ClaudeCode --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { throw "winget não instalou o Claude Code (código $LASTEXITCODE)" }
    Refresh-Path
    $exe = Get-Command claude -ErrorAction Ignore
    if ($exe) { Passo "claude em $($exe.Source)" } else { Falha 'o claude não aparece no PATH; abra um terminal novo e rode "claude --version"' }
}

# --- 5. Driver de vídeo da NVIDIA, direto da NVIDIA --------------------------------------------------
# Primeira coisa que o setup faz depois de ter o repositório na mão, e de propósito: sem o driver da placa
# o Windows fica no adaptador básico da Microsoft, numa resolução baixa, e a etapa dos monitores não tem
# como pedir 1440p a 180 Hz nem girar a LG. O Windows Update também traz o driver, mas só na etapa 26 e
# sempre atrasado (o que ele entregou nesta máquina tinha oito meses). Aqui o driver vem da própria NVIDIA,
# pela mesma API que a página de download usa, e é o mais novo que existe.
#   psid = série da placa, pfid = modelo dentro da série. A NVIDIA não expõe mais o lookup desses dois
#   (o endpoint lookupValueSearch responde 404), então ficam nesta tabela; placa que não estiver aqui cai
#   no Windows Update da etapa 26, que é lento mas funciona sozinho.
#   dev = o DEV_xxxx do ID de hardware PCI, para achar a placa quando ela ainda está sem driver e o
#   Win32_VideoController a mostra como "Microsoft Basic Display Adapter".
$NvidiaProdutos = @{
    'RTX 3090' = @{ psid = 120; pfid = 934; dev = '2204' }
}
Etapa 'Driver de vídeo (NVIDIA)' {
    # Logo depois da formatação a placa costuma estar SEM driver: o Win32_VideoController a mostra como
    # "Microsoft Basic Display Adapter" e o -match 'NVIDIA' falha, embora a placa esteja no barramento.
    # Foi o que aconteceu em 12/09/2026: a etapa saiu aqui, os monitores ficaram no adaptador básico e
    # recusaram 1440p a 180 Hz. Por isso a detecção tem dois caminhos e espera o PCI terminar de enumerar:
    # primeiro pelo nome (driver já presente); se não achar, pelo hardware (VEN_10DE na classe Display),
    # mapeando o DEV_xxxx para a placa. Sem versão instalada, o resto trata como desatualizado e instala.
    $gpu = $null
    for ($t = 1; $t -le 5 -and -not $gpu; $t++) {
        $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction Ignore | Where-Object { $_.Name -match 'NVIDIA' })[0]
        if ($gpu) { break }
        $hw = @(Get-CimInstance Win32_PnPEntity -ErrorAction Ignore | Where-Object { $_.PNPClass -eq 'Display' -and $_.PNPDeviceID -match 'VEN_10DE&DEV_([0-9A-Fa-f]{4})' })[0]
        if ($hw) {
            $dev   = if ($hw.PNPDeviceID -match 'DEV_([0-9A-Fa-f]{4})') { $Matches[1] } else { '' }
            $achado = @($NvidiaProdutos.Keys | Where-Object { $NvidiaProdutos[$_].dev -eq $dev })[0]
            if ($achado) {
                Passo "placa NVIDIA sem driver ainda ($($hw.Name), DEV_$dev = $achado); vou instalar o driver"
                $gpu = [pscustomobject]@{ Name = $achado; DriverVersion = '' }   # sem versão: trata como desatualizado
                break
            }
            Passo "placa NVIDIA DEV_$dev sem driver e fora da tabela; esperando ($t de 5)"
        } else {
            Passo "nenhuma placa NVIDIA à vista ainda; o PCI pode estar sendo enumerado ($t de 5)"
        }
        Start-Sleep -Seconds 4
    }
    if (-not $gpu) {
        Passo 'nenhuma placa NVIDIA encontrada; o vídeo fica com o que o Windows Update trouxer na etapa 26'
        return
    }
    Passo "placa: $($gpu.Name)"

    # O WMI mostra a versão do Windows (32.0.15.9186); a da NVIDIA são os dois últimos campos colados
    # (15 + 9186 = 159186), os 5 últimos dígitos disso (59186) e um ponto antes dos dois finais: 591.86.
    $instalado = $null
    $campos = @($gpu.DriverVersion -split '\.')
    if ($campos.Count -ge 2) {
        $n = ($campos[-2] + $campos[-1]) -replace '\D', ''
        if ($n.Length -ge 5) { $instalado = $n.Substring($n.Length - 5).Insert(3, '.') }
    }
    if ($instalado) { Passo "driver instalado: $instalado ($($gpu.DriverVersion))" }
    else { Passo "driver instalado: $($gpu.DriverVersion), num formato que não sei ler; vou tratar como desatualizado" }

    $chave = @($NvidiaProdutos.Keys | Where-Object { $gpu.Name -match [regex]::Escape($_) })[0]
    if (-not $chave) {
        Falha "a placa '$($gpu.Name)' não está no NvidiaProdutos do setup.ps1; o driver fica para o Windows Update da etapa 26"
        return
    }
    $prod = $NvidiaProdutos[$chave]

    # osID 135 = Windows 11 64-bit; dch=1 = driver DCH, o único que o Windows 11 aceita; isWHQL=1 = assinado
    # pela Microsoft; beta=0 e numberOfResults=1 = só o Game Ready estável mais recente.
    $api = 'https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php' +
           "?func=DriverManualLookup&psid=$($prod.psid)&pfid=$($prod.pfid)&osID=135&languageCode=1033" +
           '&beta=0&isWHQL=1&dltype=-1&dch=1&upCRD=0&qnf=0&sort1=0&numberOfResults=1'
    $info = $null
    try {
        $resposta = Invoke-RestMethod -UseBasicParsing -UserAgent 'Mozilla/5.0' -Uri $api -TimeoutSec 60
        $info = @($resposta.IDS)[0].downloadInfo
    } catch {
        Falha "a API da NVIDIA não respondeu ($($_.Exception.Message)); o driver fica para o Windows Update da etapa 26"
        return
    }
    if (-not $info.DownloadURL) {
        Falha 'a API da NVIDIA respondeu sem DownloadURL; o driver fica para o Windows Update da etapa 26'
        return
    }
    Passo "mais novo na NVIDIA: $($info.Version), de $($info.ReleaseDateTime)"

    # [version] em vez de [double]: comparação de número com ponto não depende da cultura da máquina
    if ($instalado -and [version]$instalado -ge [version]$info.Version) {
        Passo 'o driver instalado já é esse; nada a baixar'
        return
    }

    $exe = Join-Path $env:TEMP "NVIDIA-$($info.Version).exe"
    Baixar $info.DownloadURL $exe
    # -s silencioso, -noreboot para não reiniciar no meio do setup, -clean para apagar o driver anterior e os
    # perfis dele (a máquina acabou de ser formatada, não há o que preservar), -nofinish e -nosplash para não
    # abrir janela nenhuma. O instalador leva alguns minutos e a tela pisca e apaga durante ele.
    Passo 'instalando em silêncio (a tela vai piscar e ficar preta por alguns segundos)'
    $inst = Start-Process -FilePath $exe -ArgumentList '-s', '-noreboot', '-clean', '-nofinish', '-nosplash' -Wait -PassThru
    Remove-Item -LiteralPath $exe -Force -ErrorAction Ignore
    # 0 = instalou; 1 = instalou e quer reiniciar (o -noreboot só adia, e o driver já está valendo)
    if ($inst.ExitCode -notin 0, 1) {
        Falha "o instalador da NVIDIA saiu com código $($inst.ExitCode); o log dele fica em C:\ProgramData\NVIDIA Corporation\NVIDIA Installer2"
        return
    }

    # O driver novo assume sem reiniciar, mas o Windows leva alguns segundos para publicar os modos de vídeo
    # novos. A etapa seguinte depende disso, então espera a versão no WMI mudar antes de seguir.
    Passo 'esperando o driver assumir'
    $novo = $gpu
    $limite = (Get-Date).AddSeconds(90)
    while ($novo.DriverVersion -eq $gpu.DriverVersion -and (Get-Date) -lt $limite) {
        Start-Sleep -Seconds 3
        $novo = @(Get-CimInstance Win32_VideoController -ErrorAction Ignore | Where-Object { $_.Name -match 'NVIDIA' })[0]
    }
    if ($novo.DriverVersion -eq $gpu.DriverVersion) {
        Falha "o instalador terminou mas o WMI ainda mostra $($gpu.DriverVersion); os monitores podem não aceitar o modo pedido antes de um reinício"
    } else {
        Passo "driver agora: $($info.Version) ($($novo.DriverVersion))"
    }
}

# --- 6. Monitores: resolução, frequência, orientação e posição (monitores\monitores.json) ----------
# Logo depois do driver, de propósito: 1440p a 180 Hz e o giro da LG só existem com o driver da placa
# carregado. O driver acabou de assumir e o Windows leva alguns segundos para publicar os modos novos,
# então tenta até três vezes antes de desistir, em vez de avisar na primeira.
Etapa 'Monitores (resolução, Hz, posição)' {
    $mon  = Join-Path $aqui 'monitores\monitores.ps1'
    $json = Join-Path $aqui 'monitores\monitores.json'
    if (-not (Test-Path -LiteralPath $json)) { throw "não achei $json" }
    Passo 'ASUS XG27ACS em 2560x1440 a 180 Hz como principal; LG UltraGear em 1920x1080 a 144 Hz, de pé, à esquerda'
    for ($t = 1; $t -le 3; $t++) {
        & $mon -Arquivo $json
        $cod = $LASTEXITCODE
        if ($cod -eq 0) { break }
        # 100+N: os N que faltam apenas não estão ligados (cabo, botão, monitor de outra máquina). Ainda
        # vale repetir, porque logo depois do driver subir eles podem aparecer com segundos de atraso; o
        # que muda é o fim: monitor desligado sai como aviso, e só o driver recusando o modo é FALHOU.
        $faltam = if ($cod -ge 100) { $cod - 100 } else { $cod }
        if ($t -lt 3) {
            Passo "$faltam monitor(es) fora do lugar; o driver ainda pode estar subindo (tentativa $t de 3)"
            Start-Sleep -Seconds 10
        } elseif ($cod -ge 100) {
            Passo "$faltam monitor(es) do monitores.json não estão ligados; os que estão ficaram como pedido"
        } else {
            Falha "monitores: $cod monitor(es) não ficaram como no monitores.json; confira o driver da placa e rode de novo"
        }
    }
}

# --- 7. Preferências do usuário ----------------------------------------------------------------------
Etapa 'Preferências do usuário' {
    if ($Dados) {
        Passo 'Downloads em D:, onde a formatação não chega'
        # SHSetKnownFolderPath é o caminho oficial: ele mesmo grava as duas entradas de User Shell Folders
        # (nome antigo e GUID) e avisa o Explorer. Sem mover conteúdo (flag 0): num Windows recém-instalado
        # as pastas estão vazias.
        # Só a Downloads. Documentos, Imagens, Vídeos e Músicas ficam no C: como o Windows as cria: o que
        # cai ali ou é descartável ou já vive na nuvem, e não vale o redirecionamento. A Área de Trabalho
        # fica no C: pelo mesmo motivo. O que estiver em D:\Documentos e afins de instalações antigas
        # continua lá, intocado; só deixa de ser o destino dessas pastas do Windows.
        if (-not ('Win32.KnownFolders' -as [type])) {
            Add-Type -Namespace Win32 -Name KnownFolders -MemberDefinition '[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SHSetKnownFolderPath(ref Guid rfid, uint dwFlags, IntPtr hToken, string pszPath);'
        }
        foreach ($kf in @(
            @{ pasta = 'Downloads';  id = '374DE290-123F-4565-9164-39C4925E467B' })) {
            $alvo = Join-Path $Dados $kf.pasta
            New-Item -ItemType Directory -Path $alvo -Force | Out-Null
            $g = [Guid]$kf.id
            $hr = [Win32.KnownFolders]::SHSetKnownFolderPath([ref]$g, 0, [IntPtr]::Zero, $alvo)
            if ($hr -ne 0) { Falha ("pasta {0} -> {1}: SHSetKnownFolderPath devolveu 0x{2:X8}" -f $kf.pasta, $alvo, $hr) }
        }
        New-Item -ItemType Directory -Path (Join-Path $Dados 'Jogos') -Force | Out-Null   # Projetos em D: é o Alexandre quem cria

        Passo 'perfil dos programas em D:\Perfil: toda pasta de configuração de todo programa, por regra'
        # manutencao\perfil.ps1: cada pasta que há (ou houver) em Roaming, Local, LocalLow e nos .dotfolders do
        # perfil vai para D:\Perfil\<raiz>\<pasta> e vira junção, menos o que é do próprio Windows (Microsoft,
        # Packages, Temp, Programs). Roda aqui, antes de instalar qualquer programa, para as junções das
        # pastas que sobreviveram à formatação já existirem quando o instalador gravar; roda de novo no fim
        # dos Programas e no fim do setup, e depois pela tarefa 'Perfil no D' a cada logon e de hora em hora,
        # para programa instalado depois. Por que não o AppData inteiro está explicado no próprio script.
        # O que não volta, por desenho do Windows: o que os programas cifram com a DPAPI da conta (cookies,
        # sessões, tokens, credencial do git). A conta nova tem chave nova; esses pedem login de novo.
        if (Test-Path -LiteralPath $PerfilNoD) {
            & $PerfilNoD
            $sid       = ([Security.Principal.NTAccount]"$env:USERDOMAIN\$env:USERNAME").Translate([Security.Principal.SecurityIdentifier]).Value
            $principal = New-ScheduledTaskPrincipal -UserId $sid -RunLevel Highest
            $cfg       = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -Hidden
            $gatilhos  = @((New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"),
                           (New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)))
            Register-ScheduledTask -TaskName 'Perfil no D' -TaskPath '\mywiniso' -Force -Settings $cfg -Principal $principal -Trigger $gatilhos `
                -Action (New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PerfilNoD`" -Quieto") | Out-Null
            Passo "tarefa 'Perfil no D': a cada logon e de hora em hora, leva para D: o perfil de programa novo"
        } else { Falha "não achei $PerfilNoD" }
        # D:\Perfil veio de antes da formatação com dono no SID da conta velha. O Windows lê e grava assim
        # mesmo, mas o git recusa todo repositório dali ("dubious ownership") -- e os marketplaces de plugin
        # do Claude são clones git dentro de ~\.claude. Uma passada do icacls resolve (52 mil arquivos, 5 s).
        Silencioso { icacls.exe (Join-Path $Dados 'Perfil') /setowner "$env:USERDOMAIN\$env:USERNAME" /T /C /Q 2>&1 | Out-Null }
        Passo 'D:\Perfil com dono na conta atual (senão o git recusa os repositórios de lá)'
        # Android SDK, emuladores e o .android em D:, para não baixar de novo a cada formatação. O Android
        # Studio lê ANDROID_HOME no assistente inicial e propõe esse caminho para o SDK; o AVD e o .android
        # seguem as variáveis próprias. Variáveis de máquina, então valem para qualquer conta e terminal.
        Passo 'Android SDK e emuladores em D:\Android (ANDROID_HOME, ANDROID_AVD_HOME, ANDROID_USER_HOME)'
        foreach ($par in @(@('ANDROID_HOME', 'Android\Sdk'), @('ANDROID_SDK_ROOT', 'Android\Sdk'), @('ANDROID_AVD_HOME', 'Android\avd'), @('ANDROID_USER_HOME', 'Android\.android'))) {
            $alvo = Join-Path $Dados $par[1]
            New-Item -ItemType Directory -Path $alvo -Force | Out-Null
            [Environment]::SetEnvironmentVariable($par[0], $alvo, 'Machine')
        }
    }
    Passo 'Explorer: extensões, Este Computador, menu de contexto moderno'
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg $adv 'HideFileExt'        0
    Set-Reg $adv 'LaunchTo'           1
    Passo 'pastas com o nome real: Program Files, Users, Public, e não a tradução'
    # A tradução ("Arquivos de Programas") vem do LocalizedResourceName no desktop.ini de cada pasta. Só isso:
    # medido, tirar a linha basta e o FolderDescriptions do registro não precisa ser tocado. O arquivo é
    # UTF-16 com BOM e tem os atributos sistema+oculto; por isso .NET e não attrib/Set-Content.
    foreach ($pasta in "$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:ProgramFiles\Common Files", "${env:ProgramFiles(x86)}\Common Files", "$env:SystemDrive\Users", "$env:PUBLIC") {
        $ini = Join-Path $pasta 'desktop.ini'
        if (-not (Test-Path -LiteralPath $ini)) { continue }
        try {
            $bytes = [IO.File]::ReadAllBytes($ini)
            $enc = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [Text.Encoding]::Unicode } else { [Text.Encoding]::Default }
            $txt = $enc.GetString($bytes)
            if ($txt -notmatch '(?m)^LocalizedResourceName=') { continue }
            $attr = [IO.File]::GetAttributes($ini)
            [IO.File]::SetAttributes($ini, 'Normal')
            [IO.File]::WriteAllBytes($ini, $enc.GetPreamble() + $enc.GetBytes(($txt -replace '(?m)^LocalizedResourceName=.*\r?\n?', '')))
            [IO.File]::SetAttributes($ini, $attr)
        } catch { Falha "desktop.ini de ${pasta}: $($_.Exception.Message)" }
    }
    # caminho completo na barra de título. Na barra de endereço o Windows 11 só mostra a trilha (clicar nela
    # mostra o caminho): não há ajuste para deixá-la literal; o que dá é o nome de cada pasta ser o real.
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState' 'FullPath' 1
    # área de trabalho limpa: nenhum ícone aparece. Os arquivos continuam lá (o RedM.exe e o
    # mywiniso-setup.cmd que o setup deixa), só não são desenhados; para chegar neles, Win+E e ir na
    # pasta Área de Trabalho. O Explorer relê isso quando reiniciar, na etapa 10.
    Passo 'área de trabalho sem nenhum ícone (os arquivos ficam, só não aparecem)'
    Set-Reg $adv 'HideIcons'          1
    # Menu de contexto moderno, e não o clássico. O moderno é WinUI: já nasce com o acrílico e os cantos
    # arredondados do menu Iniciar, que é o visual do resto do sistema aqui, e ainda responde ao
    # windows-11-file-explorer-styler. O clássico é Win32 puro, fica chapado e de borda clara, e não há
    # jeito mantido de dar o mesmo visual a ele: o TranslucentFlyouts, único que fazia isso, está
    # arquivado desde 2024, e o dark-menus só força o escuro. O preço é que Git Bash, NVIDIA App e 7-Zip
    # passam a viver em "Mostrar mais opções" (ou no Shift+F10, que abre o clássico direto).
    # Remove em vez de só não escrever: numa máquina que já rodou o setup de antes a chave está lá.
    Remove-Item -LiteralPath 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force -ErrorAction Ignore
    Passo 'barra: ícones centralizados, só no monitor principal, sem busca, Visão de Tarefas, widgets e Copilot; "Finalizar tarefa"'
    Set-Reg $adv 'TaskbarAl'          1      # 1 = ícones centralizados
    Set-Reg $adv 'ShowTaskViewButton' 0
    Set-Reg $adv 'ShowCopilotButton'  0
    Set-Reg $adv 'MMTaskbarEnabled'  0      # barra de tarefas só no monitor principal
    # O driver UCPD (24H2+) recusa escrita em TaskbarDa quando quem grava se chama powershell.exe ou reg.exe.
    # Contorno do Sophia Script: gravar por uma cópia renomeada do próprio powershell. Não há Set-Reg antes
    # deste bloco de propósito: ela seria recusada sempre e entraria na lista de falhas do resumo por nada.
    $psOrig = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psCopia = Join-Path $env:TEMP 'mywiniso-ps.exe'
    try {
        Copy-Item -LiteralPath $psOrig -Destination $psCopia -Force
        & $psCopia -NoProfile -Command "New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarDa -PropertyType DWord -Value 0 -Force | Out-Null"
        Passo 'widgets fora da barra (gravado por cópia do powershell, senão o driver UCPD recusa)'
    } catch { Falha "TaskbarDa: $($_.Exception.Message)" }
    finally { Remove-Item -LiteralPath $psCopia -Force -ErrorAction Ignore }
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0
    Set-Reg "$adv\TaskbarDeveloperSettings" 'TaskbarEndTask' 1
    Passo 'Iniciar: mais fixados, sem recomendações'
    Set-Reg $adv 'Start_Layout'              1
    Set-Reg $adv 'Start_IrisRecommendations' 0
    Passo 'tema escuro, sem transparência, sem cor de destaque'
    $pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-Reg $pers 'AppsUseLightTheme'    0
    Set-Reg $pers 'SystemUsesLightTheme' 0
    Set-Reg $pers 'EnableTransparency'   0
    Set-Reg $pers 'ColorPrevalence'      0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence' 0
    Passo 'sem sugestões, apps promovidos e busca com Bing'
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in 'ContentDeliveryAllowed', 'FeatureManagementEnabled', 'OEMPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
                   'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled', 'SoftLandingEnabled', 'SubscribedContentEnabled',
                   'SubscribedContent-310093Enabled', 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled',
                   'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled',
                   'SubscribedContent-353696Enabled', 'SubscribedContent-353698Enabled', 'SystemPaneSuggestionsEnabled') {
        Set-Reg $cdm $n 0
    }
    Passo 'mouse sem aceleração'
    $mouse = 'HKCU:\Control Panel\Mouse'
    Set-Reg $mouse 'MouseSpeed'      '0' 'String'
    Set-Reg $mouse 'MouseThreshold1' '0' 'String'
    Set-Reg $mouse 'MouseThreshold2' '0' 'String'
    Passo 'teclado: repetição no máximo, cursor rápido, NumLock ligado, Print Screen livre para o Lightshot'
    $kbd = 'HKCU:\Control Panel\Keyboard'
    Set-Reg $kbd 'KeyboardDelay'             '0'  'String'
    Set-Reg $kbd 'KeyboardSpeed'             '31' 'String'
    Set-Reg $kbd 'InitialKeyboardIndicators' '2'  'String'
    Set-Reg 'Registry::HKU\.DEFAULT\Control Panel\Keyboard' 'InitialKeyboardIndicators' '2' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'CursorBlinkRate' '200' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'JPEGImportQuality' 100      # o wallpaper é JPG; 100 tira o artefato de compressão
    Set-Reg $kbd 'PrintScreenKeyForSnippingEnabled' 0
    # o registro só vale no próximo logon; SystemParametersInfo faz valer agora
    if (-not ('MyWinIsoTeclado' -as [type])) {
        Add-Type -Name MyWinIsoTeclado -Namespace Win32 -MemberDefinition '
            [DllImport("user32.dll", SetLastError = true)]
            public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, System.IntPtr pvParam, uint fWinIni);'
    }
    [void][Win32.MyWinIsoTeclado]::SystemParametersInfo(0x0017, 0, [IntPtr]0, 3)   # SPI_SETKEYBOARDDELAY = mais curto
    [void][Win32.MyWinIsoTeclado]::SystemParametersInfo(0x000B, 31, [IntPtr]0, 3)  # SPI_SETKEYBOARDSPEED = mais rápido
    Passo 'só o teclado ABNT2 (Português do Brasil); nenhum layout em inglês'
    try {
        $idiomas = New-WinUserLanguageList -Language pt-BR
        $idiomas[0].InputMethodTips.Clear()
        $idiomas[0].InputMethodTips.Add('0416:00010416')   # ABNT2
        Set-WinUserLanguageList -LanguageList $idiomas -Force
        Set-WinUILanguageOverride -Language pt-BR
        Set-WinSystemLocale -SystemLocale pt-BR
        Set-Culture -CultureInfo pt-BR
    } catch { Falha "teclado: $($_.Exception.Message)" }
    # o mesmo para a tela de login e para contas novas
    Set-Reg 'Registry::HKU\.DEFAULT\Keyboard Layout\Preload' '1' '00010416' 'String'
    Set-Reg 'Registry::HKU\.DEFAULT\Control Panel\Keyboard' 'KeyboardDelay' '0' 'String'
    Set-Reg 'Registry::HKU\.DEFAULT\Control Panel\Keyboard' 'KeyboardSpeed' '31' 'String'
    Passo 'desligar sem travar em app aberto; reabrir apps ao entrar'
    $desk = 'HKCU:\Control Panel\Desktop'
    Set-Reg $desk 'AutoEndTasks'         '1'    'String'
    Set-Reg $desk 'WaitToKillAppTimeout' '2000' 'String'
    Set-Reg $desk 'HungAppTimeout'       '1000' 'String'
    Set-Reg 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' 'RestartApps' 1
    Passo 'atalhos de acessibilidade desligados; Game DVR desligado'
    Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys'        'Flags' '506' 'String'
    Set-Reg 'HKCU:\Control Panel\Accessibility\ToggleKeys'        'Flags' '58'  'String'
    Set-Reg 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String'
    Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    Passo 'histórico Win+V ligado, ações sugeridas desligadas'
    Set-Reg 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SmartActionPlatform\SmartClipboard' 'Disabled' 1
    Passo 'notificações desligadas: nada de balão, banner nem som de aviso'
    # Só os avisos (toasts). A central de notificações em si NÃO é desligada, de propósito: no Windows 11
    # o calendário mora dentro dela, e clicar no relógio abre esse painel. A política
    # DisableNotificationCenter tiraria o painel inteiro e levaria o calendário junto, então ela fica de
    # fora. Resultado: nada aparece sozinho no canto, mas clicar no relógio ainda abre o calendário.
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK' 0
    # as três da tela de boas-vindas e das "dicas" do Windows, que também chegam como notificação
    Set-Reg $cdm 'SubscribedContent-310093Enabled' 0
    Set-Reg $cdm 'SubscribedContent-338389Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    Passo 'clicar no relógio abre a central com o calendário (por isso a central fica de pé)'

    # O que o preset do Sophia Script (farag2) faz e ainda não estava aqui. Cruzado função por função com o
    # Sophia.ps1 do Windows 11; o resto do preset já existe em outras linhas deste arquivo ou no specialize.
    Passo 'do Sophia Script: relatório de erros e feedback off, sem AutoPlay, Explorer e Iniciar mais limpos'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1              # ErrorReporting -Disable
    Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0                                   # FeedbackFrequency -Never
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Siuf\Rules' -Name 'PeriodInNanoSeconds' -ErrorAction Ignore
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' 'DisableAutoplay' 1  # Autoplay -Disable
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 0                      # QuickAccessFrequentFolders -Hide
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowRecent'   0                      # QuickAccessRecentFiles -Hide
    Set-Reg $adv 'HideMergeConflicts' 0                                                                       # MergeConflicts -Show
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager' 'EnthusiastMode' 1   # FileTransferDialog -Detailed
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' 0                 # PreventEdgeShortcutCreation
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableFirstLogonAnimation' 0  # FirstLogonAnimation -Disable
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates' 'ShortcutNameTemplate' '%s.lnk' 'String'   # ShortcutsSuffix -Disable
    Set-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1                    # LanguageListAccess -Disable
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters' 1                      # BSoDStopError -Enable
    Set-Reg 'HKCU:\Software\Classes\Typelib\{8cec5860-07a1-11d9-b15e-000d56bfe6ee}\1.0\0\win64' '(Default)' '' 'String'   # F1HelpPage -Disable
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel' 'AllItemsIconView' 0     # ControlPanelView -LargeIcons
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel' 'StartupPage'      1
    Set-Reg $adv 'Start_TrackProgs' 0                                                                         # MostUsedStartApps -Hide
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecentlyAddedApps' 1                  # RecentlyAddedStartApps -Hide
    Set-Reg $adv 'Start_AccountNotifications' 0                                                               # StartAccountNotifications -Hide
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'NoUseStoreOpenWith' 1                      # UseStoreOpenWith -Hide
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds\DSB' 'ShowDynamicContent' 0              # SearchHighlights -Hide
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' 'LegacyDefaultPrinterMode' 1        # WindowsManageDefaultPrinter -Disable
    Set-Reg $adv 'ShowSyncProviderNotifications' 0                                                            # OneDriveFileExplorerAd -Hide
    # NetworkAdaptersSavePower -Disable: a placa de rede não dorme para economizar energia (latência em jogo)
    Get-NetAdapter -Physical -ErrorAction Ignore | ForEach-Object { Silencioso { Disable-NetAdapterPowerManagement -Name $_.Name -NoRestart } }

    Passo 'sons do sistema desligados'
    Set-Reg 'HKCU:\AppEvents\Schemes' '(Default)' '.None' 'String'
    Get-ChildItem -Path 'HKCU:\AppEvents\Schemes\Apps\*\*' -ErrorAction Ignore |
        Where-Object PSChildName -eq '.Current' |
        ForEach-Object { Set-ItemProperty -LiteralPath $_.PSPath -Name '(Default)' -Value '' }
    Passo 'privacidade: sem experiências personalizadas, ID de anúncio, digitação, fala, localização'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'         'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Input\TIPC'                              'Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Settings\FindMyDevice' 'LocationSyncEnabled' 0
    Passo 'apps de bloatware já instalados para este usuário (mesma lista do XML) e provider do Copilot'
    $bloat = @(
        'Clipchamp.Clipchamp', 'Microsoft.549981C3F5F10', 'Microsoft.BingNews', 'Microsoft.BingSearch', 'Microsoft.BingWeather',
        'Microsoft.Copilot', 'Microsoft.Edge.GameAssist', 'Microsoft.GamingApp', 'Microsoft.GamingServices', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
        'Microsoft.Microsoft3DViewer', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.MicrosoftStickyNotes', 'Microsoft.MixedReality.Portal', 'Microsoft.MSPaint', 'Microsoft.Office.OneNote',
        'Microsoft.OutlookForWindows', 'Microsoft.Paint', 'Microsoft.People', 'Microsoft.PowerAutomateDesktop',
        'Microsoft.ScreenSketch', 'Microsoft.SkypeApp', 'Microsoft.Todos', 'Microsoft.Wallet', 'Microsoft.Windows.DevHome',
        'Microsoft.WindowsAlarms', 'Microsoft.WindowsCamera', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
        'Microsoft.WindowsSoundRecorder', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp',
        'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.YourPhone',
        'MicrosoftCorporationII.MicrosoftFamily', 'MicrosoftCorporationII.QuickAssist',
        'MicrosoftTeams', 'MSTeams', 'microsoft.windowscommunicationsapps', 'MicrosoftWindows.Client.WebExperience',
        'Microsoft.WidgetsPlatformRuntime', 'Microsoft.SecureAssessmentBrowser',
        'Microsoft.Windows.Ai.Copilot.Provider'
    )
    foreach ($app in Get-AppxPackage | Where-Object { $bloat -contains $_.Name }) {
        Passo "removendo $($app.Name)"
        Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Continue
    }
    if (Get-Process -Name OneDrive -ErrorAction Ignore) {
        Passo 'OneDrive rodando: desinstalando'
        Stop-Process -Name OneDrive -Force -ErrorAction Ignore
        foreach ($exe in "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe", "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe") {
            if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe -ArgumentList '/uninstall' -Wait }
        }
    }
    Passo 'Bloco de Notas sem o banner da Loja'
    Set-Reg 'HKCU:\Software\Microsoft\Notepad' 'ShowStoreBanner' 0
    Passo 'Modo Jogo ligado, apps em segundo plano desligados'
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode'   1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1

    # Cor de destaque fixa, e não puxada do wallpaper: a automática tirava um roxo sujo da paisagem. Este
    # é o "Roxo-sombreado-escuro" da própria paleta do Windows, escolhido pelo Alexandre. O Windows
    # guarda a cor em três lugares: a AccentPalette (8 tons RGBA, da clara para a escura, a 4ª é a base) e
    # os dois menus em ABGR, mais o DWM. Trocar aqui e o Explorer, o Iniciar e as Configurações pegam junto.
    $AccentColor = '#6B69D6'
    Passo "cor de destaque fixa: $AccentColor"
    $rgb = [Convert]::ToInt32($AccentColor.TrimStart('#'), 16)
    $cr = ($rgb -shr 16) -band 0xFF; $cg = ($rgb -shr 8) -band 0xFF; $cb = $rgb -band 0xFF
    function Tom([int] $f) {   # f > 0 clareia (mistura com branco), f < 0 escurece (com preto); em centésimos
        $alvo = if ($f -gt 0) { 255 } else { 0 }; $p = [Math]::Abs($f) / 100
        [byte[]]@([Math]::Round($cr + ($alvo - $cr) * $p), [Math]::Round($cg + ($alvo - $cg) * $p), [Math]::Round($cb + ($alvo - $cb) * $p), 0)
    }
    $pal = New-Object byte[] 32
    $i = 0
    foreach ($f in 60, 40, 20, 0, -20, -40, -60, -80) { $t = Tom $f; [Array]::Copy($t, 0, $pal, $i * 4, 4); $i++ }
    # o L nos literais nao e enfeite: sem ele o Windows PowerShell 5.1 le 0xFF000000/0xC4000000 como
    # Int32, que nao cabe, e entrega negativo; o [uint32] entao lanca "valor era muito grande ou muito
    # pequeno para UInt32" e a etapa inteira morre bem no fim. Com o L o literal e Int64 positivo.
    function Abgr([byte[]] $t) { [uint32](0xFF000000L -bor ([uint32]$t[2] -shl 16) -bor ([uint32]$t[1] -shl 8) -bor [uint32]$t[0]) }
    $acc = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
    Set-Reg $acc 'AccentPalette'   $pal 'Binary'
    Set-Reg $acc 'AccentColorMenu' (Abgr (Tom 0))   'DWord'
    Set-Reg $acc 'StartColorMenu'  (Abgr (Tom -20)) 'DWord'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'AccentColor'         (Abgr (Tom 0)) 'DWord'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorizationColor'   ([uint32](0xC4000000L -bor $rgb)) 'DWord'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorizationAfterglow' ([uint32](0xC4000000L -bor $rgb)) 'DWord'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'AutoColorization' 0
    # avisa quem está aberto (Explorer, Configurações) que a cor mudou
    if (-not ('Win32.Aviso' -as [type])) {
        Add-Type -Namespace Win32 -Name Aviso -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, UIntPtr w, string l, uint f, uint t, out UIntPtr r);'
    }
    $res = [UIntPtr]::Zero
    [void][Win32.Aviso]::SendMessageTimeout([IntPtr]0xFFFF, 0x1A, [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 1000, [ref]$res)
    Passo 'região Brasil; ícone do Edge fora da área de trabalho'
    Set-WinHomeLocation -GeoId 32
    Remove-Item -LiteralPath (Join-Path $desktop 'Microsoft Edge.lnk'), 'C:\Users\Public\Desktop\Microsoft Edge.lnk' -Force -ErrorAction Ignore
}

# --- 8. Wallpaper: uma imagem por monitor, e a tela de bloqueio --------------------------------------
# O registro (Control Panel\Desktop\WallPaper) guarda UMA imagem para todos os monitores. Uma por monitor
# só existe pela interface COM IDesktopWallpaper (Windows 8+), a mesma que a Personalização usa quando
# você clica com o direito numa imagem e escolhe "Definir para o monitor 2".
#
# Qual imagem para qual monitor: em vez de casar por nome de dispositivo, que muda de porta para porta, a
# etapa pergunta o retângulo de cada monitor e olha a forma. Mais alto que largo é o retrato (a LG em pé,
# girada 90 pela etapa 6) e recebe a imagem em retrato; os outros ficam com a paisagem. Funciona igual se
# as portas trocarem, e não quebra se só um monitor estiver ligado.
#
# A espera no fim não é decorativa. O Explorer só grava a atribuição por monitor em
# Control Panel\Desktop\TranscodedImageCache_00N alguns segundos depois do SetWallpaper. Se ele morrer
# antes disso, e ele reinicia na etapa 10 e no fim da etapa 25, volta todos os monitores para o valor
# único do registro e o monitor em pé perde a imagem. Medido nesta máquina: sem a espera desfaz, com a
# espera sobrevive. Por isso a etapa só termina depois de ver as chaves no registro.
$WallPaisagem = 'Jason_and_Lucia_Robbery_landscape.jpg'
$WallRetrato  = 'Real_Dimez_portrait.jpg'
Etapa 'Wallpaper (um por monitor)' {
    $wallDir = Join-Path $env:SystemRoot 'Web\Wallpaper\mywiniso'   # legível pelo SYSTEM, que desenha a tela de bloqueio
    New-Item -ItemType Directory -Path $wallDir -Force | Out-Null
    foreach ($nome in $WallPaisagem, $WallRetrato) {
        $origem = Join-Path $aqui "wallpaper\$nome"
        if (-not (Test-Path -LiteralPath $origem)) { throw "não achei $origem" }
        Copy-Item -LiteralPath $origem -Destination $wallDir -Force
    }
    $paisagem = Join-Path $wallDir $WallPaisagem
    $retrato  = Join-Path $wallDir $WallRetrato

    # Tudo que toca COM fica dentro do C#: o Windows PowerShell 5.1 rebaixa objeto COM para
    # System.__ComObject e perde a interface, então chamar $dw.Metodo() do PowerShell falha com "não
    # contém um método denominado...". Os 8 métodos estão na ordem exata da vtable, que é o que define
    # qual slot é chamado; a declaração tem de ir até o mais alto que se usa (SetPosition).
    if (-not ('MyWinIso.Wallpaper' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace MyWinIso {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IDesktopWallpaper {
        void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID,
                          [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint monitorIndex);
        uint GetMonitorDevicePathCount();
        RECT GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
        void SetBackgroundColor(uint color);
        uint GetBackgroundColor();
        void SetPosition(int position);
    }

    public class MonitorInfo {
        public string Id;
        public int Width, Height, Left, Top;
        public bool Portrait;
    }

    public static class Wallpaper {
        static IDesktopWallpaper Novo() {
            Type t = Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD"));
            // o cast tem de ser aqui, no C#: e ele que vira um QueryInterface de verdade
            return (IDesktopWallpaper)Activator.CreateInstance(t);
        }
        public static MonitorInfo[] Monitores() {
            IDesktopWallpaper dw = Novo();
            uint n = dw.GetMonitorDevicePathCount();
            List<MonitorInfo> lista = new List<MonitorInfo>();
            for (uint i = 0; i < n; i++) {
                string id = dw.GetMonitorDevicePathAt(i);
                if (string.IsNullOrEmpty(id)) continue;
                RECT r;
                // monitor que ja foi ligado mas esta desconectado agora aparece na lista sem retangulo
                try { r = dw.GetMonitorRECT(id); } catch { continue; }
                int w = r.Right - r.Left, h = r.Bottom - r.Top;
                if (w <= 0 || h <= 0) continue;
                lista.Add(new MonitorInfo { Id = id, Width = w, Height = h, Left = r.Left, Top = r.Top, Portrait = h > w });
            }
            return lista.ToArray();
        }
        public static string Atual(string id) { return Novo().GetWallpaper(id); }
        public static void Definir(string id, string imagem) { Novo().SetWallpaper(id, imagem); }
        public static void Posicao(int p) { Novo().SetPosition(p); }
    }
}
'@
    }

    # o valor único do registro primeiro: é o que vale para conta nova, para sessão de RDP e para
    # qualquer caminho que não passe pela IDesktopWallpaper
    Set-Reg 'HKCU:\Control Panel\Desktop' 'WallPaper'      $paisagem 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'WallpaperStyle' '10'      'String'     # preencher
    Set-Reg 'HKCU:\Control Panel\Desktop' 'TileWallpaper'  '0'       'String'

    [MyWinIso.Wallpaper]::Posicao(4)      # 4 = DWPOS_FILL, o equivalente ao WallpaperStyle 10 do registro
    $monitores = [MyWinIso.Wallpaper]::Monitores()
    Passo "$($monitores.Count) monitor(es) ligados"
    foreach ($m in $monitores) {
        $img = if ($m.Portrait) { $retrato } else { $paisagem }
        Passo ("  {0}x{1} em {2},{3} -> {4}" -f $m.Width, $m.Height, $m.Left, $m.Top, (Split-Path $img -Leaf))
        try { [MyWinIso.Wallpaper]::Definir($m.Id, $img) }
        catch { Falha ("wallpaper do monitor {0}x{1}: {2}" -f $m.Width, $m.Height, $_.Exception.Message) }
    }

    Passo 'esperando o Explorer gravar o TranscodedImageCache (sem isso o reinício dele desfaz o de cada monitor)'
    $limite = (Get-Date).AddSeconds(60)
    do {
        Start-Sleep -Seconds 2
        $caches = @((Get-Item -LiteralPath 'HKCU:\Control Panel\Desktop').Property | Where-Object { $_ -match '^TranscodedImageCache_\d+$' })
    } while ($caches.Count -lt $monitores.Count -and (Get-Date) -lt $limite)
    if ($caches.Count -lt $monitores.Count) {
        Falha "o Explorer gravou $($caches.Count) TranscodedImageCache_NNN para $($monitores.Count) monitor(es); o reinício do Explorer na etapa 10 pode desfazer o wallpaper do monitor em pé"
    } else {
        Passo "$($caches.Count) TranscodedImageCache_NNN no registro; a imagem de cada monitor sobrevive ao reinício do Explorer"
    }

    # confere lendo de volta, que é a única forma de saber se pegou
    foreach ($m in $monitores) {
        $esperado = if ($m.Portrait) { $retrato } else { $paisagem }
        $agora = try { [MyWinIso.Wallpaper]::Atual($m.Id) } catch { '' }
        if ($agora -ne $esperado) { Falha ("o monitor {0}x{1} ficou com '{2}' em vez de '{3}'" -f $m.Width, $m.Height, (Split-Path $agora -Leaf), (Split-Path $esperado -Leaf)) }
    }

    Passo 'tela de bloqueio (PersonalizationCSP)'
    $csp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
    Set-Reg $csp 'LockScreenImagePath'   $paisagem 'String'
    Set-Reg $csp 'LockScreenImageUrl'    $paisagem 'String'
    Set-Reg $csp 'LockScreenImageStatus' 1
}

# --- 9. Foto do perfil da conta (perfil\avatar.png) -------------------------------------------------
# O Windows guarda a foto da conta em tamanhos fixos dentro de C:\Users\Public\AccountPictures\<SID> e
# aponta cada um no registro, por SID. Sem esses valores a tela de login e o Iniciar mostram o boneco padrão.
Etapa 'Foto do perfil' {
    $origem = Join-Path $aqui 'perfil\avatar.png'
    if (-not (Test-Path -LiteralPath $origem)) { throw "não achei $origem" }
    $sid = ([Security.Principal.NTAccount]"$env:USERDOMAIN\$env:USERNAME").Translate([Security.Principal.SecurityIdentifier]).Value
    $dir = Join-Path $env:PUBLIC "AccountPictures\$sid"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile($origem)
    try {
        $tamanhos = 32, 40, 48, 96, 192, 208, 240, 424, 448, 1080
        $chave = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\$sid"
        foreach ($t in $tamanhos) {
            $arq = Join-Path $dir "Image$t.png"
            $bmp = New-Object System.Drawing.Bitmap $t, $t
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.DrawImage($img, 0, 0, $t, $t)
            } finally { $g.Dispose() }
            $bmp.Save($arq, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            Set-Reg $chave "Image$t" $arq 'String'
        }
        Passo "$($tamanhos.Count) tamanhos em $dir"
    } finally { $img.Dispose() }
    # a cópia no perfil do usuário é a que o Iniciar usa quando o registro ainda não foi lido
    $meu = Join-Path $env:APPDATA 'Microsoft\Windows\AccountPictures'
    New-Item -ItemType Directory -Path $meu -Force | Out-Null
    Copy-Item -LiteralPath $origem -Destination (Join-Path $meu 'avatar.png') -Force
    Passo 'foto da conta aplicada; aparece no Iniciar e na tela de login'
}

# --- 10. Explorer em Detalhes (WinSetView) ------------------------------------------------------------
# WinSetView (Les Ferch, MIT) grava em HKCU os padrões de exibição de todos os tipos de pasta e reinicia o Explorer.
# O INI é o do Alexandre (explorer\WinSetView\README.md). Roda em outro processo: o script mexe em Set-Location e
# solta dezenas de linhas do reg.exe, que vão para um log próprio em vez do console.
Etapa 'Explorer em Detalhes (WinSetView)' {
    $wsv = Join-Path $aqui 'explorer\WinSetView'
    $ini = Join-Path $wsv 'AppData\Win10.ini'
    if (-not (Test-Path -LiteralPath $ini)) { throw "não achei $ini" }
    $ps1 = Join-Path $wsv 'WinSetView.ps1'
    $logWsv = Join-Path $env:USERPROFILE 'mywiniso-winsetview.log'
    Passo 'Detalhes em todas as pastas: Nome, Caminho, Data de modificação, Tipo, Tamanho; por nome, sem agrupar; extensões visíveis; menu clássico'
    Passo "log: $logWsv"
    # Start-Process em vez de chamar direto: as dezenas de linhas do reg.exe não entram em $Error (viraria AVISO)
    # -Wait porque só com ele o objeto traz ExitCode; a cópia versionada do WinSetView não abre janela no fim,
    # então não há descendente para segurar a espera
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$ps1`"", "`"$ini`"" `
        -Wait -PassThru -NoNewWindow -RedirectStandardOutput $logWsv -RedirectStandardError "$logWsv.err"
    if ($null -ne $p.ExitCode -and $p.ExitCode -ne 0) { throw "WinSetView.ps1 saiu com código $($p.ExitCode); veja $logWsv" }
    Passo 'aplicado; o Explorer foi reiniciado'
}

# --- 11. Windhawk: barra, Iniciar e central de notificações translúcidos, menus escuros, sem bordas --------
# Windhawk (winget) mais 5 mods, sem abrir a interface: desde o 1.7 os mods vêm precompilados de mods.windhawk.net e o
# motor lê HKLM\SOFTWARE\Windhawk\Engine\Mods\<id> e carrega o mod na hora, em todos os processos já injetados. Os temas
# Translucent (Undisputed00x) já vêm dentro dos Styler do m417z; só o setting "theme" precisa ser gravado. Cada mod:
# .wh.cpp em ModsSource (a interface lista por ele), a DLL em Engine\Mods\<bits>, e a chave com Include/Exclude/
# Architecture/Version/Settings; LibraryFileName por último, porque é ele que dispara a carga.
Etapa 'Windhawk: tema Translucent' {
    winget.exe install --id RamenSoftware.Windhawk --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { throw "winget não instalou o Windhawk (código $LASTEXITCODE)" }
    $wh = Join-Path $env:ProgramFiles 'Windhawk'
    if (-not (Test-Path -LiteralPath (Join-Path $wh 'windhawk.exe'))) { throw "não achei $wh\windhawk.exe" }
    $pd = Join-Path $env:ProgramData 'Windhawk'
    foreach ($d in 'ModsSource', 'Engine\Mods\64', 'Engine\Mods\32') { New-Item -ItemType Directory -Path (Join-Path $pd $d) -Force | Out-Null }
    # bibliotecas que a interface copiaria na primeira abertura; as DLLs precompiladas dos Styler dependem delas
    foreach ($alvo in @(@{ dir = 'x86_64-w64-mingw32'; bits = '64' }, @{ dir = 'i686-w64-mingw32'; bits = '32' })) {
        $bin = Join-Path $wh "Compiler\$($alvo.dir)\bin"
        foreach ($par in @(@('libc++.dll', 'libc++.whl'), @('libunwind.dll', 'libunwind.whl'), @('windhawk-mod-shim.dll', 'windhawk-mod-shim.dll'))) {
            $src = Join-Path $bin $par[0]; $dst = Join-Path $pd "Engine\Mods\$($alvo.bits)\$($par[1])"
            if ((Test-Path -LiteralPath $src) -and -not (Test-Path -LiteralPath $dst)) { Copy-Item -LiteralPath $src -Destination $dst -Force }
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $pd 'Engine\Mods\64\libc++.whl'))) {
        Falha 'não achei libc++.whl em Engine\Mods\64 (o Windhawk veio sem a pasta Compiler?); se a barra não ficar translúcida, abra o Windhawk uma vez, que ele copia essas bibliotecas'
    }
    # O tema TranslucentTaskbar pinta o fundo da barra com <WindhawkBlur TintColor="#25323232">: alpha 0x25,
    # uns 15%, que sobre wallpaper claro fica quase branco. Aqui o mesmo desfoque com um tint bem mais
    # escuro: 0xCC é 80% de um cinza quase preto. Para clarear de novo, baixe o primeiro par de dígitos.
    # Os dois alvos são os do próprio tema: o fundo da barra e o da bandeja que abre no hover.
    $TaskbarTint  = '#CC101010'
    $TaskbarFundo = "Fill:=<WindhawkBlur BlurAmount=`"18`" TintColor=`"$TaskbarTint`"/>"
    $mods = @(
        @{ id = 'windows-11-taskbar-styler';             settings = [ordered]@{
                theme                        = 'TranslucentTaskbar'
                xamlDiagnosticsHandling      = 'block'
                'controlStyles[0].target'    = 'Taskbar.TaskbarFrame > Grid#RootGrid > Taskbar.TaskbarBackground > Grid > Rectangle#BackgroundFill'
                'controlStyles[0].styles[0]' = $TaskbarFundo
                'controlStyles[1].target'    = 'Taskbar.TaskbarBackground#HoverFlyoutBackgroundControl > Grid > Rectangle#BackgroundFill'
                'controlStyles[1].styles[0]' = $TaskbarFundo
            } },
        @{ id = 'windows-11-start-menu-styler';          settings = @{ theme = 'TranslucentStartMenu' } },
        @{ id = 'windows-11-notification-center-styler'; settings = @{ theme = 'TranslucentShell' } },
        # Explorer e Configurações no mesmo Translucent escuro da barra. São dois mods que só funcionam
        # juntos, e o FAQ do próprio autor diz isso: o file-explorer-styler deixa transparente a parte WinUI
        # do Explorer, e o translucent-windows põe o desfoque escuro por trás de toda janela (Win32 e WinUI,
        # Configurações incluída). O styler sozinho é o "cinza lavado" que apareceu na primeira tentativa:
        # WinUI transparente sobre o fundo chapado do Win32. O tint é o mesmo da barra, $TaskbarTint.
        @{ id = 'translucent-windows';                   settings = [ordered]@{
                'RenderingMod.ThemeBackground'       = '1'
                'RenderingMod.SysColors'             = '0'
                'RenderingMod.AccentColorControls'   = '1'
                'BackgroundEffects.type'             = 'acrylicblur'
                'BackgroundEffects.AccentBlurBehind' = $TaskbarTint.TrimStart('#')
                'FlyoutsEffects'                     = '1'
            } },
        @{ id = 'windows-11-file-explorer-styler';       settings = @{ theme = 'Translucent Explorer11' } },
        @{ id = 'taskbar-thumbnail-reorder';             settings = @{} },   # arrastar a miniatura da barra com o botão esquerdo
        # Explorer abre em D: (Win+E e o pino da barra). O Windows só oferece Início, Este Computador e Downloads
        # (LaunchTo); pasta arbitrária só por este mod. Sem a partição Alexandre, abre em Este Computador.
        @{ id = 'change-explorer-default-location';      settings = @{ location = $(if ($Dados) { 'D:\' } else { 'shell:::{20D04FE0-3AEA-1069-A2D8-08002B30309D}' }) } },
        @{ id = 'dark-menus';                            settings = @{} },
        @{ id = 'invisible-borders';                     settings = @{} }
    )
    foreach ($m in $mods) {
        $id  = $m.id
        $src = Join-Path $pd "ModsSource\$id.wh.cpp"
        $dll = $null
        try {
            # fonte e DLL do mesmo servidor: o raw do GitHub pode anunciar uma versão que o mods.windhawk.net
            # ainda não compilou, e aí a URL da DLL daria 404
            $tmpSrc = Join-Path $env:TEMP "$id.wh.cpp"
            Baixar "https://mods.windhawk.net/mods/$id.wh.cpp" $tmpSrc
            $meta = @{}
            foreach ($l in (Get-Content -LiteralPath $tmpSrc -Encoding UTF8 -TotalCount 80)) {
                if ($l -match '^//\s*==/WindhawkMod==') { break }
                if ($l -match '^//\s*@(\w+)\s+(.+?)\s*$') { $meta[$Matches[1]] = @($meta[$Matches[1]]) + $Matches[2] }
            }
            $ver  = "$($meta['version'])".Trim()
            $arch = "$($meta['architecture'])".Trim()
            if (-not $ver) { throw "não achei @version no .wh.cpp" }
            $inc  = @($meta['include'] | Where-Object { $_ }) -join '|'
            $exc  = @($meta['exclude'] | Where-Object { $_ }) -join '|'
            $k    = "HKLM:\SOFTWARE\Windhawk\Engine\Mods\$id"
            $dllAntes = (Get-ItemProperty -LiteralPath $k -Name LibraryFileName -ErrorAction Ignore).LibraryFileName
            $verAntes = (Get-ItemProperty -LiteralPath $k -Name Version -ErrorAction Ignore).Version
            if (-not $dllAntes -or $verAntes -ne $ver) {
                $dll  = "${id}_${ver}_$(Get-Random -Minimum 100000 -Maximum 999999).dll"
                $bits = if ($arch -eq 'x86-64') { @('64') } else { @('64', '32') }
                foreach ($b in $bits) { Baixar "https://mods.windhawk.net/mods/$id/${ver}_$b.dll" (Join-Path $pd "Engine\Mods\$b\$dll") }
            } else { $dll = $dllAntes; Passo "$id $ver já registrado; só conferindo settings" }
            # a fonte só vai para ModsSource depois que a DLL existe, senão a interface lista uma versão que não roda
            Move-Item -LiteralPath $tmpSrc -Destination $src -Force
            Set-Reg $k 'Include'      $inc  'String'
            Set-Reg $k 'Exclude'      $exc  'String'
            Set-Reg $k 'Architecture' $arch 'String'
            Set-Reg $k 'Version'      $ver  'String'
            Set-Reg $k 'Disabled'     0
            foreach ($nome in $m.settings.Keys) { Set-Reg "$k\Settings" $nome $m.settings[$nome] 'String' }
            Set-Reg $k 'SettingsChangeTime' ([int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -band 0x7fffffff))
            Set-Reg $k 'LibraryFileName' $dll 'String'
            Passo ("{0} {1}: {2}{3}" -f $id, $ver, $(if ($m.settings.theme) { "tema $($m.settings.theme)" } else { 'ativo' }), $(if ($inc) { " em $inc" } else { '' }))
        } catch {
            # um mod que falha não leva os outros; DLL pela metade sai para não acumular lixo
            if ($dll) { Remove-Item -Path (Join-Path $pd "Engine\Mods\*\$dll") -Force -ErrorAction Ignore }
            Falha ("{0}: {1}" -f $id, $_.Exception.Message)
            continue
        }
    }
    # serviço e ícone da bandeja; o instalador silencioso pode não subir os dois na hora
    Start-Service -Name Windhawk -ErrorAction SilentlyContinue
    if (-not (Get-Process -Name windhawk -ErrorAction SilentlyContinue)) { Start-Process -FilePath (Join-Path $wh 'windhawk.exe') -ArgumentList '-tray-only' }
    Passo "serviço Windhawk: $((Get-Service -Name Windhawk -ErrorAction SilentlyContinue).Status)"

    # O Windhawk injeta em processo que sobe depois dele. O painel que abre ao clicar no relógio e a
    # central de notificações são desenhados pelo ShellExperienceHost, e o Iniciar pelo
    # StartMenuExperienceHost; os dois já estavam de pé quando os mods foram registrados, então ficavam
    # sem tema até o próximo logon. Era por isso que o Iniciar e o painel do relógio saíam sem estilo
    # enquanto a barra ficava certa: a barra é o Explorer, que a etapa 10 já tinha reiniciado.
    # O Windows sobe os dois sozinho em seguida.
    foreach ($proc in 'ShellExperienceHost', 'StartMenuExperienceHost') {
        if (Get-Process -Name $proc -ErrorAction Ignore) {
            Passo "reiniciando o $proc para o Windhawk injetar nele"
            Stop-Process -Name $proc -Force -ErrorAction Ignore
        }
    }
}

# --- 12. Energia: Desempenho Máximo, nunca suspender, nunca apagar a tela, sem hibernação -----------
Etapa 'Energia' {
    # Desempenho Máximo (Ultimate Performance) vem oculto no Windows 11; /duplicatescheme cria uma cópia visível.
    # Se a cópia já existe (segunda execução), reaproveita em vez de criar outra.
    $guid = $null
    $lista = (powercfg.exe /list 2>&1) -join "`n"
    if ($lista -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s+\((Desempenho M.ximo|Ultimate Performance)\)') {
        $guid = $Matches[1]; Passo "plano Desempenho Máximo já existe: $guid"
    } else {
        $saida = (powercfg.exe /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1) -join "`n"
        if ($saida -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { $guid = $Matches[1]; Passo "plano Desempenho Máximo criado: $guid" }
        else { $guid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; Passo 'Desempenho Máximo não disponível; usando Alto desempenho' }
    }
    powercfg.exe /setactive $guid
    Passo 'a máquina nunca suspende nem hiberna; a tela apaga depois de 5 minutos parada'
    powercfg.exe /change standby-timeout-ac 0
    powercfg.exe /change hibernate-timeout-ac 0
    powercfg.exe /change monitor-timeout-ac 5
    powercfg.exe /hibernate off
    Passo ((powercfg.exe /getactivescheme) -join ' ')

    # Memória, pelo hardware. 32 GB de RAM: pagefile fixo de 16 GB no C: (início = máximo, então nunca cresce
    # nem fragmenta no meio de um jogo, e ainda cabe um dump de kernel) e compressão de memória desligada (ela
    # gasta CPU para poupar RAM, que sobra). O que o Intelligent Standby List Cleaner faz, a limpeza da
    # standby list quando a RAM livre cai, é a tarefa 'Standby list' da etapa 28. Pagefile e compressão só
    # valem depois de reiniciar.
    $ramGB = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $pfMB  = [Math]::Max(4096, [Math]::Min(16384, [int]($ramGB * 512)))    # metade da RAM, entre 4 e 16 GB
    Passo "memória: $ramGB GB de RAM, pagefile fixo de $($pfMB / 1024) GB no C:, sem compressão de memória"
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cs.AutomaticManagedPagefile) { $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $false } }
    Get-CimInstance Win32_PageFileSetting | Where-Object Name -notlike 'C:*' | Remove-CimInstance
    $pf = Get-CimInstance Win32_PageFileSetting | Where-Object Name -like 'C:*'
    if ($pf) { $pf | Set-CimInstance -Property @{ InitialSize = $pfMB; MaximumSize = $pfMB } }
    else { New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = 'C:\pagefile.sys'; InitialSize = $pfMB; MaximumSize = $pfMB } | Out-Null }
    Silencioso { Disable-MMAgent -MemoryCompression }
}

# --- 13. Programas, um a um, com resultado ----------------------------------------------------------
# Instalador que recusa rodar elevado faz o winget sair com 0x8A150056 (INSTALLER_PROHIBITS_ELEVATION).
# O setup roda como administrador, então esses vão por uma tarefa agendada sem elevação. O do Spotify é o
# caso conhecido; se outro aparecer com esse código no resumo, é só acrescentar o id aqui.
$SemElevacao = @('Spotify.Spotify')
Etapa 'Programas (apps.json)' {
    if ($AppsArquivo -ne 'apps.json') { Passo "perfil $Perfil`: lendo $AppsArquivo em vez de apps.json" }
    $lista = Get-Content -LiteralPath (Join-Path $aqui $AppsArquivo) -Raw | ConvertFrom-Json
    $pacotes = @()
    foreach ($src in $lista.Sources) {
        foreach ($p in $src.Packages) { $pacotes += [pscustomobject]@{ Id = $p.PackageIdentifier; Fonte = $src.SourceDetails.Name } }
    }
    $i = 0
    foreach ($p in $pacotes) {
        $i++
        Write-Host ("  [{0,2}/{1}] {2} ({3})" -f $i, $pacotes.Count, $p.Id, $p.Fonte) -ForegroundColor White
        $argumentos = "install --id $($p.Id) --exact --source $($p.Fonte) --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"
        if ($SemElevacao -contains $p.Id) {
            Passo 'este instalador recusa administrador; vai por tarefa agendada sem elevação'
            # pelo powershell.exe, e não pelo winget.exe: o winget é um alias de execução de app em
            # WindowsApps, que a tarefa agendada nem sempre resolve pelo nome
            $codigo = Invoke-SemElevacao "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
                "-NoProfile -ExecutionPolicy Bypass -Command `"winget.exe $argumentos; exit `$LASTEXITCODE`""
        } else {
            winget.exe install --id $p.Id --exact --source $p.Fonte --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
            $codigo = $LASTEXITCODE
        }
        # A tarefa agendada do caminho sem elevação devolve o código SEM sinal: o mesmo 0x8A15002B de "já
        # instalado" chegava como 2316632107, não batia com a constante negativa e o Spotify entrava no
        # resumo como programa que falhou, a cada formatação. Normaliza os dois caminhos para Int32.
        if ($codigo -gt [int]::MaxValue) { $codigo = [int]($codigo - 4294967296) }
        # 0x8A15002B: instalado e sem atualização. 0x8A150114: instalado, mas quem atualiza é o próprio
        # programa (o Android Studio se atualiza sozinho e o winget diz isso). Nenhum dos dois é falha,
        # e repetir não muda nada: o winget já respondeu sobre o pacote, não sobre a rede.
        $JaInstalado = -1978335189, -1978334956
        # 0x8A150101/02/03: instalou, mas só fica pronto depois de reiniciar (ou o próprio winget já
        # reiniciaria). Não é falha e repetir não adianta -- o que falta é o reinício, tratado no fim.
        $ReiniciaDepois = -1978334975, -1978334974, -1978334973
        # Uma segunda tentativa antes de desistir, só para o que sobra. Falha de download não diz nada
        # sobre o pacote: o Proton Pass saiu com 0x80D05011 (a Delivery Optimization largou o download no
        # meio) numa rodada e instalou de primeira na seguinte, sem nada ter mudado. O winget install é
        # idempotente, então repetir não estraga nada. Só uma vez: erro que persiste é erro de verdade.
        if ($codigo -ne 0 -and $JaInstalado -notcontains $codigo -and $ReiniciaDepois -notcontains $codigo -and $SemElevacao -notcontains $p.Id) {
            Passo ("saiu com 0x{0:X8}; tentando mais uma vez" -f $codigo)
            Start-Sleep -Seconds 5
            winget.exe install --id $p.Id --exact --source $p.Fonte --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
            $codigo = $LASTEXITCODE
            if ($codigo -gt [int]::MaxValue) { $codigo = [int]($codigo - 4294967296) }
        }
        if ($codigo -eq 0)                    { Write-Host '        OK' -ForegroundColor Green }
        elseif ($codigo -eq -1978335189)      { Write-Host '        já instalado, sem atualização' -ForegroundColor DarkGray }
        elseif ($codigo -eq -1978334956)      { Write-Host '        já instalado; a atualização é pelo próprio programa' -ForegroundColor DarkGray }
        elseif ($ReiniciaDepois -contains $codigo) { Write-Host '        instalado; termina depois do reinício' -ForegroundColor DarkGray; $global:PedeReinicio = $true }
        else                                  { Falha ("{0}: winget saiu com código {1} (0x{2:X8})" -f $p.Id, $codigo, $codigo) }
    }
    Refresh-Path
    if ($Dados -and (Test-Path -LiteralPath $PerfilNoD)) {
        # instalador que abre o programa no fim (Discord, Spotify) deixa a pasta em uso; fecha para ela ir a D: agora
        Passo 'perfil do que acabou de ser instalado vai para D:'
        Stop-Process -Name Discord, Spotify, steam, chrome, Code, obsidian, Update -Force -ErrorAction Ignore
        Start-Sleep -Seconds 2
        & $PerfilNoD
    }
}

# --- 14. Claude Code: MCPs, plugins e skills (claude\mcps.json) ------------------------------------
# A etapa 4 instala o CLI; esta liga o que ele usa. Os MCPs de escopo user ficam em ~\.claude.json, que a
# etapa 7 já pôs em D: -- mas a formatação de 06/09/2026 mostrou que só isso não basta: o arquivo voltou sem
# nenhum mcpServers, e os pacotes npm globais de que eles dependem (Roaming\npm\node_modules) vieram vazios.
# A lista, então, é o repo (claude\mcps.json) e a etapa é determinística: instala o pacote npm de cada um se
# faltar, remove e registra de novo com claude mcp add-json. Pacote global e entrypoint pelo node, nunca
# npx @latest: o npx revalida na rede a cada partida e estoura o timeout de 30 s do Claude Code (medido no
# shadcn: 37 s). A chave do firecrawl vem de D:\Claude\.secrets\firecrawl.env, nunca do repo. Depois: o
# binário do engram (o plugin engram sobe por ele), o maestro (CLI de teste no emulador; ~\.maestro já fica
# em D: pela regra do perfil), os 4 marketplaces e plugins, e a conferência das skills, que moram em
# ~\.claude\skills e sobrevivem em D:. Fecha com claude mcp list, que tenta conectar em cada um.
Etapa 'Claude Code: MCPs, plugins e skills' {
    Refresh-Path
    if (-not (Get-Command claude -ErrorAction Ignore)) { throw 'o claude não está no PATH (etapa 4)' }
    $npmCmd = Get-Command npm.cmd -ErrorAction Ignore
    if (-not $npmCmd) { throw 'npm.cmd não está no PATH (o Node.js vem do apps.json, etapa 13)' }
    $central = if ($Dados) { Join-Path $Dados 'Claude' } else { $null }
    if ($central -and -not (Test-Path -LiteralPath $central)) { Falha "não achei $central (a central de orientações); obsidian e playwright ficam de fora"; $central = $null }
    if ($central) {
        # veio de antes da formatação com dono no SID da conta velha; sem isto o git recusa o repositório
        Silencioso { icacls.exe $central /setowner "$env:USERDOMAIN\$env:USERNAME" /T /C /Q 2>&1 | Out-Null }
    }
    $npmRaiz = Join-Path $env:APPDATA 'npm\node_modules'
    $java = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
    if (-not $java) { $java = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine') }
    $java = ([string]$java).TrimEnd('\')   # barra no fim não serve para nada e ainda vira escape dentro do JSON
    if (-not $java) {
        # o maestro só aceita JDK 17 ou 21; o 17 vem do apps.json (Temurin)
        $jdk = Get-ChildItem -LiteralPath 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-17*' -ErrorAction Ignore | Select-Object -First 1
        if ($jdk) { $java = $jdk.FullName; [Environment]::SetEnvironmentVariable('JAVA_HOME', $java, 'User'); Passo "JAVA_HOME = $java (usuário)" }
        else { Falha 'JAVA_HOME vazio e nenhum JDK 17 da Temurin em Program Files; o maestro fica sem Java' }
    }
    $lista = Get-Content -LiteralPath (Join-Path $aqui 'claude\mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    # 1. pacotes npm, globais (a pasta Roaming\npm também é de D: pela regra do perfil)
    foreach ($m in $lista | Where-Object { $_.npm }) {
        $pasta = Join-Path $npmRaiz ($m.npm -replace '@[\d^~.]+$', '')
        if (Test-Path -LiteralPath $pasta) { Passo "$($m.npm): já instalado"; continue }
        Passo "npm install -g $($m.npm)"
        Silencioso { & $npmCmd.Source install -g $m.npm --no-fund --no-audit --loglevel=error 2>&1 | Out-Host }
        if (-not (Test-Path -LiteralPath $pasta)) { Falha "npm não instalou $($m.npm)" }
    }

    # 2. engram: escrito em Go, mas o release traz o binário pronto. Vai para ~\.local\bin, que a regra do perfil leva para D:
    $bin = Join-Path $env:USERPROFILE '.local\bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    if (Test-Path -LiteralPath (Join-Path $bin 'engram.exe')) { Passo 'engram: já instalado' }
    else {
        try {
            $rel   = Invoke-RestMethod -Uri 'https://api.github.com/repos/Gentleman-Programming/engram/releases/latest' -Headers @{ 'User-Agent' = 'PowerShell' }
            $asset = $rel.assets | Where-Object { $_.name -like 'engram_*_windows_amd64.zip' } | Select-Object -First 1
            $zip   = Join-Path $env:TEMP 'engram.zip'
            $tmp   = Join-Path $env:TEMP 'engram'
            Baixar $asset.browser_download_url $zip
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
            Expand-Archive -Path $zip -DestinationPath $tmp -Force
            $exe = Get-ChildItem -LiteralPath $tmp -Recurse -Filter 'engram.exe' | Select-Object -First 1
            Copy-Item -LiteralPath $exe.FullName -Destination $bin -Force
            Passo "engram $($rel.tag_name) em $bin"
        } catch { Falha "engram: $($_.Exception.Message)" }
    }

    # 3. maestro em ~\.maestro (também em D: pela regra). São 315 MB: só quando falta.
    $maestroBin = Join-Path $env:USERPROFILE '.maestro\bin'
    if (Test-Path -LiteralPath (Join-Path $maestroBin 'maestro.bat')) { Passo 'maestro: já instalado' }
    else {
        try {
            $rel   = Invoke-RestMethod -Uri 'https://api.github.com/repos/mobile-dev-inc/maestro/releases/latest' -Headers @{ 'User-Agent' = 'PowerShell' }
            $asset = $rel.assets | Where-Object { $_.name -eq 'maestro.zip' } | Select-Object -First 1
            $zip   = Join-Path $env:TEMP 'maestro.zip'
            $tmp   = Join-Path $env:TEMP 'maestro-zip'
            Baixar $asset.browser_download_url $zip
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
            Expand-Archive -Path $zip -DestinationPath $tmp -Force
            $raiz = if (Test-Path -LiteralPath (Join-Path $tmp 'maestro\bin')) { Join-Path $tmp 'maestro' } else { $tmp }
            $dest = Split-Path $maestroBin -Parent
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            foreach ($sub in 'bin', 'lib') {
                Remove-Item -LiteralPath (Join-Path $dest $sub) -Recurse -Force -ErrorAction Ignore
                Copy-Item -LiteralPath (Join-Path $raiz $sub) -Destination $dest -Recurse -Force
            }
            Passo "maestro $($rel.tag_name) em $dest"
        } catch { Falha "maestro: $($_.Exception.Message)" }
    }
    # os dois no Path do usuário (o profile.ps1 também os põe na sessão)
    $pathUser = [Environment]::GetEnvironmentVariable('Path', 'User')
    foreach ($p in $bin, $maestroBin) { if (($pathUser -split ';') -notcontains $p) { $pathUser = "$pathUser;$p" } }
    [Environment]::SetEnvironmentVariable('Path', $pathUser.Trim(';'), 'User')
    Refresh-Path

    # 4. registro dos MCPs, escopo user
    $segredos = if ($central) { Join-Path $central '.secrets' } else { $null }
    # O JSON vai para o claude mcp add-json por -EncodedCommand do pwsh 7, e não como argumento daqui. Motivo,
    # medido: o setup roda no Windows PowerShell 5.1, e o 5.1 não entrega inteiro um argumento que tenha aspas
    # E espaço -- o add-json responde "Invalid configuration: : Invalid input". Vale para as duas formas, JSON
    # cru e com as aspas escapadas. Sete dos oito passavam por acaso (nenhum valor deles tem espaço); só o
    # maestro caía, pelo JAVA_HOME em "C:\Program Files\...". O -EncodedCommand é base64 de UTF-16: não passa
    # por parser de linha de comando nenhum, então espaço, aspas e acento chegam como estão. O pwsh 7 vem do
    # apps.json, na etapa 13, que roda antes desta.
    $pwsh = (Get-Command pwsh.exe -ErrorAction Ignore).Source
    if (-not $pwsh) { Falha 'pwsh 7 não está no PATH (vem do apps.json, etapa 13); MCP com espaço no valor pode não registrar' }
    $registrados = @()
    foreach ($m in $lista | Where-Object { $_.servidor }) {
        $json = $m.servidor | ConvertTo-Json -Compress -Depth 5
        if ($m.segredo) {
            $arq = if ($segredos) { Join-Path $segredos $m.segredo } else { '' }
            if (-not ($arq -and (Test-Path -LiteralPath $arq))) { Falha "$($m.nome): sem $($m.segredo) em D:\Claude\.secrets; fica de fora"; continue }
            foreach ($linha in Get-Content -LiteralPath $arq) {
                if ($linha -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.+?)\s*$') { $json = $json.Replace('{' + $Matches[1] + '}', $Matches[2]) }
            }
        }
        if ($json.Contains('{claude}') -and -not $central) { Falha "$($m.nome): precisa de D:\Claude; fica de fora"; continue }
        # as barras dobram porque a troca é no texto do JSON
        $json = $json.Replace('{npm}', $npmRaiz.Replace('\', '\\')).Replace('{home}', $env:USERPROFILE.Replace('\', '\\')).Replace('{java}', ([string]$java).Replace('\', '\\'))
        if ($central) { $json = $json.Replace('{claude}', $central.Replace('\', '\\')) }
        Silencioso { claude mcp remove $m.nome -s user 2>&1 | Out-Null }
        if ($pwsh) {
            # aspas simples dobradas: é assim que uma aspa simples entra numa string literal do PowerShell
            $cmd = "claude mcp add-json '$($m.nome)' '$($json.Replace("'", "''"))' -s user"
            $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
            $saida = Silencioso { & $pwsh -NoProfile -EncodedCommand $b64 2>&1 | Out-String }
        } else {
            $saida = Silencioso { claude mcp add-json $m.nome $json.Replace('"', '\"') -s user 2>&1 | Out-String }
        }
        if ($saida -match 'Added') { $registrados += $m.nome } else { Falha "$($m.nome): claude mcp add-json não confirmou ($(($saida -split "`n")[0]))" }
    }
    Passo "registrados: $($registrados -join ', ')"

    # 5. marketplaces e plugins: as pastas em ~\.claude\plugins\marketplaces já estão em D:; o que se perde é o registro
    foreach ($mk in 'JuliusBrussee/caveman', 'Gentleman-Programming/engram', 'firebase/agent-skills', 'expo/skills') {
        Silencioso { claude plugin marketplace add $mk 2>&1 | Out-Null }
    }
    foreach ($pl in 'caveman@caveman', 'engram@engram', 'firebase@firebase', 'expo@expo-plugins') {
        Silencioso { claude plugin install $pl 2>&1 | Out-Null }
        Silencioso { claude plugin enable  $pl 2>&1 | Out-Null }
    }
    # o MCP do plugin firebase sobe com "npx -y firebase-tools@latest": 30 s de partida nesta máquina, o
    # limite exato do Claude Code, e ele entrava como Failed. Apontar o entrypoint pelo node (o pacote já foi
    # instalado global acima) baixa para 18 s. O arquivo é do cache do plugin e volta ao original quando o
    # plugin atualiza -- por isso a correção é reaplicada a cada rodada, e não uma vez só.
    $fbEntry = Join-Path $npmRaiz 'firebase-tools\lib\bin\firebase.js'
    foreach ($mcpArq in Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.claude\plugins\cache\firebase') -Recurse -Filter '.mcp.json' -ErrorAction Ignore) {
        if (-not (Test-Path -LiteralPath $fbEntry)) { Falha 'firebase-tools global não está no lugar; o MCP do plugin firebase segue pelo npx'; break }
        $cfg = Get-Content -LiteralPath $mcpArq.FullName -Raw | ConvertFrom-Json
        if ($cfg.mcpServers.firebase.command -eq 'node') { Passo 'plugin firebase: já aponta para o node'; continue }
        $cfg.mcpServers.firebase.command = 'node'
        $cfg.mcpServers.firebase.args    = @($fbEntry, 'mcp', '--dir', '.')
        # WriteAllText e não Set-Content -Encoding UTF8: o do Windows PowerShell grava BOM, e com BOM o
        # carregador de plugin do Claude Code não lê o .mcp.json -- o servidor não falha, ele simplesmente
        # some da lista, que é pior de perceber. Medido nesta máquina.
        [IO.File]::WriteAllText($mcpArq.FullName, ($cfg | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        Passo "plugin firebase: $($mcpArq.FullName) apontado para o node (npx @latest estourava os 30 s)"
    }

    $known = Join-Path $env:USERPROFILE '.claude\plugins\known_marketplaces.json'
    $nomes = if (Test-Path -LiteralPath $known) { (Get-Content -LiteralPath $known -Raw | ConvertFrom-Json).PSObject.Properties.Name } else { @() }
    Passo "marketplaces: $($nomes -join ', ')"
    $cfgClaude = Join-Path $env:USERPROFILE '.claude\settings.json'
    $ligados = if (Test-Path -LiteralPath $cfgClaude) { $e = (Get-Content -LiteralPath $cfgClaude -Raw | ConvertFrom-Json).enabledPlugins; if ($e) { $e.PSObject.Properties | Where-Object { $_.Value } | ForEach-Object Name } }
    Passo "plugins ligados: $(if ($ligados) { $ligados -join ', ' } else { 'nenhum' })"

    # 6. skills: globais em ~\.claude\skills (D:); as de projeto vivem em cada repositório
    $skills = Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.claude\skills') -Directory -ErrorAction Ignore
    if ($skills) { Passo "skills: $($skills.Name -join ', ')" } else { Falha 'nenhuma skill em ~\.claude\skills: o D:\Perfil\Home\.claude não voltou?' }

    # 7. prova: o claude mcp list tenta conectar em cada um (os do claude.ai vêm com a conta)
    Passo 'claude mcp list (conecta em cada um; demora um pouco)'
    $lista2 = Silencioso { claude mcp list 2>&1 | Out-String }
    foreach ($l in ($lista2 -split "`n")) {
        if ($l -match '^(.+?):\s.*-\s.*(Connected|Failed|Needs authentication)') {
            $nome = $Matches[1].Trim(); $estado = $Matches[2]
            if ($estado -eq 'Connected') { Passo "  $nome`: conectado" }
            elseif ($estado -eq 'Needs authentication') { Passo "  $nome`: pede login (/mcp no Claude Code)" }
            else { Falha "$nome`: não conectou" }
        }
    }
}

# --- 15. Lightshot: um atalho só, Shift+PrintScreen -----------------------------------------------
# O Lightshot guarda tudo em HKCU\Software\Skillbrains\lightshot, e lê esses valores quando inicia.
# Tem três atalhos: o principal (selecionar área), salvar a tela toda e enviar a tela toda para o site.
# Aqui fica só o principal, em Shift+PrintScreen, e os outros dois desligados.
#   Hotkey_*_mod  = bits do RegisterHotKey: 1 ALT, 2 CTRL, 4 SHIFT, 8 WIN
#   Hotkey_*_vk   = virtual-key code: 44 = 0x2C = VK_SNAPSHOT (PrintScreen)
# A etapa 7 já pôs PrintScreenKeyForSnippingEnabled em 0, senão o Windows engole a tecla para a
# Ferramenta de Captura antes de o Lightshot ver. appFirstRun em 0 tira a janela de boas-vindas.
Etapa 'Lightshot: só Shift+PrintScreen' {
    $ls = 'HKCU:\Software\Skillbrains\lightshot'
    if (-not (Test-Path -LiteralPath $ls)) {
        Passo 'o Lightshot ainda não criou a chave dele; gravando os valores para ele achar no primeiro início'
    }
    Passo 'atalho principal: Shift+PrintScreen (selecionar área)'
    Set-Reg $ls 'Hotkey_main_mod'     4
    Set-Reg $ls 'Hotkey_main_vk'      44
    Set-Reg $ls 'Hotkey_main_enabled' 1
    Passo 'os outros dois atalhos desligados: salvar tela toda e enviar tela toda'
    Set-Reg $ls 'Hotkey_savefull_enabled'   0
    Set-Reg $ls 'Hotkey_uploadfull_enabled' 0
    Passo 'sem janela de boas-vindas, sem balão de aviso, em pt-BR'
    Set-Reg $ls 'appFirstRun'  0
    Set-Reg $ls 'ShowBubbles'  0
    Set-Reg $ls 'Locale' 'PT-BR' 'String'
    # se o Lightshot estiver rodando, ele só releria no próximo início
    if (Get-Process -Name Lightshot -ErrorAction Ignore) {
        Passo 'Lightshot está aberto; reiniciando para ele reler os atalhos'
        $exe = (Get-Process -Name Lightshot -ErrorAction Ignore | Select-Object -First 1).Path
        Stop-Process -Name Lightshot -Force -ErrorAction Ignore
        Start-Sleep -Seconds 1
        if ($exe -and (Test-Path -LiteralPath $exe)) { Start-Process -FilePath $exe }
    }
}

# --- 16. Chrome: senhas só no Proton Pass, e as duas extensões já instaladas -----------------------
# Por política de máquina (HKLM\SOFTWARE\Policies\Google\Chrome), que o Chrome lê no início:
#   PasswordManagerEnabled 0  desliga o cofre do Chrome inteiro: não oferece salvar, não preenche e
#                             não sugere senha forte. É o que faz o Proton Pass ficar sendo o único.
#   ExtensionInstallForcelist instala e mantém instaladas as extensões, sem pedir nada ao usuário.
# Efeito colateral aceito: o Chrome passa a mostrar "Gerenciado pela sua organização" nas
# configurações, e extensão de forcelist não pode ser desativada pela página de extensões.
$ChromeExtensoes = [ordered]@{
    'ghmbeldphafepmbegfdlkpapadhbakde' = 'Proton Pass'
    'ponfpcnoihfmfllpaingbgckeeldkhle' = 'Enhancer for YouTube'
}
Etapa 'Chrome e Discord: Proton Pass, extensões e Vencord' {
    $pol = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    Passo 'gerenciador de senhas do Chrome desligado (nao salva, nao preenche, nao sugere senha)'
    Set-Reg $pol 'PasswordManagerEnabled' 0
    Passo 'sem detecção de vazamento e sem preenchimento de cartão, que também puxam para o cofre do Chrome'
    Set-Reg $pol 'PasswordLeakDetectionEnabled' 0
    Set-Reg $pol 'AutofillCreditCardEnabled'    0

    $lista = "$pol\ExtensionInstallForcelist"
    $i = 0
    foreach ($id in $ChromeExtensoes.Keys) {
        $i++
        Passo "extensão $($ChromeExtensoes[$id]) ($id)"
        # o ";https://clients2.google.com/service/update2/crx" e a URL de update da Chrome Web Store
        Set-Reg $lista "$i" "$id;https://clients2.google.com/service/update2/crx" 'String'
    }

    # A configuração do Enhancer for YouTube não vem daqui: a extensão guarda tudo dentro do perfil do
    # Chrome (chrome.storage) e não tem política de managed storage, então não há como injetar de fora.
    # O backup fica com o Alexandre; a importação é na mão, em Opções > Importar configurações.

    $pp = Get-ChildItem 'C:\Program Files\Proton\Proton Pass', "$env:LOCALAPPDATA\Programs\Proton Pass" -ErrorAction Ignore | Select-Object -First 1
    if ($pp) { Passo 'Proton Pass para Windows instalado (veio do apps.json)' }
    else { Passo 'Proton Pass para Windows ainda não aparece; ele vem do apps.json na etapa 13' }

    # Discord com o Vencord do fork do Alexandre (github.com/eualexandrerrr/Vencord), que tem o plugin
    # goLiveBypass e o que mais ele puser em src/userplugins. Por isso não serve o instalador oficial: ele
    # injetaria o Vencord de fábrica. O caminho é o dos desenvolvedores: clonar, buildar e injetar o dist
    # local, que é o que "pnpm inject" faz (o installer roda com VENCORD_DEV_INSTALL=1 apontando para o
    # dist). O clone fica em ~\Projetos\Vencord e é refeito a cada formatação (uns 2 minutos); as
    # configurações (settings.json, quickCss, temas) ficam em %APPDATA%\Vencord, que a etapa 7 já pôs em D:.
    Passo 'Discord com o Vencord do fork eualexandrerrr/Vencord (plugins próprios inclusos)'
    Refresh-Path
    if (-not (Get-Command git.exe -ErrorAction Ignore) -or -not (Get-Command node.exe -ErrorAction Ignore)) {
        Falha 'Vencord: sem git ou node no PATH; rode o setup de novo depois de reiniciar'
    } elseif (-not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Discord'))) {
        Falha 'Vencord: o Discord não está instalado (apps.json); rode o setup de novo'
    } else {
        $vsrc = Join-Path $env:USERPROFILE 'Projetos\Vencord'
        try {
            if (Test-Path -LiteralPath (Join-Path $vsrc '.git')) { Passo 'git pull no fork'; git.exe -C $vsrc pull --ff-only }
            else { Passo "git clone do fork em $vsrc"; git.exe clone --progress https://github.com/eualexandrerrr/Vencord $vsrc }
            if ($LASTEXITCODE -ne 0) { throw "git saiu com código $LASTEXITCODE" }
            Passo ("fork no commit " + (git.exe -C $vsrc log -1 --format='%h %ad %s' --date=format:'%d/%m/%Y %H:%M'))
            # o pnpm vem pelo corepack, na versão que o package.json pede (packageManager); sem prompt
            $env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
            # O corepack já foi embutido no Node, mas saiu da distribuição (aqui o Node é 26 e a pasta
            # tem só node.exe, npm e npx), e o passo morria com "o termo 'corepack' não é reconhecido".
            # Ele continua publicado no npm, que vem junto com o Node: instala uma vez e o resto segue
            # igual, ainda pegando do packageManager a versão do pnpm, em vez de fixar uma aqui.
            if (-not (Get-Command corepack -ErrorAction Ignore)) {
                Passo 'este Node não traz o corepack embutido; instalando pelo npm'
                & npm.cmd install -g corepack 2>&1 | Out-Host
                Refresh-Path
                if (-not (Get-Command corepack -ErrorAction Ignore)) { throw 'corepack não entrou nem pelo npm' }
            }
            Get-Process -Name Discord -ErrorAction Ignore | Stop-Process -Force -ErrorAction Ignore
            Push-Location $vsrc
            try {
                # Silencioso nos três: o pnpm escreve o progresso todo em stderr, e o 2>&1 daqui faz o
                # Windows PowerShell 5.1 virar cada linha dessas em registro de erro. Com o corepack
                # funcionando, a etapa passou a fechar em AVISO exibindo "Successfully patched ...\Discord"
                # como se fosse defeito. Quem diz se deu certo é o código de saída, conferido logo abaixo,
                # e ele atravessa o Silencioso intacto.
                Passo 'pnpm install'
                Silencioso { & corepack pnpm install --frozen-lockfile 2>&1 | Out-Host }
                if ($LASTEXITCODE -ne 0) { throw "pnpm install saiu com código $LASTEXITCODE" }
                Passo 'pnpm build'
                Silencioso { & corepack pnpm build 2>&1 | Out-Host }
                if ($LASTEXITCODE -ne 0) { throw "pnpm build saiu com código $LASTEXITCODE" }
                Passo 'pnpm inject (injeta o dist local no Discord stable, sem perguntar)'
                Silencioso { & corepack pnpm inject --branch stable 2>&1 | Out-Host }
                if ($LASTEXITCODE -ne 0) { throw "pnpm inject saiu com código $LASTEXITCODE" }
            } finally { Pop-Location }
            Passo 'Vencord injetado; o Discord abre já com ele'
        } catch { Falha "Vencord: $($_.Exception.Message)" }
    }
}

# --- 17. RedM ----------------------------------------------------------------------------------------
# O RedM.exe do site é um bootstrapper: no primeiro clique ele cria o RedM.app ao lado de si mesmo e
# baixa o jogo, uns GB, numa janela própria. Não existe instalação silenciosa: o binário só entende
# -ctracpkm, nada de /S nem /quiet, e a página do CitizenFX não documenta nenhum. Então o setup faz o que
# dá para fazer sozinho: põe o executável numa casa definitiva (não na área de trabalho, que desde a
# etapa 7 não mostra ícone nenhum) e cria o atalho no menu Iniciar, que é o caminho estável que a etapa
# 24 fixa na barra. O que sobra para você é um clique.
Etapa 'Jogos: RedM e biblioteca do Steam' {
    # com a partição Dados, o RedM (e o RedM.app que ele cria ao lado) vive em D:\Jogos e sobrevive à formatação
    $dir = if ($Dados) { Join-Path $Dados 'Jogos\RedM' } else { Join-Path $env:LOCALAPPDATA 'RedM' }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $exe = Join-Path $dir 'RedM.exe'
    Baixar 'https://runtime.fivem.net/redm/RedM.exe' $exe
    $lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\RedM.lnk'
    $atalho = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    $atalho.TargetPath       = $exe
    $atalho.WorkingDirectory = $dir
    $atalho.Description      = 'RedM'
    $atalho.Save()
    Passo "RedM em $exe"
    Passo "atalho em $lnk (é por ele que a barra fixa o RedM)"
    # a versão anterior deixava o instalador na área de trabalho; sai, que agora não aparece mesmo
    Remove-Item -LiteralPath (Join-Path $desktop 'RedM.exe') -Force -ErrorAction Ignore
    Passo 'sem modo silencioso: o primeiro clique baixa o jogo numa janela própria'

    if ($Dados) {
        # Biblioteca do Steam em D:\Jogos\Steam. O Steam só cria o steamapps\libraryfolders.vdf na primeira
        # abertura; se ele ainda não existe, este esqueleto entra antes e o Steam o completa (contentid,
        # totalsize, apps) sozinho ao abrir. Se já existe, o Steam já rodou e mexer por fora corrompe: aí a
        # pasta é adicionada à mão, em Configurações > Armazenamento. Marcar como padrão é um clique lá.
        # Depois de uma formatação a biblioteca em D: volta inteira: o Steam relê e não baixa de novo.
        $biblio = Join-Path $Dados 'Jogos\Steam'
        New-Item -ItemType Directory -Path (Join-Path $biblio 'steamapps') -Force | Out-Null
        $steam = 'C:\Program Files (x86)\Steam'
        $vdf   = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $steam) {
            # login lembrado, configurações e saves na nuvem local (userdata) e config: em D:, pela mesma junção
            # do perfil. O Steam ainda não abriu nesta altura, então as duas pastas nascem já em D:.
            foreach ($j in 'config', 'userdata') {
                $para = Join-Path $biblio "_perfil\$j"
                try { Passo ("  Steam\{0} -> {1}: {2}" -f $j, $para, (Junction (Join-Path $steam $j) $para)) }
                catch { Falha "Steam\$j : $($_.Exception.Message)" }
            }
        }
        if (-not (Test-Path -LiteralPath $steam)) { Passo 'Steam não está instalado; a biblioteca em D: fica para a próxima rodada' }
        elseif (Test-Path -LiteralPath $vdf) { Passo "o Steam já rodou; adicione $biblio em Configurações > Armazenamento e marque como padrão" }
        else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $vdf) -Force | Out-Null
            $q = [char]34
            $linhas = @('"libraryfolders"', '{',
                        "`t`"0`"", "`t{", "`t`t`"path`"`t`t`"$($steam -replace '\\', '\\')`"", "`t`t`"label`"`t`t`"`"", "`t}",
                        "`t`"1`"", "`t{", "`t`t`"path`"`t`t`"$($biblio -replace '\\', '\\')`"", "`t`t`"label`"`t`t`"`"", "`t}",
                        '}')
            [IO.File]::WriteAllLines($vdf, $linhas, [Text.Encoding]::ASCII)
            Passo "biblioteca do Steam semeada em $biblio; em Configurações > Armazenamento, marque-a como padrão"
        }
    }
}

# --- 18. Git -----------------------------------------------------------------------------------------
Etapa 'git config' {
    git.exe config --global user.name  'Alexandre Rangel'
    git.exe config --global user.email 'mamutal91@gmail.com'
    git.exe config --global init.defaultBranch main
    Passo "user.name=$(git.exe config --global user.name) user.email=$(git.exe config --global user.email)"
}

# --- 19. Office LTSC 2024 (Office Deployment Tool + office\Configuracao.xml) -------------------------
Etapa 'Office' {
    $odt = Join-Path $env:TEMP 'odt'
    New-Item -ItemType Directory -Path $odt -Force | Out-Null
    Baixar 'https://officecdn.microsoft.com/pr/wsus/setup.exe' (Join-Path $odt 'setup.exe')
    $cfg = Join-Path $aqui 'office\Configuracao.xml'
    Passo "setup.exe /configure $cfg (baixa uns 3 GB da Microsoft; demora)"
    $p = Start-Process -FilePath (Join-Path $odt 'setup.exe') -ArgumentList "/configure `"$cfg`"" -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "setup.exe do Office saiu com código $($p.ExitCode)" }
    Passo 'instalado'
}

# --- 20. Área de Trabalho Remota (este PC como host), senha sem validade, scripts liberados -----------
Etapa 'Área de Trabalho Remota e contas' {
    Passo 'RDP ligado com autenticação de rede; regra de firewall'
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 0
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication' 1
    Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'   # grupo "Área de Trabalho Remota", nome neutro de idioma
    if (-not $Senha) { Passo 'AVISO: conta sem senha; o RDP não aceita login até você definir uma (net user Alexandre *)' }
    Passo 'senha sem validade, sem bloqueio de conta, scripts .ps1 liberados (RemoteSigned)'
    net.exe accounts /maxpwage:unlimited | Out-Null
    net.exe accounts /lockoutthreshold:0 | Out-Null
    try { Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop }
    catch {
        if ($Error.Count) { $Error.RemoveAt(0) }
        Passo "Set-ExecutionPolicy recusou ($($_.Exception.Message.Trim())); gravando no registro"
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' 'ExecutionPolicy' 'RemoteSigned' 'String'
    }
}

# --- 21. NVIDIA App (não está no winget; instalador silencioso com /s) ------------------------------
Etapa 'NVIDIA App' {
    $url = 'https://us.download.nvidia.com/nvapp/client/11.0.9.251/NVIDIA_app_v11.0.9.251.exe'   # reserva, caso a página mude
    try {
        $html = (Invoke-WebRequest -UseBasicParsing -UserAgent 'Mozilla/5.0' -Uri 'https://www.nvidia.com/en-us/software/nvidia-app/' -TimeoutSec 30).Content
        if ($html -match 'https://[a-z.]*download\.nvidia\.com/nvapp/client/[0-9.]+/NVIDIA_app_v[0-9.]+\.exe') { $url = $Matches[0]; Passo 'URL atual lida da página da NVIDIA' }
        else { Passo 'página da NVIDIA sem link reconhecível; usando a URL de reserva' }
    } catch { Passo "página da NVIDIA inacessível ($($_.Exception.Message)); usando a URL de reserva" }
    $exe = Join-Path $env:TEMP 'NVIDIA_app.exe'
    Baixar $url $exe
    Passo 'instalando com /s (silencioso)'
    $p = Start-Process -FilePath $exe -ArgumentList '/s' -Wait -PassThru
    Remove-Item $exe -Force -ErrorAction Ignore
    if ($p.ExitCode -ne 0) { Falha "NVIDIA App: instalador saiu com código $($p.ExitCode) (sem placa NVIDIA é esperado); instale pelo nvidia.com" }
    else { Passo 'NVIDIA App instalado' }
}

# --- 22. MariaDB: serviço automático, root com a senha da conta e acesso remoto ---------------------
Etapa 'MariaDB' {
    $maria = Get-ChildItem -Path 'C:\Program Files\MariaDB*' -Directory -ErrorAction Ignore | Select-Object -First 1
    if (-not $maria) { throw 'não instalado (MariaDB.Server falhou no winget?)' }
    $bin = Join-Path $maria.FullName 'bin'
    Passo "em $($maria.FullName)"
    # Os bancos moram em D:\Perfil\MariaDB\data quando a partição Alexandre existe: sobrevivem à formatação.
    # Na reinstalação o data dir já está lá (tem a pasta mysql\ dentro), e aí não se roda o install-db, que
    # se recusaria; só se registra o serviço em cima dele, com um my.ini apontando o datadir. A senha do
    # root já está gravada dentro do data dir; o ALTER USER abaixo entra pelo caminho "já configurado".
    $data = if ($Dados) { Join-Path $Dados 'Perfil\MariaDB\data' } else { Join-Path $maria.FullName 'data' }
    if (-not (Get-Service -Name MariaDB -ErrorAction Ignore)) {
        if (Test-Path -LiteralPath (Join-Path $data 'mysql')) {
            Passo "bancos de antes da formatação em $data; registrando o serviço em cima deles"
            $ini = Join-Path (Split-Path $data -Parent) 'my.ini'
            "[mysqld]`r`ndatadir=$($data -replace '\\', '/')`r`n" | Set-Content -LiteralPath $ini -Encoding ASCII
            $daemon = @('mariadbd.exe', 'mysqld.exe') | ForEach-Object { Join-Path $bin $_ } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            & $daemon --install MariaDB "--defaults-file=$ini"
            if ($LASTEXITCODE -ne 0) { throw "$(Split-Path $daemon -Leaf) --install saiu com código $LASTEXITCODE" }
        } else {
            Passo "serviço MariaDB não existe; criando data dir em $data e o serviço"
            if ((Test-Path -LiteralPath $data) -and -not $Dados) { Remove-Item -LiteralPath $data -Recurse -Force }
            New-Item -ItemType Directory -Path (Split-Path $data -Parent) -Force | Out-Null
            $args = @("--datadir=$data", '--service=MariaDB')
            if ($Senha) { $args += "--password=$Senha" }
            & (Join-Path $bin 'mariadb-install-db.exe') @args
            if ($LASTEXITCODE -ne 0) { throw "mariadb-install-db saiu com código $LASTEXITCODE" }
        }
    }
    Set-Service -Name MariaDB -StartupType Automatic
    Start-Service -Name MariaDB
    Start-Sleep -Seconds 5
    Passo "serviço: $((Get-Service -Name MariaDB).Status)"
    if ($Senha) {
        $sql = "ALTER USER 'root'@'localhost' IDENTIFIED BY '$Senha'; CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$Senha'; GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;"
        # Silencioso, e não só 2>$null: quando o root já tem senha esta primeira tentativa TEM de falhar,
        # e o 2>$null esconde a linha da tela mas o Windows PowerShell 5.1 guarda o stderr do programa
        # nativo em $Error do mesmo jeito. A etapa então fechava em AVISO com o "ERROR 1045 Access denied"
        # logo depois de ter escrito que o root ficou com senha, que é justamente o contrário do ocorrido.
        Silencioso { & (Join-Path $bin 'mysql.exe') -u root -e $sql 2>$null }            # root ainda sem senha
        if ($LASTEXITCODE -ne 0) { & (Join-Path $bin 'mysql.exe') -u root "-p$Senha" -e $sql }   # já configurado antes
        if ($LASTEXITCODE -ne 0) { throw 'não consegui definir a senha do root' }
        Passo 'root com senha, acesso local e remoto'
    } else {
        Passo 'sem senha: root sem senha, só local'
    }

    # HeidiSQL guarda sessões e preferências no registro (HKCU\Software\HeidiSQL), que a formatação leva.
    # Com um portable_settings.txt ao lado do heidisql.exe ele passa a gravar nesse arquivo; o arquivo é um
    # symlink para D:\Perfil\HeidiSQL, então as conexões salvas voltam junto com os bancos.
    if ($Dados) {
        $heidi = Get-ChildItem 'C:\Program Files\HeidiSQL', "$env:LOCALAPPDATA\Programs\HeidiSQL" -Filter heidisql.exe -ErrorAction Ignore | Select-Object -First 1
        if ($heidi) {
            $alvo = Join-Path $Dados 'Perfil\HeidiSQL\portable_settings.txt'
            New-Item -ItemType Directory -Path (Split-Path $alvo -Parent) -Force | Out-Null
            if (-not (Test-Path -LiteralPath $alvo)) { New-Item -ItemType File -Path $alvo -Force | Out-Null }
            $link = Join-Path $heidi.DirectoryName 'portable_settings.txt'
            $it = Get-Item -LiteralPath $link -ErrorAction Ignore
            if (-not ($it -and ($it.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
                Remove-Item -LiteralPath $link -Force -ErrorAction Ignore
                try { New-Item -ItemType SymbolicLink -Path $link -Target $alvo -ErrorAction Stop | Out-Null; Passo "HeidiSQL em modo portátil, sessões em $alvo" }
                catch { Falha "HeidiSQL portable_settings.txt: $($_.Exception.Message)" }
            } else { Passo 'HeidiSQL já em modo portátil' }
        } else { Passo 'HeidiSQL não instalado; fica para a próxima rodada' }
    }
}

# --- 23. Fonte Cascadia Mono (máquina), console e VS Code ---------------------------------------------
Etapa 'Fontes, console e VS Code' {
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/cascadia-code/releases/latest' -Headers @{ 'User-Agent' = 'PowerShell' }
    $asset = $rel.assets | Where-Object { $_.name -like 'CascadiaCode-*.zip' } | Select-Object -First 1
    Passo "microsoft/cascadia-code release $($rel.tag_name): $($asset.name)"
    $zip = Join-Path $env:TEMP 'CascadiaCode.zip'
    $tmp = Join-Path $env:TEMP 'CascadiaCode'
    Baixar $asset.browser_download_url $zip
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    Add-Type -AssemblyName PresentationCore
    $regFontes = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    $n = 0
    foreach ($f in Get-ChildItem -Path $tmp -Recurse -Filter 'CascadiaMono-*.ttf' | Where-Object FullName -like '*static*') {
        $dest = Join-Path $env:WINDIR "Fonts\$($f.Name)"
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        try {
            $gt = [System.Windows.Media.GlyphTypeface]::new([Uri]$dest)
            $familia = $gt.Win32FamilyNames.Values | Select-Object -First 1
            $face    = $gt.Win32FaceNames.Values   | Select-Object -First 1
            $nome = if ($face -and $face -ne 'Regular') { "$familia $face" } else { $familia }
        } catch {
            # o construtor do GlyphTypeface falha em algumas fontes; o nome sai do arquivo e o erro não vira AVISO
            if ($Error.Count) { $Error.RemoveAt(0) }
            $partes  = $f.BaseName -split '-', 2
            $familia2 = $partes[0] -creplace '(?<=[a-z])(?=[A-Z])', ' '
            $face2    = if ($partes.Count -gt 1) { $partes[1] -creplace '(?<=[a-z])(?=Italic)', ' ' } else { '' }
            $nome = if ($face2 -and $face2 -ne 'Regular') { "$familia2 $face2" } else { $familia2 }
        }
        Set-ItemProperty -Path $regFontes -Name "$nome (TrueType)" -Value $f.Name -Type String
        $n++
    }
    Passo "$n arquivos de fonte instalados em C:\Windows\Fonts"
    $consoles = @('HKCU:\Console', 'HKCU:\Console\%SystemRoot%_System32_WindowsPowerShell_v1.0_powershell.exe', 'HKCU:\Console\Git Bash', 'HKCU:\Console\Git CMD')
    $pwsh = (Get-Command pwsh.exe -ErrorAction Ignore).Source
    if ($pwsh) { $consoles += "HKCU:\Console\$($pwsh -replace '\\', '_')" }
    foreach ($c in $consoles) {
        Set-Reg $c 'FaceName'   'Cascadia Mono' 'String'
        Set-Reg $c 'FontFamily' 54
        Set-Reg $c 'FontWeight' 400
        Set-Reg $c 'FontSize'   (19 -shl 16)
    }
    Passo "console: Cascadia Mono 19 em $($consoles.Count) perfis"
    $vsDir = Join-Path $env:APPDATA 'Code\User'
    $vsArq = Join-Path $vsDir 'settings.json'
    New-Item -ItemType Directory -Path $vsDir -Force | Out-Null
    $atual = if (Test-Path -LiteralPath $vsArq) { Get-Content -LiteralPath $vsArq -Raw | ConvertFrom-Json } else { New-Object PSObject }
    $novo  = Get-Content -LiteralPath (Join-Path $aqui 'vscode\settings.json') -Raw | ConvertFrom-Json
    foreach ($p in $novo.PSObject.Properties) { $atual | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    $atual | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $vsArq -Encoding UTF8
    Passo "VS Code: $vsArq"
}

# --- 24. Um perfil só para todo PowerShell (powershell\profile.ps1) ---------------------------------
# O 5.1 e o 7, em qualquer host (Windows Terminal, VS Code, console solto, elevado ou não), carregam o mesmo
# arquivo: o do 7 é a cópia do repo, e o do Windows PowerShell só aponta para ele -- pelo $PSScriptRoot, porque
# Documentos está em D: e "$HOME\Documents" não existe (era assim, e o 5.1 abria sem perfil nenhum). O
# starship.toml, o mesmo do zsh do Debian, vai para D:\Perfil\Home\.config, onde o profile.ps1 e o zshrc o
# procuram; o histórico do PSReadLine também fica em D:\Perfil\Home, um arquivo para todos os hosts.
Etapa 'Um perfil só para todo PowerShell' {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    New-Item -ItemType Directory -Path (Join-Path $docs 'PowerShell'), (Join-Path $docs 'WindowsPowerShell') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $aqui 'powershell\profile.ps1') -Destination (Join-Path $docs 'PowerShell\profile.ps1') -Force
    Set-Content -LiteralPath (Join-Path $docs 'WindowsPowerShell\profile.ps1') -Value '. "$PSScriptRoot\..\PowerShell\profile.ps1"' -Encoding UTF8
    Passo "$docs\PowerShell\profile.ps1; o do Windows PowerShell aponta para ele"
    if ($Dados) {
        $cfg = Join-Path $Dados 'Perfil\Home\.config'
        New-Item -ItemType Directory -Path $cfg -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $aqui 'terminal\starship.toml') -Destination (Join-Path $cfg 'starship.toml') -Force
        Passo "$cfg\starship.toml: o prompt do PowerShell 5.1, do 7 e do zsh do Debian"
        Passo "histórico: $(Join-Path $Dados 'Perfil\Home\.ps_history'), um só para todos os hosts"
    } else { Passo 'sem a partição Dados: starship com o prompt padrão dele e histórico por host' }
    if (-not (Get-Command starship -ErrorAction Ignore)) { Falha 'starship não está no PATH (vem do apps.json, etapa 13); o perfil cai no prompt simples' }
}

# --- 25. Barra de tarefas (taskbar\LayoutModification.xml) e tarefa "Startup OnLogon" ---------------
Etapa 'Barra de tarefas e tarefa de logon' {
    $layout = Join-Path $aqui 'taskbar\LayoutModification.xml'
    foreach ($shell in (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Shell'), 'C:\Users\Default\AppData\Local\Microsoft\Windows\Shell') {
        New-Item -ItemType Directory -Path $shell -Force | Out-Null
        Copy-Item -LiteralPath $layout -Destination (Join-Path $shell 'LayoutModification.xml') -Force
    }
    $taskband = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
    foreach ($n in 'Favorites', 'FavoritesResolve', 'FavoritesChanges', 'FavoritesVersion') {
        Remove-ItemProperty -Path $taskband -Name $n -ErrorAction Ignore      # força o Explorer a reler o layout
    }
    Passo 'pinos: Explorer, Firefox, Discord, VS Code, WinSCP, Chrome (aparecem quando o Explorer reiniciar)'
    # o script fica no próprio clone: o git pull atualiza a tarefa, e não depende do Google Drive estar sincronizado
    $onlogon = Join-Path $aqui 'startup\startup-onlogon.ps1'
    $acao      = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$onlogon`""
    $gatilho   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $gatilho.Delay = 'PT30S'
    $config    = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName 'Startup OnLogon' -Action $acao -Trigger $gatilho -Settings $config -Principal $principal -Force | Out-Null
    Passo "tarefa 'Startup OnLogon': $onlogon, 30 s depois de entrar"
    Passo 'reiniciando o Explorer para aplicar tema, barra e wallpaper'
    Stop-Process -Name explorer -Force -ErrorAction Ignore
}

# --- 26. Resto dos drivers e as atualizações, pelo Windows Update -------------------------------------------------
Etapa 'Windows Update (drivers)' {
    Silencioso { Install-PackageProvider -Name NuGet -Force -Scope AllUsers | Out-Null }
    # O Set-PSRepository do PowerShellGet 5.1 reclama de 'PackageManagementProvider' e de 'SourceLocation'
    # quando o PSGallery foi registrado por uma versão mais nova do PackageManagement. A confiança é aplicada
    # de todo jeito, e o que vem depois só depende dela: se o PSGallery ficar mesmo inacessível, o
    # Import-Module abaixo falha e a etapa fecha em ERRO, que é o certo. Silencioso só tira o ruído.
    Silencioso { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted }
    Silencioso { Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers }
    Import-Module PSWindowsUpdate
    # UpdateMicrosoftProducts (Sophia): o Microsoft Update traz também Office, .NET e o resto, não só o Windows
    Silencioso { Add-WUServiceManager -MicrosoftUpdate -Confirm:$false | Out-Null }
    Passo 'procurando e instalando o resto das atualizações e drivers (o de vídeo já veio na etapa 5)'
    Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot | Out-Host

    # Ativação. Esta máquina tem licença digital do Windows 11 Pro gravada no hardware (canal Retail,
    # "ativada permanentemente"): reinstalando a mesma edição no mesmo PC, a Microsoft reativa sozinha
    # quando há rede. Aqui só se pede a ativação agora (slmgr /ato) em vez de esperar o Windows
    # lembrar, e o estado vai para o resumo. Nada de chave nem de ativador: não precisa.
    Passo 'ativação do Windows pela licença digital do hardware'
    Silencioso { cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato 2>&1 | Out-Null }
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" -ErrorAction Ignore | Select-Object -First 1
    if ($lic -and $lic.LicenseStatus -eq 1) { Passo "Windows ativado ($($lic.ProductKeyChannel), chave ...$($lic.PartialProductKey))" }
    else { Falha "Windows ainda não ativado (status $($lic.LicenseStatus)); a licença digital reativa sozinha com rede, confira em Configurações > Sistema > Ativação" }
}

# --- 27. Windows Terminal: um terminal só, sempre atualizado (terminal\settings.json) ---------------
# No Windows dá para abrir console de vários lugares (cmd, Windows PowerShell, PowerShell 7, Git Bash, WSL) e
# cada um abria numa janela diferente. Aqui o Windows Terminal passa a ser o console padrão do sistema: tudo que
# abrir console aparece nele, em abas, e os cinco shells ficam num menu só. O padrão é o PowerShell 7.
Etapa 'Windows Terminal como terminal único' {
    winget.exe install --id Microsoft.WindowsTerminal --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { Falha "winget não instalou o Windows Terminal (código $LASTEXITCODE)" }
    Passo 'procurando versão mais nova'
    winget.exe upgrade --id Microsoft.WindowsTerminal --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    $pacote = Get-AppxPackage -Name 'Microsoft.WindowsTerminal' -ErrorAction Ignore | Select-Object -First 1
    if ($pacote) { Passo "Windows Terminal $($pacote.Version)" } else { throw 'o Windows Terminal não aparece instalado' }

    $estado = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    New-Item -ItemType Directory -Path $estado -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $aqui 'terminal\settings.json') -Destination (Join-Path $estado 'settings.json') -Force
    Passo "perfis: PowerShell 7 (padrão), Windows PowerShell, Prompt de Comando, Debian com zsh e Git Bash"

    # console padrão do Windows: os dois CLSIDs são do Windows Terminal
    $inicio = 'HKCU:\Console\%%Startup'
    Set-Reg $inicio 'DelegationConsole'  '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}' 'String'
    Set-Reg $inicio 'DelegationTerminal' '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}' 'String'
    Passo 'qualquer console do Windows abre no Windows Terminal'
}

# --- 28. Manutenção: limpeza recorrente, espaço em disco e telemetria de fundo ---------------------
# Vem do Sophia Script (farag2), que trata isso melhor que qualquer outra ferramenta. Três tarefas agendadas
# que rodam sozinhas, o armazenamento reservado liberado (~7 GB), o compartilhamento P2P de updates desligado
# e as dez tarefas de telemetria que rodam em segundo plano. A pior delas, o Compatibility Appraiser, varre o
# disco inteiro e trava a máquina por minutos.
Etapa 'Manutenção e telemetria de fundo' {
    Passo 'tarefas de telemetria e diagnóstico que rodam em segundo plano'
    $paradas = 0
    foreach ($t in 'MareBackup', 'Microsoft Compatibility Appraiser', 'Microsoft Compatibility Appraiser Exp',
                   'StartupAppTask', 'Proxy', 'Consolidator', 'UsbCeip', 'BthSQM', 'AitAgent', 'ProgramDataUpdater',
                   'Microsoft-Windows-DiskDiagnosticDataCollector', 'MapsToastTask', 'MapsUpdateTask',
                   'QueueReporting', 'Device', 'Device User', 'KernelCeipTask', 'Uploader') {
        $tarefa = Get-ScheduledTask -TaskName $t -ErrorAction Ignore
        if ($tarefa) { $tarefa | Disable-ScheduledTask -ErrorAction Ignore | Out-Null; $paradas++ }
    }
    Passo "$paradas tarefas desabilitadas"

    Passo 'armazenamento reservado liberado (uns 7 GB)'
    try { Set-WindowsReservedStorageState -State Disabled -ErrorAction Stop }
    catch { Falha "armazenamento reservado em uso; rode de novo depois de um reinício: $($_.Exception.Message)" }

    Passo 'sem compartilhar updates com a internet (o Windows para de servir bytes para desconhecidos)'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    Set-Reg 'Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings' 'DownloadMode' 0

    Passo 'backup periódico do registro (voltou a existir; a Microsoft desligou no 1803)'
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager' 'EnablePeriodicBackup' 1
    Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance' -Name MaintenanceDisabled -Force -ErrorAction Ignore
    Get-ScheduledTask -TaskName RegIdleBackup -ErrorAction Ignore | Enable-ScheduledTask -ErrorAction Ignore | Out-Null

    Passo 'Sensor de Armazenamento: esvazia a Lixeira depois de 30 dias'
    $ss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
    Set-Reg $ss '01'   1
    Set-Reg $ss '04'   1
    Set-Reg $ss '2048' 30

    Passo 'nada de "desbloquear" arquivo baixado da internet'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments' 'SaveZoneInformation' 1

    Passo 'miniaturas não são apagadas pela limpeza de disco'
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Thumbnail Cache' 'Autorun' 0

    # As três tarefas de limpeza. Os scripts ficam no clone, então o git pull atualiza o que elas fazem.
    $tarefasDir = Join-Path $aqui 'manutencao'
    if (-not (Test-Path -LiteralPath $tarefasDir)) { throw "não achei $tarefasDir" }
    Passo 'marcando os caches que a limpeza de disco deve tratar'
    foreach ($c in 'BranchCache', 'Delivery Optimization Files', 'Device Driver Packages', 'Language Pack',
                   'Previous Installations', 'Setup Log Files', 'System error memory dump files',
                   'System error minidump files', 'Temporary Files', 'Temporary Setup Files', 'Update Cleanup',
                   'Upgrade Discarded Files', 'Windows Defender', 'Windows ESD installation files',
                   'Windows Upgrade Log Files') {
        Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\$c" 'StateFlags1337' 2
    }
    $sid       = ([Security.Principal.NTAccount]"$env:USERDOMAIN\$env:USERNAME").Translate([Security.Principal.SecurityIdentifier]).Value
    $config    = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $sid -RunLevel Highest
    foreach ($t in @(
        @{ Nome = 'Limpeza do Windows';  Arq = 'limpeza.ps1';              Dias = 30 },
        @{ Nome = 'Cache do Update';     Arq = 'cache-do-update.ps1';      Dias = 90 },
        @{ Nome = 'Arquivos temporários'; Arq = 'temporarios.ps1';         Dias = 60 })) {
        $arq = Join-Path $tarefasDir $t.Arq
        if (-not (Test-Path -LiteralPath $arq)) { Falha "não achei $arq"; continue }
        # conhost --headless: a tarefa roda sem piscar janela de console
        Register-ScheduledTask -TaskName $t.Nome -TaskPath '\mywiniso' -Force -Settings $config -Principal $principal `
            -Trigger (New-ScheduledTaskTrigger -Daily -DaysInterval $t.Dias -At 9pm) `
            -Action  (New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$arq`"") | Out-Null
        Passo "tarefa '$($t.Nome)': a cada $($t.Dias) dias, 21h"
    }

    # O que o Intelligent Standby List Cleaner faz, sem instalar nada: a cada minuto, se a RAM livre caiu
    # abaixo de um quarto e a standby list passou de 1 GB, manutencao\standby.ps1 esvazia a standby list
    # pela mesma chamada que o ISLC usa (NtSetSystemInformation, MemoryPurgeStandbyList). Evita a engasgada
    # em jogo quando o Windows fica segurando cache velho em vez de entregar a memória.
    $standby = Join-Path $tarefasDir 'standby.ps1'
    if (Test-Path -LiteralPath $standby) {
        $gatilho = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
        $cfg = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -Hidden
        Register-ScheduledTask -TaskName 'Standby list' -TaskPath '\mywiniso' -Force -Settings $cfg -Principal $principal -Trigger $gatilho `
            -Action (New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$standby`"") | Out-Null
        Passo "tarefa 'Standby list': a cada minuto, limpa a standby list quando a RAM livre cai (o que o ISLC faz)"
    } else { Falha "não achei $standby" }

    if ($Dados -and (Test-Path -LiteralPath $PerfilNoD)) {
        Passo 'última rodada do perfil em D: (o que as etapas de depois dos Programas criaram)'
        Stop-Process -Name Discord, Spotify, steam, chrome, Code, obsidian, Update -Force -ErrorAction Ignore
        Start-Sleep -Seconds 2
        & $PerfilNoD
    }
}

# --- Resumo -----------------------------------------------------------------------------------------
Write-Host ''
Write-Host '================================ RESUMO ================================' -ForegroundColor Cyan
foreach ($r in $Resultado) {
    $cor = @{ OK = 'Green'; AVISO = 'Yellow'; ERRO = 'Red' }[$r.Estado]
    Write-Host ("  {0,-6} {1,-40} {2,5} s  {3}" -f $r.Estado, $r.Etapa, $r.Segundos, $r.Detalhe) -ForegroundColor $cor
}
if ($Falhas.Count -gt 0) {
    Write-Host ''
    Write-Host "  Programas que falharam ($($Falhas.Count)):" -ForegroundColor Red
    $Falhas | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
}
$erros  = @($Resultado | Where-Object Estado -eq 'ERRO').Count
$avisos = @($Resultado | Where-Object Estado -eq 'AVISO').Count
Write-Host ''
Write-Host ("  {0} etapas: {1} OK, {2} com aviso, {3} com erro. Log: {4}" -f $Resultado.Count, ($Resultado.Count - $erros - $avisos), $avisos, $erros, $Log) -ForegroundColor $(if ($erros) { 'Red' } elseif ($avisos) { 'Yellow' } else { 'Green' })

# --- Reinício e retomada ------------------------------------------------------------------------------
# Se o Windows precisar reiniciar durante a instalação, ele reinicia -- e volta continuando. Não se
# reinicia no meio das etapas: a rodada termina, e só então, havendo reinício pendente, o setup arma a
# tarefa 'mywiniso-retomar' e reinicia. No logon seguinte ela chama manutencao\retomar.ps1, que roda o
# setup de novo; o cabeçalho de lá explica por que repetir a rodada inteira é a forma segura de continuar.
# Sem reinício pendente a tarefa é removida: ela não sobrevive ao fim da instalação.
$ChaveMy = 'HKLM:\SOFTWARE\mywiniso'
$Retomar = 'mywiniso-retomar'
# Só os dois sinais fortes do Windows. O PendingFileRenameOperations fica ligado por qualquer instalador
# e atravessa rodadas inteiras (26 entradas nesta máquina agora): incluí-lo daria um reinício em toda
# formatação sem nada a ganhar.
$pendente = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
            (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
$querReiniciar = $global:PedeReinicio -or $pendente
if (-not (Test-Path -LiteralPath $ChaveMy)) { New-Item -Path $ChaveMy -Force | Out-Null }
$jaFoi = [int](Get-ItemProperty -LiteralPath $ChaveMy -Name Retomadas -ErrorAction Ignore).Retomadas
$armou = $false

if ($querReiniciar -and $jaFoi -lt 3 -and -not $Depurando) {
    $retomarPs1 = Join-Path $aqui 'manutencao\retomar.ps1'
    if (-not (Test-Path -LiteralPath $retomarPs1)) {
        Write-Host "  não achei $retomarPs1; sem retomada automática." -ForegroundColor Yellow
    } else {
        try {
            $acao      = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$retomarPs1`""
            $gatilho   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
            $gatilho.Delay = 'PT30S'
            $config    = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
            Register-ScheduledTask -TaskName $Retomar -Action $acao -Trigger $gatilho -Settings $config -Principal $principal -Force | Out-Null
            Set-ItemProperty -LiteralPath $ChaveMy -Name Retomadas -Value ($jaFoi + 1) -Type DWord -Force
            $armou = $true
        } catch {
            Write-Host "  não consegui armar a retomada: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

if ($armou) {
    Write-Host ''
    Write-Host ("  O Windows pediu reinício. Retomada {0} de 3 armada: ao entrar de novo, o setup continua sozinho." -f ($jaFoi + 1)) -ForegroundColor Cyan
    Write-Host '  Reiniciando em 60 s. Para cancelar: shutdown /a' -ForegroundColor Cyan
    $Pulso.Ligado = $false
    if ($PulsoPS) { try { $PulsoPS.Runspace.Close() } catch { } }
    try { Stop-Transcript | Out-Null } catch { }
    shutdown.exe /r /t 60 /c "mywiniso: reiniciando para continuar a instalacao" | Out-Null
    exit $erros
}

if ($querReiniciar) {
    Write-Host ''
    if ($jaFoi -ge 3) {
        Write-Host '  Ainda há reinício pendente depois de 3 retomadas; parei de reiniciar sozinho para não virar laço.' -ForegroundColor Yellow
    }
    Write-Host '  Reinicie e rode mywiniso-setup.cmd de novo se algo tiver ficado para trás.' -ForegroundColor Yellow
} else {
    Write-Host '  Reinicie. Depois: abra o RedM.exe da área de trabalho.' -ForegroundColor Cyan
}
# nada mais pendente: a retomada não sobrevive ao fim da instalação (com -So não se mexe no estado)
if (-not $Depurando) {
    Unregister-ScheduledTask -TaskName $Retomar -Confirm:$false -ErrorAction Ignore
    Set-ItemProperty -LiteralPath $ChaveMy -Name Retomadas -Value 0 -Type DWord -Force
}
$Pulso.Ligado = $false
if ($PulsoPS) { try { $PulsoPS.Runspace.Close() } catch { } }
try { Stop-Transcript | Out-Null } catch { }
exit $erros
