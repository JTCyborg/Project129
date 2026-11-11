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
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $BuildDir "P129BOOT.map")
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $BuildDir "P129BOOT.sym")

Write-Host "[P129 BUILD] VERSION=BOOTSTRAP-0.1.0"
foreach ($Source in @("src/main.c", "src/entry.asm", "src/boot/main.asm")) {
    $Hash = (Get-FileHash $Source -Algorithm SHA256).Hash.Substring(0, 8)
    Write-Host "[P129 BUILD] $Source=$Hash"
}
Write-Host "[P129 BUILD] ZCC=$Zcc"
# -zorg is not a ZX target linker relocation option. The no-CRT image is linked
# at address zero unless the Z80ASM linker is explicitly relocated. Since TR-DOS
# loads P129BOOT.C at #6000, relocate the complete linked image to #6000 so every
# CALL/JR/data reference emitted by SDCC addresses the resident image correctly.
& $Zcc +zx -v -O2 -compiler=sdcc --no-crt -Cl-r24576 -m -s -bn $Resident src/entry.asm src/main.c
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
$MapFile = [System.IO.Path]::ChangeExtension($Resident, ".map")
if (-not (Test-Path $MapFile)) { throw "Z88DK did not produce the required link map: $MapFile" }
$MapText = Get-Content -Raw $MapFile
$EntryMatch = [regex]::Match($MapText, '(?m)^_p129_entry\s*=\s*\$([0-9A-Fa-f]{4})')
$CEntryMatch = [regex]::Match($MapText, '(?m)^_p129_c_entry\s*=\s*\$([0-9A-Fa-f]{4})')
if (-not $EntryMatch.Success -or [Convert]::ToInt32($EntryMatch.Groups[1].Value, 16) -ne 0x6000) {
    throw "Invalid resident entry origin. Expected _p129_entry=#6000; inspect $MapFile"
}
if (-not $CEntryMatch.Success) { throw "C entry symbol _p129_c_entry is missing from $MapFile" }
$CEntryAddress = [Convert]::ToInt32($CEntryMatch.Groups[1].Value, 16)
if ($CEntryAddress -lt 0x6000 -or $CEntryAddress -ge (0x6000 + $ResidentSize)) {
    throw ("C entry is outside the loaded resident image: #{0:X4}" -f $CEntryAddress)
}
$ResidentBytes = [System.IO.File]::ReadAllBytes($Resident)
$CallFound = $false
for ($i = 0; $i -lt ($ResidentBytes.Length - 2); $i++) {
    if ($ResidentBytes[$i] -eq 0xCD) {
        $Target = [int]$ResidentBytes[$i + 1] + ([int]$ResidentBytes[$i + 2] -shl 8)
        if ($Target -eq $CEntryAddress) { $CallFound = $true; break }
    }
}
if (-not $CallFound) { throw ("No CALL to linked C entry #{0:X4} found in resident binary" -f $CEntryAddress) }
Write-Host ("[P129 BUILD] ENTRY=#{0:X4} C_ENTRY=#{1:X4} HANDOFF=VERIFIED" -f 0x6000, $CEntryAddress)
Write-Host "[P129 BUILD] RESIDENT=p129boot.C LOAD=#6000 SIZE=$ResidentSize"
Write-Host "[P129 BUILD] LINK_MAP=$([System.IO.Path]::ChangeExtension($Resident, '.map'))"
Write-Host "[P129 BUILD] LINK_SYMBOLS=$([System.IO.Path]::ChangeExtension($Resident, '.sym'))"

Write-Host "[P129 BUILD] SJASMPLUS=$SjAsmPlus"
& $SjAsmPlus --dirbol src/boot/main.asm
if ($LASTEXITCODE -ne 0) { throw "SjASMPlus packaging failed: $LASTEXITCODE" }
if (-not (Test-Path $Out)) { throw "SjASMPlus did not create $Out" }
$ImageSize = (Get-Item $Out).Length
if ($ImageSize -ne 655360) { throw "TR-DOS image is $ImageSize bytes; expected 655360" }
Write-Host "[P129 BUILD] TRD_IMAGE=$Out SIZE=$ImageSize"
Write-Host "[P129 BUILD] BUILD OK"
