# O único perfil do PowerShell. Vale para o PowerShell 7 e para o Windows PowerShell 5.1, em qualquer host:
# Windows Terminal, VS Code, console solto, elevado ou não. O setup.ps1 copia este arquivo para
# Documentos\PowerShell\profile.ps1 e faz o Documentos\WindowsPowerShell\profile.ps1 apontar para ele.
# Mesmo desenho do zsh do Debian (wsl/zshrc): starship com o mesmo starship.toml, histórico grande e
# compartilhado, eza, zoxide, e os atalhos c e x. Tudo que é de máquina (histórico, tema) mora em D:\Perfil\Home.
# Nada aqui pode custar tempo: o perfil roda a cada terminal aberto.

# --- ambiente ---------------------------------------------------------------------------------------------
# UTF-8 no console: sem isto o Windows PowerShell 5.1 mostra os glifos do starship como "?".
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

$HomeD = 'D:\Perfil\Home'                                      # o "home" que sobrevive à formatação
$env:EDITOR = 'nano'
if (Test-Path -LiteralPath "$HomeD\.config\starship.toml") { $env:STARSHIP_CONFIG = "$HomeD\.config\starship.toml" }
foreach ($p in "$HOME\.local\bin", "$HOME\.maestro\bin") {      # engram e maestro (o setup também põe no Path do usuário)
    if ((Test-Path -LiteralPath $p) -and ($env:Path -split ';') -notcontains $p) { $env:Path = "$p;$env:Path" }
}

# --- histórico: um arquivo só, em D:, para o 5.1, o 7, o VS Code e o Windows Terminal --------------------
# Sem isto cada host guarda o seu (ConsoleHost_history.txt, Visual Studio Code Host_history.txt) em
# Roaming\Microsoft, que a formatação leva. Com o mesmo arquivo, o que foi digitado num vale em todos.
if (Get-Module PSReadLine) {
    if (Test-Path -LiteralPath $HomeD) { Set-PSReadLineOption -HistorySavePath "$HomeD\.ps_history" }
    Set-PSReadLineOption -MaximumHistoryCount 100000 -HistoryNoDuplicates -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    # sugestão em cinza a partir do histórico, como o zsh-autosuggestions; só no PSReadLine 2.1+ (o 5.1 vem com o 2.0)
    if ((Get-Module PSReadLine).Version -ge [version]'2.1') { Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView }
}

# --- atalhos, os mesmos do zsh -----------------------------------------------------------------------------
if (Test-Path -LiteralPath 'D:\Utils\git.sh') {
    function c { & 'C:\Program Files\Git\bin\bash.exe' 'D:\Utils\git.sh' @args }
} else { function c { Clear-Host } }
function x { claude --dangerously-skip-permissions --model opus @args }
# ls pelo eza, com ícones e pastas primeiro. Só o ls: cat continua Get-Content, que scripts usam em pipeline.
if (Get-Command eza -ErrorAction Ignore) {
    Remove-Item Alias:ls -Force -ErrorAction Ignore
    function ls { eza --icons --group-directories-first @args }
}
if (Get-Command zoxide -ErrorAction Ignore) { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }

# --- prompt: starship, com o starship.toml de D: (o mesmo do zsh) -----------------------------------------
if (Get-Command starship -ErrorAction Ignore) {
    Invoke-Expression (& starship init powershell)
} else {
    function prompt {
        $leaf = Split-Path -Leaf $PWD
        if ([string]::IsNullOrEmpty($leaf)) { $leaf = $PWD.Path }
        Write-Host $leaf -ForegroundColor Green -NoNewline
        return '> '
    }
}
