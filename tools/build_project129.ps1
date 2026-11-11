[CmdletBinding()]
param(
    [string]$Zcc = "zcc",
    [string]$SjAsmPlus = "sjasmplus",
    [string]$Output = ".\disk_A.trd"
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$ZccCommand = Get-Command $Zcc -ErrorAction SilentlyContinue
if (-not $ZccCommand) { throw "Z88DK zcc not found: $Zcc" }
$Zcc = $ZccCommand.Source

# zcc launches z88dk-z80asm as a child process. When zcc is invoked by
# absolute path, its bin directory may not be present in the inherited PATH.
$Z88dkBin = Split-Path -Parent $Zcc
$env:PATH = "$Z88dkBin;$env:PATH"
$Z80Asm = Join-Path $Z88dkBin "z88dk-z80asm.exe"
if (-not (Test-Path $Z80Asm)) {
    throw "Z88DK assembler not found: $Z80Asm. Check the Z88DK installation."
}
Write-Host "[P129 BUILD] Z88DK_BIN=$Z88dkBin"
Write-Host "[P129 BUILD] Z80ASM=$Z80Asm"

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

Write-Host "[P129 BUILD] VERSION=BOOTSTRAP-0.1.0"
foreach ($Source in @("src/main.c", "src/entry.asm", "src/boot/main.asm")) {
    $Hash = (Get-FileHash $Source -Algorithm SHA256).Hash.Substring(0, 8)
    Write-Host "[P129 BUILD] $Source=$Hash"
}
Write-Host "[P129 BUILD] ZCC=$Zcc"
& $Zcc +zx -v -O2 -compiler=sdcc --no-crt -zorg=24576 -m -bn $Resident src/entry.asm src/main.c
if ($LASTEXITCODE -ne 0) { throw "Z88DK compile/link failed: $LASTEXITCODE" }
if (-not (Test-Path $Resident)) {
    $Candidates = @(Get-ChildItem -Path $BuildDir -Filter "P129BOOT*" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    if ($Candidates.Count -gt 0) {
        throw "Z88DK output name mismatch. Expected $Resident; found: $($Candidates -join ", ")"
    }
    throw "Z88DK returned success but produced no P129BOOT output. Review the verbose ZCC commands above."
}
$ResidentSize = (Get-Item $Resident).Length
if ($ResidentSize -le 0 -or $ResidentSize -gt 16384) {
    throw "Bootstrap resident image has invalid size: $ResidentSize bytes"
}
Write-Host "[P129 BUILD] RESIDENT=p129boot.C LOAD=#6000 SIZE=$ResidentSize"

Write-Host "[P129 BUILD] SJASMPLUS=$SjAsmPlus"
& $SjAsmPlus --dirbol src/boot/main.asm
if ($LASTEXITCODE -ne 0) { throw "SjASMPlus packaging failed: $LASTEXITCODE" }
if (-not (Test-Path $Out)) { throw "SjASMPlus did not create $Out" }
$ImageSize = (Get-Item $Out).Length
if ($ImageSize -ne 655360) { throw "TR-DOS image is $ImageSize bytes; expected 655360" }
Write-Host "[P129 BUILD] TRD_IMAGE=$Out SIZE=$ImageSize"
Write-Host "[P129 BUILD] BUILD OK"
