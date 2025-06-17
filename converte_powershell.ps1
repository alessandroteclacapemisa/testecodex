# DBF v3 to CSV converter with XML-configurable logging
param(
    [Parameter(Mandatory=$true)]
    [string]$Entrada,
    [Parameter(Mandatory=$true)]
    [string]$Saida,
    [string]$LogConfig = 'logging_config.xml'
)

# Mapping of log levels
$LevelMap = @{ 
    'FATAL' = 50
    'ERROR' = 40
    'WARN'  = 30
    'INFO'  = 20
    'DEBUG' = 10
    'TRACE' = 5
}

$Global:LogLevel = 20
$Global:LogFormat = '{0} - {1} - {2}'
$Global:LogFile = 'converte_powershell.log'
$Global:LogMaxBytes = 1048576
$Global:LogBackupCount = 3

function Rotate-Logs {
    param(
        [string]$File,
        [int]$MaxBytes,
        [int]$BackupCount
    )
    if (Test-Path $File -and (Get-Item $File).Length -ge $MaxBytes) {
        for ($i = $BackupCount - 1; $i -ge 1; $i--) {
            $src = f"$File.$i"
            $dst = f"$File.{i + 1}"
            if (Test-Path $src) { Move-Item -Force $src $dst }
        }
        Move-Item -Force $File "$File.1"
    }
}

function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )
    $levelNum = $LevelMap[$Level]
    if ($levelNum -lt $Global:LogLevel) { return }
    $time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $text = $Global:LogFormat -f $time, $Level, $Message
    Rotate-Logs $Global:LogFile $Global:LogMaxBytes $Global:LogBackupCount
    Add-Content -Path $Global:LogFile -Value $text
    Write-Host $text
}

function Initialize-Logging {
    param([string]$ConfigPath)
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "Arquivo de configuracao de log '$ConfigPath' nao encontrado. Usando configuracao padrao."
        return
    }
    try {
        [xml]$xml = Get-Content $ConfigPath
        $levelName = $xml.logging.level
        if ($LevelMap.ContainsKey($levelName)) { $Global:LogLevel = $LevelMap[$levelName] }
        $Global:LogFormat = $xml.logging.format
        $Global:LogFile = $xml.logging.filename
        $Global:LogMaxBytes = [int]$xml.logging.maxBytes
        $Global:LogBackupCount = [int]$xml.logging.backupCount
    } catch {
        Write-Host "Falha ao ler configuracao de log: $_"
    }
}

function Parse-DBFHeader {
    param([System.IO.BinaryReader]$Reader)
    $header = $Reader.ReadBytes(32)
    if ($header.Length -lt 32) { throw 'Arquivo DBF invalido ou corrompido' }
    $numRecords = [BitConverter]::ToInt32($header, 4)
    $headerLen = [BitConverter]::ToInt16($header, 8)
    $fields = @()
    while ($true) {
        $fd = $Reader.ReadBytes(32)
        if (-not $fd -or $fd[0] -eq 0x0D) { break }
        $name = [System.Text.Encoding]::GetEncoding('latin1').GetString($fd[0:11]).Split([char]0)[0]
        $type = [System.Text.Encoding]::GetEncoding('latin1').GetString($fd[11:12])
        $length = $fd[16]
        $decimal = $fd[17]
        $fields += [pscustomobject]@{ name=$name; type=$type; length=$length; decimal=$decimal }
    }
    $Reader.BaseStream.Seek($headerLen, 'Begin') | Out-Null
    return @{ Fields=$fields; Num=$numRecords }
}

function Read-DBFRecords {
    param(
        [System.IO.BinaryReader]$Reader,
        $Fields,
        [int]$Num
    )
    $records = @()
    $recordSize = ($Fields | Measure-Object -Property length -Sum).Sum + 1
    for ($i=0; $i -lt $Num; $i++) {
        $data = $Reader.ReadBytes($recordSize)
        if (-not $data) { break }
        if ($data[0] -eq [byte]'*') { continue }
        $pos = 1
        $rec = @()
        foreach ($f in $Fields) {
            $raw = $data[$pos..($pos + $f.length - 1)]
            $pos += $f.length
            $value = [System.Text.Encoding]::GetEncoding('latin1').GetString($raw).Trim()
            $rec += $value
        }
        $records += ,$rec
    }
    return $records
}

function Convert-DBFToCSV {
    param(
        [string]$InputFile,
        [string]$OutputFile
    )
    Write-Log 'INFO' "Lendo arquivo DBF: $InputFile"
    if (-not (Test-Path $InputFile)) {
        Write-Log 'ERROR' "Arquivo de entrada nao encontrado: $InputFile"
        throw 'Arquivo nao encontrado'
    }
    try {
        $fs = [System.IO.File]::Open($InputFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
        $br = New-Object System.IO.BinaryReader($fs)
        $info = Parse-DBFHeader $br
        $fields = $info.Fields
        $num = $info.Num
        $layout = $fields | ForEach-Object { "($($_.name), $($_.type), $($_.length), $($_.decimal))" }
        Write-Log 'DEBUG' "Layout lido: $($layout -join ', ')"
        Write-Log 'DEBUG' "Quantidade de registros: $num"
        $records = Read-DBFRecords $br $fields $num
        $br.Close(); $fs.Close()
    } catch {
        Write-Log 'ERROR' "Erro ao ler arquivo DBF: $_"
        throw
    }
    Write-Log 'INFO' "Escrevendo CSV: $OutputFile"
    try {
        $enc = [System.Text.Encoding]::UTF8
        $sw = New-Object System.IO.StreamWriter($OutputFile, $false, $enc)
        $sw.WriteLine(($fields | ForEach-Object { $_.name }) -join ',')
        foreach ($rec in $records) {
            $sw.WriteLine(($rec -join ','))
        }
        $sw.Close()
    } catch {
        Write-Log 'ERROR' "Erro ao escrever CSV: $_"
        throw
    }
    Write-Log 'INFO' "Conversao concluida. $($records.Count) registros processados."
}

Initialize-Logging $LogConfig

try {
    Convert-DBFToCSV $Entrada $Saida
} catch {
    Write-Log 'FATAL' "Erro fatal: $_"
    exit 1
}
