# Desliga o Organizador automático e tira ele da inicialização do Windows
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$Atalho = [IO.Path]::Combine([Environment]::GetFolderPath('Startup'), 'Organizador automático de arquivos.lnk')
if (Test-Path -LiteralPath $Atalho) { Remove-Item -LiteralPath $Atalho -Force }
$n = 0
try {
    $procs = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine -like '*organizador_automatico.ps1*' })
    foreach ($p in $procs) { try { Stop-Process -Id $p.ProcessId -Force; $n++ } catch {} }
} catch {}
Write-Host ''
Write-Host 'Organizador DESLIGADO. Ele não vai mais ligar sozinho.' -ForegroundColor Green
if ($n -gt 0) { Write-Host '(Se o ícone ainda aparecer perto do relógio, ele some quando você passar o mouse em cima.)' }
Write-Host 'Para ligar de novo: ATIVAR.bat'
