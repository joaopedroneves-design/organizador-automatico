# Liga o Organizador automático agora e em todo início do Windows
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$Aqui       = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script     = [IO.Path]::Combine($Aqui, 'organizador_automatico.ps1')
$RegrasTxt  = [IO.Path]::Combine($Aqui, 'regras.txt')
$Exemplo    = [IO.Path]::Combine($Aqui, 'regras.exemplo.txt')
if (-not (Test-Path -LiteralPath $RegrasTxt) -and (Test-Path -LiteralPath $Exemplo)) {
    [IO.File]::Copy($Exemplo, $RegrasTxt)
    Write-Host 'Criei o regras.txt a partir do exemplo: edite com as suas pastas e palavras-chave.' -ForegroundColor Yellow
}
$PS         = [IO.Path]::Combine($env:SystemRoot, 'System32\WindowsPowerShell\v1.0\powershell.exe')
$Argumentos = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Script + '"'
$Atalho     = [IO.Path]::Combine([Environment]::GetFolderPath('Startup'), 'Organizador automático de arquivos.lnk')
try {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($Atalho)
    $sc.TargetPath = $PS
    $sc.Arguments = $Argumentos
    $sc.WorkingDirectory = $Aqui
    $sc.WindowStyle = 7
    $sc.Description = 'Organiza arquivos novos de Downloads e Documentos (regras.txt)'
    $sc.Save()
} catch {
    Write-Host ('Não consegui criar o atalho de inicialização: {0}' -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
Start-Process -FilePath $PS -ArgumentList $Argumentos -WindowStyle Hidden
Write-Host ''
Write-Host 'Organizador LIGADO.' -ForegroundColor Green
Write-Host 'Ele já está rodando e vai ligar sozinho toda vez que o computador iniciar.'
Write-Host 'Procure o ícone azul (i) perto do relógio: botão direito para abrir as regras ou desligar.'
Write-Host 'Para desligar de vez: DESATIVAR.bat'
