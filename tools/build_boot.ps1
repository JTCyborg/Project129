[CmdletBinding()]
param(
    [string]$SjAsmPlus = ".\tools\sjasmplus.exe",
    [string]$Output = ".\build\p127_boot.bin"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Source = ".\src\boot\p127_boot.asm"
$OutputDir = Split-Path -Parent $Output
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

if (-not (Test-Path $SjAsmPlus)) {
    throw "SjASMPlus not found: $SjAsmPlus"
}
if (-not (Test-Path $Source)) {
    throw "Boot source not found: $Source"
}

& $SjAsmPlus --raw=$Output $Source
if ($LASTEXITCODE -ne 0) {
    throw "SjASMPlus failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path $Output)) {
    throw "Assembler did not create output: $Output"
}

$Length = (Get-Item $Output).Length
if ($Length -le 0) {
    throw "Boot image is empty"
}
if ($Length -gt 16384) {
    throw "Milestone 0 image exceeds 16 KiB: $Length bytes"
}

Write-Host "[P127 BUILD] MILESTONE 0"
Write-Host "[P127 BUILD] LOAD=0x6000 ENTRY=0x6000"
Write-Host "[P127 BUILD] IMAGE_BYTES=$Length"
Write-Host "[P127 BUILD] BUILD OK"
