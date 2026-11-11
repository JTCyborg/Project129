[CmdletBinding()]
param(
    [string]$Zcc = "zcc",
    [string]$SjAsmPlus = (Join-Path $PSScriptRoot "sjasmplus.exe"),
    [string]$Output = ".\disk_A.trd"
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$ZccCommand = Get-Command $Zcc -ErrorAction SilentlyContinue
if (-not $ZccCommand) { throw "Z88DK zcc not found: $Zcc" }
$Zcc = $ZccCommand.Source

if (-not (Test-Path $SjAsmPlus)) {
    $AssemblerCommand = Get-Command $SjAsmPlus -ErrorAction SilentlyContinue
    if (-not $AssemblerCommand) { throw "SjASMPlus not found: $SjAsmPlus" }
    $SjAsmPlus = $AssemblerCommand.Source
}

$BuildDir = Join-Path $Root "build"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$Out = [System.IO.Path]::GetFullPath($Output)
if ([System.IO.Path]::GetFileName($Out) -ne "disk_A.trd") {
    throw "The packaging source writes disk_A.trd; use -Output disk_A.trd"
}

$Resident = Join-Path $BuildDir "P129BOOT.bin"
Remove-Item -Force -ErrorAction SilentlyContinue $Resident
Remove-Item -Force -ErrorAction SilentlyContinue $Out

Write-Host "[P129 BUILD] ZCC=$Zcc"
& $Zcc +zx -vn -O2 -startup=0 -zorg=24576 -o $Resident src/entry.asm src/main.c
if ($LASTEXITCODE -ne 0) { throw "Z88DK compile/link failed: $LASTEXITCODE" }
if (-not (Test-Path $Resident)) { throw "Z88DK did not create $Resident" }
$ResidentSize = (Get-Item $Resident).Length
if ($ResidentSize -le 0 -or $ResidentSize -gt 16384) {
    throw "Bootstrap resident image has invalid size: $ResidentSize bytes"
}
Write-Host "[P129 BUILD] RESIDENT=P129BOOT.C LOAD=#6000 SIZE=$ResidentSize"

Write-Host "[P129 BUILD] SJASMPLUS=$SjAsmPlus"
& $SjAsmPlus --dirbol src/boot/main.asm
if ($LASTEXITCODE -ne 0) { throw "SjASMPlus packaging failed: $LASTEXITCODE" }
if (-not (Test-Path $Out)) { throw "SjASMPlus did not create $Out" }
$ImageSize = (Get-Item $Out).Length
if ($ImageSize -ne 655360) { throw "TR-DOS image is $ImageSize bytes; expected 655360" }
Write-Host "[P129 BUILD] TRD_IMAGE=$Out SIZE=$ImageSize"
Write-Host "[P129 BUILD] BUILD OK"
