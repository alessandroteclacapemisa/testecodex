# Conversor DBF para CSV

Este repositório contém os scripts **converte_python** e **converte_powershell.ps1**
para converter arquivos DBF (versão 3) para arquivos CSV.

## Uso

### Python
```
./converte_python entrada.dbf saida.csv
```

### PowerShell
```
pwsh ./converte_powershell.ps1 -Entrada entrada.dbf -Saida saida.csv
```

É possível especificar um arquivo XML para configuração de logs usando o
parâmetro `--log-config`. Um modelo básico encontra-se em `logging_config.xml`.

## Configuração de Log

O arquivo `logging_config.xml` define o formato, nível de log, tamanho máximo
do arquivo de log e quantidade de backups para rotação. Os logs são enviados
para arquivo e para o console.

### Níveis de log disponíveis

- **FATAL** – Erros críticos que interrompem a execução
- **ERROR** – Erros de execução que permitem continuação
- **WARN** – Situações que podem gerar problemas
- **INFO** – Informações gerais do fluxo
- **DEBUG** – Detalhes de depuração
- **TRACE** – Detalhes ainda mais minuciosos

## Dependências

Não há dependências externas além da biblioteca padrão do Python.
