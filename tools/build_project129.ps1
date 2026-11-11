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

Write-Host "[P129 BUILD] VERSION=BOOTSTRAP-0.3.24-MULTIPAGE-MODULE-IO"
foreach ($Source in @("src/main.c", "src/memory.c", "src/memory.h", "src/map.c", "src/bank.c", "src/bank.h", "src/bank.c", "src/bank.h", "src/map.h", "src/map_hw.asm", "src/entry.asm", "src/trdos.asm", "src/ui.asm", "src/rtc.asm", "src/hdd.asm", "src/hdd_fat16.asm", "src/range.c", "src/keyboard.asm", "src/speaker.asm", "src/boot/main.asm")) {
    $Hash = (Get-FileHash $Source -Algorithm SHA256).Hash.Substring(0, 8)
    Write-Host "[P129 BUILD] $Source=$Hash"
}
Write-Host "[P129 BUILD] ZCC=$Zcc"
# -zorg is not a ZX target linker relocation option. The no-CRT image is linked
# at address zero unless the Z80ASM linker is explicitly relocated. Since TR-DOS
# loads P129BOOT.C at #6000, relocate the complete linked image to #6000 so every
# CALL/JR/data reference emitted by SDCC addresses the resident image correctly.
& $Zcc +zx -v -O2 -compiler=sdcc --no-crt -Cl-r24576 -m -s -bn $Resident src/entry.asm src/main.c src/memory.c src/map.c src/bank.c src/bank.c src/map_hw.asm src/range.c src/keyboard.asm src/speaker.asm src/trdos.asm src/ui.asm src/rtc.asm src/hdd.asm src/hdd_fat16.asm
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
$UiLeaseTestMatch = [regex]::Match($MapText, '(?m)^_p129_ui_lease_selftest\s*=\s*\$([0-9A-Fa-f]{4})')
$UiLeaseQuiesceMatch = [regex]::Match($MapText, '(?m)^_p129_ui_quiesce\s*=\s*\$([0-9A-Fa-f]{4})')
$UiLeaseBeginMatch = [regex]::Match($MapText, '(?m)^_p129_ui_handoff_begin\s*=\s*\$([0-9A-Fa-f]{4})')
$UiLeaseEndMatch = [regex]::Match($MapText, '(?m)^_p129_ui_handoff_end\s*=\s*\$([0-9A-Fa-f]{4})')
$UiLeaseResumeMatch = [regex]::Match($MapText, '(?m)^_p129_ui_resume\s*=\s*\$([0-9A-Fa-f]{4})')
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
if (-not $UiLeaseTestMatch.Success -or -not $UiLeaseQuiesceMatch.Success -or -not $UiLeaseBeginMatch.Success -or -not $UiLeaseEndMatch.Success -or -not $UiLeaseResumeMatch.Success) { throw "W3 UI lease entry points are missing from $MapFile" }
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
$MemoryReserveMatch = [regex]::Match($MapText, '(?m)^_p129_page_reserve\s*=\s*\$([0-9A-Fa-f]{4})')
$MemoryRefcountMatch = [regex]::Match($MapText, '(?m)^_p129_page_refcount\s*=\s*\$([0-9A-Fa-f]{4})')
$MemoryReservedMatch = [regex]::Match($MapText, '(?m)^_p129_page_is_reserved\s*=\s*\$([0-9A-Fa-f]{4})')
$MemoryAllocatedMatch = [regex]::Match($MapText, '(?m)^_p129_page_is_allocated\s*=\s*\$([0-9A-Fa-f]{4})')
$MemoryFreeCountMatch = [regex]::Match($MapText, '(?m)^_p129_memory_free_count\s*=\s*\$([0-9A-Fa-f]{4})')
$MapInitMatch = [regex]::Match($MapText, '(?m)^_p129_map_init\s*=\s*\$([0-9A-Fa-f]{4})')
$MapSelftestMatch = [regex]::Match($MapText, '(?m)^_p129_map_selftest\s*=\s*\$([0-9A-Fa-f]{4})')
$MapPortMatch = [regex]::Match($MapText, '(?m)^_p129_map_window_port\s*=\s*\$([0-9A-Fa-f]{4})')
$MapBeginMatch = [regex]::Match($MapText, '(?m)^_p129_map_txn_begin\s*=\s*\$([0-9A-Fa-f]{4})')
$MapCommitMatch = [regex]::Match($MapText, '(?m)^_p129_map_txn_commit\s*=\s*\$([0-9A-Fa-f]{4})')
$MapRollbackMatch = [regex]::Match($MapText, '(?m)^_p129_map_txn_rollback\s*=\s*\$([0-9A-Fa-f]{4})')
$MapAcceptMatch = [regex]::Match($MapText, '(?m)^_p129_map_txn_accept\s*=\s*\$([0-9A-Fa-f]{4})')
$MapRestoreMatch = [regex]::Match($MapText, '(?m)^_p129_map_restore_boot\s*=\s*\$([0-9A-Fa-f]{4})')
$BankEnterMatch = [regex]::Match($MapText, '(?m)^_p129_map_w3_bank_enter\s*=\s*\$([0-9A-Fa-f]{4})')
$BankLeaveMatch = [regex]::Match($MapText, '(?m)^_p129_map_w3_bank_leave\s*=\s*\$([0-9A-Fa-f]{4})')
$PageCopyMatch = [regex]::Match($MapText, '(?m)^_p129_map_page_copy\s*=\s*\$([0-9A-Fa-f]{4})')
$PageCopySelftestMatch = [regex]::Match($MapText, '(?m)^_p129_map_page_copy_selftest\s*=\s*\$([0-9A-Fa-f]{4})')
$BankModuleAllocMatch = [regex]::Match($MapText, '(?m)^_p129_bank_module_alloc\s*=\s*\$([0-9A-Fa-f]{4})')
$BankModuleReadMatch = [regex]::Match($MapText, '(?m)^_p129_bank_module_read\s*=\s*\$([0-9A-Fa-f]{4})')
$BankModuleWriteMatch = [regex]::Match($MapText, '(?m)^_p129_bank_module_write\s*=\s*\$([0-9A-Fa-f]{4})')
$BankModuleSelftestMatch = [regex]::Match($MapText, '(?m)^_p129_bank_module_selftest\s*=\s*\$([0-9A-Fa-f]{4})')
$BankSelftestMatch = [regex]::Match($MapText, '(?m)^_p129_map_w3_bank_selftest\s*=\s*\$([0-9A-Fa-f]{4})')
$MapHwWriteMatch = [regex]::Match($MapText, '(?m)^_p129_map_hw_write\s*=\s*\$([0-9A-Fa-f]{4})')
$MapHwSelftestMatch = [regex]::Match($MapText, '(?m)^_p129_map_w3_hw_selftest\s*=\s*\$([0-9A-Fa-f]{4})')
if (-not $MapInitMatch.Success -or -not $MapSelftestMatch.Success -or -not $MapPortMatch.Success -or -not $MapBeginMatch.Success -or -not $MapCommitMatch.Success -or -not $MapRollbackMatch.Success -or -not $MapAcceptMatch.Success -or -not $MapRestoreMatch.Success -or -not $BankEnterMatch.Success -or -not $BankLeaveMatch.Success -or -not $BankSelftestMatch.Success -or -not $MapHwWriteMatch.Success -or -not $MapHwSelftestMatch.Success -or -not $PageCopyMatch.Success -or -not $PageCopySelftestMatch.Success -or -not $BankModuleAllocMatch.Success -or -not $BankModuleReadMatch.Success -or -not $BankModuleWriteMatch.Success -or -not $BankModuleSelftestMatch.Success) {
    throw "Software page mapper API symbols are missing from $MapFile"
}
if (-not $MemoryInitMatch.Success -or -not $MemorySelftestMatch.Success -or -not $MemoryAllocMatch.Success -or -not $MemoryFreeMatch.Success -or -not $MemoryPinMatch.Success -or -not $MemoryUnpinMatch.Success -or -not $MemoryReserveMatch.Success -or -not $MemoryRefcountMatch.Success -or -not $MemoryReservedMatch.Success -or -not $MemoryAllocatedMatch.Success -or -not $MemoryFreeCountMatch.Success) {
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
$MemoryAddresses = @($MemoryInitMatch, $MemorySelftestMatch, $MemoryAllocMatch, $MemoryFreeMatch, $MemoryPinMatch, $MemoryUnpinMatch, $MemoryReserveMatch, $MemoryRefcountMatch, $MemoryReservedMatch, $MemoryAllocatedMatch, $MemoryFreeCountMatch) | ForEach-Object { [Convert]::ToInt32($_.Groups[1].Value, 16) }
$MapAddresses = @($MapInitMatch, $MapSelftestMatch, $MapPortMatch, $MapBeginMatch, $MapCommitMatch, $MapRollbackMatch, $MapAcceptMatch, $MapRestoreMatch, $BankEnterMatch, $BankLeaveMatch, $BankSelftestMatch, $MapHwWriteMatch, $MapHwSelftestMatch, $PageCopyMatch, $PageCopySelftestMatch, $BankModuleAllocMatch, $BankModuleReadMatch, $BankModuleWriteMatch, $BankModuleSelftestMatch) | ForEach-Object { [Convert]::ToInt32($_.Groups[1].Value, 16) }
foreach ($MapAddress in $MapAddresses) {
    if ($MapAddress -lt 0x6000 -or $MapAddress -ge (0x6000 + $ResidentSize)) {
        throw ("Software mapper API entry point is outside the loaded resident image: #{0:X4}" -f $MapAddress)
    }
}
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
Write-Host ("[P129 BUILD] MAP_INIT=#{0:X4} MAP_SELFTEST=#{1:X4} MAP_PORT=#{2:X4} MAP_BEGIN=#{3:X4} MAP_COMMIT=#{4:X4} MAP_ROLLBACK=#{5:X4} MAP_ACCEPT=#{6:X4} MAP_RESTORE=#{7:X4} BANK_ENTER=#{8:X4} BANK_LEAVE=#{9:X4} BANK_SELFTEST=#{10:X4} HW_WRITE=#{11:X4} HW_SELFTEST=#{12:X4}" -f $MapAddresses[0], $MapAddresses[1], $MapAddresses[2], $MapAddresses[3], $MapAddresses[4], $MapAddresses[5], $MapAddresses[6], $MapAddresses[7], $MapAddresses[8], $MapAddresses[9], $MapAddresses[10], $MapAddresses[11], $MapAddresses[12])
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
