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

Write-Host "[P129 BUILD] VERSION=BOOTSTRAP-0.3.17-MEMORY-PAGE-ALLOCATOR"
foreach ($Source in @("src/main.c", "src/memory.c", "src/memory.h", "src/entry.asm", "src/trdos.asm", "src/ui.asm", "src/rtc.asm", "src/hdd.asm", "src/hdd_fat16.asm", "src/range.c", "src/keyboard.asm", "src/speaker.asm", "src/boot/main.asm")) {
    $Hash = (Get-FileHash $Source -Algorithm SHA256).Hash.Substring(0, 8)
    Write-Host "[P129 BUILD] $Source=$Hash"
}
Write-Host "[P129 BUILD] ZCC=$Zcc"
# -zorg is not a ZX target linker relocation option. The no-CRT image is linked
# at address zero unless the Z80ASM linker is explicitly relocated. Since TR-DOS
# loads P129BOOT.C at #6000, relocate the complete linked image to #6000 so every
# CALL/JR/data reference emitted by SDCC addresses the resident image correctly.
& $Zcc +zx -v -O2 -compiler=sdcc --no-crt -Cl-r24576 -m -s -bn $Resident src/entry.asm src/main.c src/memory.c src/range.c src/keyboard.asm src/speaker.asm src/trdos.asm src/ui.asm src/rtc.asm src/hdd.asm src/hdd_fat16.asm
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
$TrdosMatch = [regex]::Match($MapText, '(?m)^_p129_trdos_preload\s*=\s*\$([0-9A-Fa-f]{4})')
if (-not $TrdosMatch.Success) { throw "TR-DOS preload symbol _p129_trdos_preload is missing from $MapFile" }
$UiInitMatch = [regex]::Match($MapText, '(?m)^_p129_ui_init\s*=\s*\$([0-9A-Fa-f]{4})')
$UiPutcMatch = [regex]::Match($MapText, '(?m)^_p129_ui_putc\s*=\s*\$([0-9A-Fa-f]{4})')
$UiClockMatch = [regex]::Match($MapText, '(?m)^_p129_ui_clock_update\s*=\s*\$([0-9A-Fa-f]{4})')
$RtcProbeMatch = [regex]::Match($MapText, '(?m)^_p129_rtc_probe\s*=\s*\$([0-9A-Fa-f]{4})')
$RtcReadMatch = [regex]::Match($MapText, '(?m)^_p129_rtc_read_current\s*=\s*\$([0-9A-Fa-f]{4})')
$HddProbeMatch = [regex]::Match($MapText, '(?m)^_p129_hdd_probe\s*=\s*\$([0-9A-Fa-f]{4})')
$HddListMatch = [regex]::Match($MapText, '(?m)^_p129_hdd_list_root\s*=\s*\$([0-9A-Fa-f]{4})')
$RangeValidateMatch = [regex]::Match($MapText, '(?m)^_p129_range_validate\s*=\s*\$([0-9A-Fa-f]{4})')
$RangeSelftestMatch = [regex]::Match($MapText, '(?m)^_p129_range_selftest\s*=\s*\$([0-9A-Fa-f]{4})')
$KeyboardInitMatch = [regex]::Match($MapText, '(?m)^_p129_keyboard_init\s*=\s*\$([0-9A-Fa-f]{4})')
$KeyboardPollMatch = [regex]::Match($MapText, '(?m)^_p129_keyboard_poll\s*=\s*\$([0-9A-Fa-f]{4})')
if (-not $UiInitMatch.Success -or -not $UiPutcMatch.Success -or -not $UiClockMatch.Success) { throw "Required ATM UI entry points are missing from $MapFile" }
if (-not $RtcProbeMatch.Success -or -not $RtcReadMatch.Success) { throw "DS12887 RTC entry points are missing from $MapFile" }
if (-not $HddProbeMatch.Success) { throw "Nemo IDE entry point _p129_hdd_probe is missing from $MapFile" }
if (-not $HddListMatch.Success) { throw "FAT16 entry point _p129_hdd_list_root is missing from $MapFile" }
if (-not $RangeValidateMatch.Success -or -not $RangeSelftestMatch.Success) { throw "UINT32 range API entry points are missing from $MapFile" }
if (-not $KeyboardInitMatch.Success -or -not $KeyboardPollMatch.Success) { throw "ATM keyboard entry points are missing from $MapFile" }
$SpeakerTestMatch = [regex]::Match($MapText, '(?m)^_p129_speaker_test_tone\s*=\s*\$([0-9A-Fa-f]{4})')
if (-not $SpeakerTestMatch.Success) { throw "ATM speaker entry point is missing from $MapFile" }
$MemoryInitMatch = [regex]::Match($MapText, '(?m)^_p129_memory_init\s*=\s*\$([0-9A-Fa-f]{4})')
$MemorySelftestMatch = [regex]::Match($MapText, '(?m)^_p129_memory_selftest\s*=\s*\$([0-9A-Fa-f]{4})')
$MemoryAllocMatch = [regex]::Match($MapText, '(?m)^_p129_page_alloc_topdown\s*=\s*\$([0-9A-Fa-f]{4})')
$MemoryFreeMatch = [regex]::Match($MapText, '(?m)^_p129_page_free\s*=\s*\$([0-9A-Fa-f]{4})')
$MemoryPinMatch = [regex]::Match($MapText, '(?m)^_p129_page_pin\s*=\s*\$([0-9A-Fa-f]{4})')
$MemoryUnpinMatch = [regex]::Match($MapText, '(?m)^_p129_page_unpin\s*=\s*\$([0-9A-Fa-f]{4})')
if (-not $MemoryInitMatch.Success -or -not $MemorySelftestMatch.Success -or -not $MemoryAllocMatch.Success -or -not $MemoryFreeMatch.Success -or -not $MemoryPinMatch.Success -or -not $MemoryUnpinMatch.Success) {
    throw "Physical page manager API symbols are missing from $MapFile"
}
$UiInitAddress = [Convert]::ToInt32($UiInitMatch.Groups[1].Value, 16)
$UiPutcAddress = [Convert]::ToInt32($UiPutcMatch.Groups[1].Value, 16)
$UiClockAddress = [Convert]::ToInt32($UiClockMatch.Groups[1].Value, 16)
$RtcProbeAddress = [Convert]::ToInt32($RtcProbeMatch.Groups[1].Value, 16)
$RtcReadAddress = [Convert]::ToInt32($RtcReadMatch.Groups[1].Value, 16)
$HddProbeAddress = [Convert]::ToInt32($HddProbeMatch.Groups[1].Value, 16)
$HddListAddress = [Convert]::ToInt32($HddListMatch.Groups[1].Value, 16)
$RangeValidateAddress = [Convert]::ToInt32($RangeValidateMatch.Groups[1].Value, 16)
$RangeSelftestAddress = [Convert]::ToInt32($RangeSelftestMatch.Groups[1].Value, 16)
$KeyboardInitAddress = [Convert]::ToInt32($KeyboardInitMatch.Groups[1].Value, 16)
$KeyboardPollAddress = [Convert]::ToInt32($KeyboardPollMatch.Groups[1].Value, 16)
$SpeakerTestAddress = [Convert]::ToInt32($SpeakerTestMatch.Groups[1].Value, 16)
$TrdosAddress = [Convert]::ToInt32($TrdosMatch.Groups[1].Value, 16)
$CEntryAddress = [Convert]::ToInt32($CEntryMatch.Groups[1].Value, 16)
if ($CEntryAddress -lt 0x6000 -or $CEntryAddress -ge (0x6000 + $ResidentSize)) {
    throw ("C entry is outside the loaded resident image: #{0:X4}" -f $CEntryAddress)
}
if ($TrdosAddress -lt 0x6000 -or $TrdosAddress -ge (0x6000 + $ResidentSize)) {
    throw ("TR-DOS preload is outside the loaded resident image: #{0:X4}" -f $TrdosAddress)
}
$MemoryAddresses = @($MemoryInitMatch, $MemorySelftestMatch, $MemoryAllocMatch, $MemoryFreeMatch, $MemoryPinMatch, $MemoryUnpinMatch) | ForEach-Object { [Convert]::ToInt32($_.Groups[1].Value, 16) }
foreach ($MemoryAddress in $MemoryAddresses) {
    if ($MemoryAddress -lt 0x6000 -or $MemoryAddress -ge (0x6000 + $ResidentSize)) {
        throw ("Memory manager API entry point is outside the loaded resident image: #{0:X4}" -f $MemoryAddress)
    }
}
foreach ($UiAddress in @($UiInitAddress, $UiPutcAddress, $UiClockAddress, $RtcProbeAddress, $RtcReadAddress, $HddProbeAddress, $HddListAddress, $RangeValidateAddress, $RangeSelftestAddress, $KeyboardInitAddress, $KeyboardPollAddress, $SpeakerTestAddress)) {
    if ($UiAddress -lt 0x6000 -or $UiAddress -ge (0x6000 + $ResidentSize)) {
        throw ("Resident API entry point is outside the loaded resident image: #{0:X4}" -f $UiAddress)
    }
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
Write-Host ("[P129 BUILD] ENTRY=#{0:X4} C_ENTRY=#{1:X4} UI_INIT=#{2:X4} UI_PUTC=#{3:X4} TRDOS_PRELOAD=#{4:X4} RTC_PROBE=#{5:X4} RTC_READ=#{6:X4} UI_CLOCK=#{7:X4} HDD_PROBE=#{8:X4} HDD_LIST=#{9:X4} RANGE_VALIDATE=#{10:X4} RANGE_SELFTEST=#{11:X4} KBD_INIT=#{12:X4} KBD_POLL=#{13:X4} SPEAKER_TEST=#{14:X4} HANDOFF=VERIFIED" -f 0x6000, $CEntryAddress, $UiInitAddress, $UiPutcAddress, $TrdosAddress, $RtcProbeAddress, $RtcReadAddress, $UiClockAddress, $HddProbeAddress, $HddListAddress, $RangeValidateAddress, $RangeSelftestAddress, $KeyboardInitAddress, $KeyboardPollAddress, $SpeakerTestAddress)
Write-Host ("[P129 BUILD] MEMORY_INIT=#{0:X4} MEMORY_SELFTEST=#{1:X4} PAGE_ALLOC=#{2:X4} PAGE_FREE=#{3:X4} PAGE_PIN=#{4:X4} PAGE_UNPIN=#{5:X4}" -f $MemoryAddresses[0], $MemoryAddresses[1], $MemoryAddresses[2], $MemoryAddresses[3], $MemoryAddresses[4], $MemoryAddresses[5])
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
