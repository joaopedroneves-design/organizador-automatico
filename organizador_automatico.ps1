# =====================================================================
#  ORGANIZADOR AUTOMÁTICO DE ARQUIVOS  (Windows 10/11, PowerShell 5.1+)
#  Fica ligado escondido. A cada 10 segundos olha os arquivos soltos em
#  Downloads e em Documentos:
#   1) se o NOME combinar com uma regra de regras.txt, move sozinho e avisa;
#   2) se não combinar, abre uma janelinha perguntando para qual pasta vai.
#  Nunca apaga nem substitui nada. Cada movimentação vai para registro.csv.
# =====================================================================
param(
    [switch]$UmaVez,          # roda uma volta só (usado em testes)
    [string]$RespostasTeste   # arquivo com respostas no lugar da janela (usado em testes)
)
$ErrorActionPreference = 'Stop'

$Aqui      = Split-Path -Parent $MyInvocation.MyCommand.Path
$Regras    = [IO.Path]::Combine($Aqui, 'regras.txt')
$Registro  = [IO.Path]::Combine($Aqui, 'registro.csv')
$Ignorados = [IO.Path]::Combine($Aqui, 'ignorados.txt')
$Desk = [Environment]::GetFolderPath('Desktop')
$Docs = [Environment]::GetFolderPath('MyDocuments')
$DL   = [IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'), 'Downloads')
$Vigiar = @(@($DL, $Docs) | Where-Object { $_ -and [IO.Directory]::Exists($_) })

# só uma cópia ligada por vez
$trava = New-Object System.Threading.Mutex($false, 'Claude_Organizador_Automatico')
$temTrava = $false
try { $temTrava = $trava.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $temTrava = $true }
if (-not $temTrava) { exit }

$SegundosParado = 15      # só mexe em arquivo que não muda há 15 s (download terminado)
$IntervaloSeg   = 10
$ExtIgnoradas   = @('.crdownload', '.part', '.partial', '.tmp', '.download', '.opdownload', '.ini', '.lnk', '.url', '.lock')
$script:sair    = $false

# ---------- janela e ícone (só no Windows) ----------
$temGUI = $false
if ($env:OS -eq 'Windows_NT' -and -not $RespostasTeste) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $script:App = [type]'System.Windows.Forms.Application'
        $script:App::EnableVisualStyles()
        $temGUI = $true
    } catch { $temGUI = $false }
}
$icone = $null
if ($temGUI -and -not $UmaVez) {
    try {
        $icone = New-Object System.Windows.Forms.NotifyIcon
        $icone.Icon = ([type]'System.Drawing.SystemIcons')::Information
        $icone.Text = 'Organizador automático de arquivos'
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        [void]$menu.Items.Add('Abrir regras', $null, { try { Start-Process notepad.exe -ArgumentList ('"' + $Regras + '"') } catch {} })
        [void]$menu.Items.Add('Ver o que já foi movido', $null, { try { if (Test-Path -LiteralPath $Registro) { Start-Process -FilePath $Registro } } catch {} })
        [void]$menu.Items.Add('Desligar até reiniciar o PC', $null, { $script:sair = $true })
        $icone.ContextMenuStrip = $menu
        $icone.Visible = $true
    } catch { $icone = $null }
}
function Avisar([string]$titulo, [string]$texto) {
    if ($icone) { try { $icone.ShowBalloonTip(5000, $titulo, $texto, 'Info') } catch {} }
}

# ---------- texto ----------
function Sem-Acento([string]$s) {
    if (-not $s) { return '' }
    $d = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $d.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
    }
    return $sb.ToString().Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
}
function Texto-Comparavel([string]$nome) {
    $t = Sem-Acento ([IO.Path]::GetFileNameWithoutExtension($nome))
    $t = [regex]::Replace($t, '[_\-\.\(\)\[\]\+,;]+', ' ')
    return [regex]::Replace($t, '\s+', ' ').Trim()
}

