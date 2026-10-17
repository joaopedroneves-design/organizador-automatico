# Organizador automático de arquivos

Script para Windows que organiza sozinho os arquivos novos que chegam em **Downloads** e **Documentos**:

- se o **nome** do arquivo combina com uma regra (ex.: `Lista 6 Cálculo 3.pdf`, `MTM3103_plano.pdf`, `Curriculo.pdf`, `setup.exe`), ele **move sozinho** para a pasta certa e mostra um aviso;
- se o nome não diz nada (ex.: `lista5.pdf`), abre uma **janelinha** perguntando para qual pasta vai, com um botão para cada pasta.

Nada é apagado nem substituído: se já existir um arquivo com o mesmo nome no destino, o novo ganha a data no nome. Tudo o que foi movido fica anotado em `registro.csv`.

> **English:** a small PowerShell tool for Windows that watches Downloads and Documents and files new items into folders, either automatically (keyword rules on the file name) or with one click in a small prompt. It never deletes or overwrites files.

## Requisitos

- Windows 10 ou 11
- PowerShell 5.1, que já vem com o Windows. Não precisa instalar nada nem ser administrador.

## Como usar

1. Baixe o projeto (**Code › Download ZIP**) e extraia numa pasta fixa, por exemplo em Documentos.
2. Dê dois cliques em **`ATIVAR.bat`**. Na primeira vez ele cria o `regras.txt` a partir do exemplo.
3. Abra o **`regras.txt`** e troque as regras pelas suas pastas e palavras-chave.

Pronto: o organizador fica rodando escondido e liga sozinho toda vez que o Windows inicia. Um ícone azul (i) aparece perto do relógio; com o botão direito dá para abrir as regras, ver o que já foi movido ou desligar até reiniciar.

Para desligar de vez: **`DESATIVAR.bat`**.

## Regras (`regras.txt`)

Cada linha tem as palavras-chave, `=>` e a pasta de destino:

```
mtm3103, calculo 3, calc 3   =>  Faculdade\Cálculo 3
.exe, .msi                   =>  DOWNLOADS\Instaladores
curriculo, resume, cv        =>  Carreira\Currículos
=>  Pessoal
```

- Palavras separadas por vírgula; maiúsculas e acentos não importam.
- A palavra precisa aparecer inteira no nome (`edo` não pega `credo`). Termine com `*` para valer o começo da palavra (`oscila*` pega "oscilações").
- Palavras que começam com ponto são extensões (`.exe`, `.vhd`).
- O destino começa na **Área de Trabalho**. Comece com `DOWNLOADS\` ou `DOCUMENTOS\` para usar essas pastas como base.
- Vale a primeira regra que combinar, de cima para baixo.
- Uma linha só com `=> pasta` vira apenas um botão na janela.
- O arquivo é relido sozinho, sem precisar reiniciar o organizador.

## Como funciona

- A cada 10 segundos olha só os arquivos soltos de Downloads e Documentos (não entra em subpastas).
- Ignora downloads em andamento (`.crdownload`, `.part`, `.tmp`…), arquivos ocultos ou de sistema, atalhos e arquivos que mudaram há menos de 15 segundos.
- Arquivo aberto em outro programa (por exemplo, um Word sendo editado) espera até ser fechado.
- "Deixar onde está" fica lembrado em `ignorados.txt`, e ele não pergunta de novo sobre aquele arquivo.
- Só roda uma cópia por vez.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `organizador_automatico.ps1` | o organizador |
| `regras.exemplo.txt` | modelo de regras (vira `regras.txt` na primeira ativação) |
| `ATIVAR.bat` / `ativar.ps1` | liga agora e coloca na inicialização do Windows |
| `DESATIVAR.bat` / `desativar.ps1` | desliga e tira da inicialização |

`regras.txt`, `registro.csv` e `ignorados.txt` são pessoais e ficam fora do Git (`.gitignore`).

## Licença

MIT. Veja [LICENSE](LICENSE).

Feito com a ajuda do Claude (Anthropic).
