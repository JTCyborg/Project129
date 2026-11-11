[CmdletBinding()]
param(
    [string]$SjAsmPlus = (Join-Path $PSScriptRoot "sjasmplus.exe"),
    [string]$Output = ".\disk_A.trd"
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
if (-not (Test-Path $SjAsmPlus)) {
    $AssemblerCommand = Get-Command $SjAsmPlus -ErrorAction SilentlyContinue
    if (-not $AssemblerCommand) { throw "SjASMPlus not found: $SjAsmPlus" }
    $SjAsmPlus = $AssemblerCommand.Source
}
$BuildDir = Join-Path $Root "build"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$Out = [System.IO.Path]::GetFullPath($Output)
if ([System.IO.Path]::GetFileName($Out) -ne "disk_A.trd") {
    throw "Project127 main.asm writes disk_A.trd; use -Output disk_A.trd"
}
Remove-Item -Force -ErrorAction SilentlyContinue $Out
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $BuildDir "list.txt")
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $BuildDir "map.txt")
Write-Host "[P127 BUILD] ASSEMBLER=$SjAsmPlus"
Write-Host "[P127 BUILD] SOURCE=src/main.asm"
& $SjAsmPlus --dirbol "--lst=build/list.txt" "--sym=build/map.txt" src/main.asm
if ($LASTEXITCODE -ne 0) { throw "SjASMPlus failed: $LASTEXITCODE" }
if (-not (Test-Path $Out)) { throw "SjASMPlus did not create $Out" }
$ImageSize = (Get-Item $Out).Length
if ($ImageSize -ne 655360) { throw "TR-DOS image is $ImageSize bytes; expected 655360" }
Copy-Item -Force $Out (Join-Path $BuildDir "disk_A.trd")
Write-Host "[P127 BUILD] BASIC=boot.B"
Write-Host "[P127 BUILD] STAGE2=P127BOOT.C LOAD=#6000"
Write-Host "[P127 BUILD] TRD_IMAGE=$Out ($ImageSize bytes)"
Write-Host "[P127 BUILD] BUILD OK"