# ---------- regras ----------
function Ler-Regras {
    $lista = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Regras)) { return ,$lista }
    foreach ($linha in (Get-Content -LiteralPath $Regras -Encoding UTF8)) {
        $l = $linha.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        $partes = $l -split '=>', 2
        if ($partes.Count -ne 2) { continue }
        $destino = $partes[1].Trim()
        if (-not $destino) { continue }
        $exts = New-Object System.Collections.Generic.List[string]
        $pads = New-Object System.Collections.Generic.List[object]
        foreach ($p in ($partes[0] -split ',')) {
            $k = Sem-Acento $p.Trim()
            if (-not $k) { continue }
            if ($k.StartsWith('.')) { $exts.Add($k); continue }
            $prefixo = $k.EndsWith('*')
            $k = [regex]::Replace($k.TrimEnd('*'), '[_\-\.]+', ' ').Trim()
            if (-not $k) { continue }
            $esc = [regex]::Escape($k) -replace '\\ ', '\s+'
            if ($prefixo) { $esc += '[\p{L}\p{N}]*' }
            $pads.Add((New-Object System.Text.RegularExpressions.Regex('(?<![\p{L}\p{N}])' + $esc + '(?![\p{L}\p{N}])')))
        }
        $lista.Add([pscustomobject]@{ Destino = $destino; Exts = $exts; Pads = $pads })
    }
    return ,$lista
}
function Achar-Regra($regras, [string]$nome, [string]$ext) {
    $texto = Texto-Comparavel $nome
    foreach ($r in $regras) {
        if ($r.Exts -contains $ext) { return $r }
        foreach ($p in $r.Pads) { if ($p.IsMatch($texto)) { return $r } }
    }
    return $null
}
function Botoes($regras) {
    $vistos = @{}
    $lista = New-Object System.Collections.Generic.List[object]
    foreach ($r in $regras) {
        $d = $r.Destino
        if ($d -match '^(?i)downloads([\\/]|$)') { continue }
        if ($vistos.ContainsKey($d)) { continue }
        $vistos[$d] = $true
        $segs = @($d -split '[\\/]+' | Where-Object { $_ })
        $lista.Add([pscustomobject]@{ Rotulo = $segs[$segs.Count - 1]; Destino = $d })
    }
    return ,$lista
}
function Resolver-Destino([string]$d) {
    $segs = @($d.Trim() -split '[\\/]+' | Where-Object { $_ })
    $base = $Desk
    if ($segs.Count -gt 0 -and $segs[0] -match '^(?i)downloads$') { $base = $DL; $segs = @($segs | Select-Object -Skip 1) }
    elseif ($segs.Count -gt 0 -and $segs[0] -match '^(?i)(documentos|documents)$') { $base = $Docs; $segs = @($segs | Select-Object -Skip 1) }
    return [IO.Path]::Combine([string[]](@($base) + $segs))
}

