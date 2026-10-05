param(
    [Parameter(Mandatory = $true)][string]$Converter,
    [Parameter(Mandatory = $true)][string]$InputFile,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$converterPath = (Resolve-Path -LiteralPath $Converter).Path
$inputPath = (Resolve-Path -LiteralPath $InputFile).Path
if (-not (Test-Path -LiteralPath $converterPath -PathType Leaf)) { throw 'Converter must be an executable file.' }
if ([IO.Path]::GetExtension($inputPath).ToLowerInvariant() -notin @('.db2', '.dbc')) {
    throw 'Input must be an extracted .db2 or .dbc table, not a CASC directory.'
}
$stream = [IO.File]::OpenRead($inputPath)
try {
    $bytes = New-Object byte[] 4
    if ($stream.Read($bytes, 0, 4) -ne 4) { throw 'Input is too short to contain a table header.' }
    $signature = [Text.Encoding]::ASCII.GetString($bytes)
} finally { $stream.Dispose() }
if ($signature -notmatch '^(WDB[5-9]|WDC[1-9])$') {
    throw "Unsupported table header '$signature'. Marlamin DBC2CSV requires WDB5+; legacy WDBC files need a different reader."
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = (Resolve-Path -LiteralPath $OutputDirectory).Path
$table = [IO.Path]::GetFileNameWithoutExtension($inputPath)
$csvPath = Join-Path $outputPath ($table + '.csv')
$copyPath = Join-Path $outputPath ([IO.Path]::GetFileName($inputPath))
if ((Test-Path -LiteralPath $csvPath) -or (Test-Path -LiteralPath $copyPath)) {
    throw 'Output already exists. Choose a new output directory; nothing has been overwritten.'
}
$definition = Join-Path (Split-Path -Parent $converterPath) ('definitions\' + $table + '.dbd')
if (-not (Test-Path -LiteralPath $definition -PathType Leaf)) { throw "Missing definition: $definition" }
Copy-Item -LiteralPath $inputPath -Destination $copyPath
try {
    $messages = & $converterPath $copyPath 2>&1
    $exitCode = $LASTEXITCODE
    $messages | Write-Output
    if ($exitCode -ne 0 -or (($messages | Out-String) -match 'Failed to export DB2') -or
        -not (Test-Path -LiteralPath $csvPath -PathType Leaf) -or
        (Get-Item -LiteralPath $csvPath).Length -eq 0) {
        throw 'Conversion failed or produced no CSV. Check table format and build-matched definitions. Exit code alone is not reliable for this converter.'
    }
    Write-Output "Converted CSV: $csvPath"
} catch {
    if (Test-Path -LiteralPath $csvPath -PathType Leaf) { Remove-Item -LiteralPath $csvPath }
    throw
} finally {
    Remove-Item -LiteralPath $copyPath
}