# ---------- arquivos ----------
function Caminho-Livre([string]$dir, [string]$nome, [datetime]$quando) {
    $p = [IO.Path]::Combine($dir, $nome)
    if (-not (Test-Path -LiteralPath $p)) { return $p }
    $base = [IO.Path]::GetFileNameWithoutExtension($nome)
    $ext  = [IO.Path]::GetExtension($nome)
    $data = $quando.ToString('yyyy-MM-dd')
    $p = [IO.Path]::Combine($dir, ('{0} ({1}){2}' -f $base, $data, $ext))
    if (-not (Test-Path -LiteralPath $p)) { return $p }
    for ($i = 2; ; $i++) {
        $p = [IO.Path]::Combine($dir, ('{0} ({1}) ({2}){3}' -f $base, $data, $i, $ext))
        if (-not (Test-Path -LiteralPath $p)) { return $p }
    }
}
function Esta-Livre([string]$p) {
    try { $fs = [IO.File]::Open($p, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None); $fs.Close(); return $true } catch { return $false }
}
function Rotulo-Curto([string]$dir) {
    if ($dir.StartsWith($Desk, [StringComparison]::OrdinalIgnoreCase)) { return $dir.Substring($Desk.Length).TrimStart('\', '/') }
    return $dir
}
function Registrar($origem, $destino, $motivo) {
    try {
        [pscustomobject]@{ Data = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Origem = $origem; Destino = $destino; Motivo = $motivo } |
            Export-Csv -LiteralPath $Registro -Append -NoTypeInformation -Delimiter ';' -Encoding UTF8
    } catch {}
}
function Mover([IO.FileInfo]$info, [string]$destDir, [string]$motivo, [bool]$avisar) {
    if ([IO.Path]::GetFullPath($destDir).TrimEnd('\', '/') -ieq [IO.Path]::GetFullPath($info.DirectoryName).TrimEnd('\', '/')) { return }
    [void][IO.Directory]::CreateDirectory($destDir)
    $alvo = Caminho-Livre $destDir $info.Name $info.LastWriteTime
    [IO.File]::Move($info.FullName, $alvo)
    Registrar $info.FullName $alvo $motivo
    if ($avisar) { Avisar 'Arquivo organizado' ($info.Name + '  →  ' + (Rotulo-Curto $destDir)) }
}

# ---------- "deixar onde está" fica lembrado ----------
function Chave([IO.FileInfo]$i) { return $i.FullName + '|' + $i.Length + '|' + $i.LastWriteTimeUtc.Ticks }
function Ler-Ignorados {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath $Ignorados) {
        foreach ($l in (Get-Content -LiteralPath $Ignorados -Encoding UTF8)) { if ($l) { [void]$set.Add($l) } }
    }
    return ,$set
}
function Adicionar-Ignorado([string]$k) { try { Add-Content -LiteralPath $Ignorados -Value $k -Encoding UTF8 } catch {} }
function Limpar-Ignorados {
    if (-not (Test-Path -LiteralPath $Ignorados)) { return }
    try {
        $manter = @(Get-Content -LiteralPath $Ignorados -Encoding UTF8 | Where-Object { $_ -and (Test-Path -LiteralPath (($_ -split '\|')[0])) })
        Set-Content -LiteralPath $Ignorados -Value $manter -Encoding UTF8
    } catch {}
}

# ---------- janela "Para qual pasta vai?" ----------
function Perguntar([string]$arquivo, $botoes) {
    if ($RespostasTeste) {
        foreach ($l in (Get-Content -LiteralPath $RespostasTeste -Encoding UTF8)) {
            $p = $l -split '=>', 2
            if ($p.Count -eq 2 -and $p[0].Trim() -eq [IO.Path]::GetFileName($arquivo)) { return $p[1].Trim() }
        }
        return '|ficar'
    }
    if (-not $temGUI) { return '|adiar' }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Organizador de arquivos'
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.ShowInTaskbar = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.AutoSize = $true
    $form.AutoSizeMode = 'GrowAndShrink'
    $form.Padding = New-Object System.Windows.Forms.Padding(14)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $form.Tag = $null

    $painel = New-Object System.Windows.Forms.FlowLayoutPanel
    $painel.FlowDirection = 'TopDown'
    $painel.WrapContents = $false
    $painel.AutoSize = $true
    $painel.AutoSizeMode = 'GrowAndShrink'
    $form.Controls.Add($painel)

    $titulo = New-Object System.Windows.Forms.Label
    $titulo.Text = 'Para qual pasta vai este arquivo?'
    $titulo.AutoSize = $true
    $titulo.Font = New-Object System.Drawing.Font('Segoe UI', 11, ([Enum]::Parse([type]'System.Drawing.FontStyle', 'Bold')))
    $painel.Controls.Add($titulo)

    $nome = New-Object System.Windows.Forms.Label
    $nome.Text = [IO.Path]::GetFileName($arquivo) + '   (está em ' + [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($arquivo)) + ')'
    $nome.AutoSize = $true
    $nome.MaximumSize = New-Object System.Drawing.Size(440, 0)
    $painel.Controls.Add($nome)

    $ver = New-Object System.Windows.Forms.LinkLabel
    $ver.Text = 'Abrir o arquivo para ver o que é'
    $ver.AutoSize = $true
    $ver.Tag = $arquivo
    $ver.Margin = New-Object System.Windows.Forms.Padding(3, 3, 3, 10)
    $ver.add_LinkClicked({ param($s, $e) try { Start-Process -FilePath ([string]$s.Tag) } catch {} })
    $painel.Controls.Add($ver)

    foreach ($b in $botoes) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $b.Rotulo
        $btn.Tag = $b.Destino
        $btn.Width = 440
        $btn.Height = 34
        $btn.TextAlign = 'MiddleLeft'
        $btn.add_Click({ param($s, $e) $f = $s.FindForm(); $f.Tag = [string]$s.Tag; $f.Close() })
        $painel.Controls.Add($btn)
    }

    $outra = New-Object System.Windows.Forms.Button
    $outra.Text = 'Outra pasta...'
    $outra.Width = 440
    $outra.Height = 34
    $outra.TextAlign = 'MiddleLeft'
    $outra.add_Click({
        param($s, $e)
        $f = $s.FindForm()
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        $fb.Description = 'Escolha a pasta para este arquivo'
        $fb.SelectedPath = [Environment]::GetFolderPath('Desktop')
        if ($fb.ShowDialog($f) -eq 'OK') { $f.Tag = '>' + $fb.SelectedPath; $f.Close() }
    })
    $painel.Controls.Add($outra)

    $ficar = New-Object System.Windows.Forms.Button
    $ficar.Text = 'Deixar onde está (não perguntar de novo)'
    $ficar.Width = 440
    $ficar.Height = 34
    $ficar.TextAlign = 'MiddleLeft'
    $ficar.add_Click({ param($s, $e) $f = $s.FindForm(); $f.Tag = '|ficar'; $f.Close() })
    $painel.Controls.Add($ficar)

    $form.add_Shown({ param($s, $e) $s.Activate() })
    [void]$form.ShowDialog()
    $resp = $form.Tag
    $form.Dispose()
    if ($null -eq $resp) { return '|ficar' }
    return [string]$resp
}

# ---------- uma volta ----------
function Processar {
    $regras = Ler-Regras
    $ign = Ler-Ignorados
    foreach ($pasta in $Vigiar) {
        $arquivos = @()
        try { $arquivos = [IO.Directory]::GetFiles($pasta) } catch { continue }
        foreach ($f in $arquivos) {
            if ($script:sair) { return }
            try {
                $info = New-Object IO.FileInfo($f)
                if (-not $info.Exists) { continue }
                if ($info.Attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System)) { continue }
                $nome = $info.Name
                if ($nome.StartsWith('~$') -or $nome.StartsWith('.')) { continue }
                $ext = Sem-Acento $info.Extension
                if ($ExtIgnoradas -contains $ext) { continue }
                if (((Get-Date) - $info.LastWriteTime).TotalSeconds -lt $SegundosParado) { continue }
                $chave = Chave $info
                if ($ign.Contains($chave)) { continue }

                $regra = Achar-Regra $regras $nome $ext
                if ($regra) { Mover $info (Resolver-Destino $regra.Destino) ('regra: ' + $regra.Destino) $true; continue }

                if (-not (Esta-Livre $f)) { continue }   # aberto em algum programa: pergunta depois
                $resp = Perguntar $f (Botoes $regras)
                if ($resp -eq '|adiar') { continue }
                if ($resp -eq '|ficar') { Adicionar-Ignorado $chave; continue }
                if ($resp.StartsWith('>')) { $destDir = $resp.Substring(1) } else { $destDir = Resolver-Destino $resp }
                Mover $info $destDir ('escolhido: ' + $resp.TrimStart('>')) $false
            } catch { }   # arquivo ocupado ou sumiu: tenta de novo na próxima volta
        }
    }
}

# ---------- laço principal ----------
Limpar-Ignorados
try {
    while ($true) {
        Processar
        if ($UmaVez -or $script:sair) { break }
        $fim = (Get-Date).AddSeconds($IntervaloSeg)
        while ((Get-Date) -lt $fim -and -not $script:sair) {
            if ($temGUI) { $script:App::DoEvents() }
            Start-Sleep -Milliseconds 200
        }
        if ($script:sair) { break }
    }
} finally {
    if ($icone) { $icone.Visible = $false; $icone.Dispose() }
}
