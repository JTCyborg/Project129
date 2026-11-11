# Project126 implementation status

This document records actual artifacts and their verification state; it is not a projection of the roadmap.

## ATM host IPC transport primitives

- ATM-side source: `atm_host/neogs_ipc.asm`, public interface: `atm_host/neogs_ipc.inc`; assembly unit: `atm_host/neogs_ipc_assemble.asm`.
- ATM source version is now `P126 ATM_IPC v0.2.0`; the common ABI constants are in `shared/p126_ipc_protocol.inc`.
- Existing bounded CBIT/DBIT polling, GSCOM command and legacy GSDAT byte helpers remain available. GSDAT helpers are compatibility/bootstrap primitives, not the application payload transport.
- Added ATM CRC-16/CCITT-FALSE byte-update routine and executable standard-vector self-test (123456789 → 29B1h). Startup does not call the self-test yet.
- Added NeoGS-side counterpart in `neogs_sub/p126_ipc.asm`, with standalone audit unit `neogs_sub/p126_ipc_assemble.asm`; it uses the same shared constants and test vector. This is a reusable primitive, not yet connected to a resident command loop.
- ATM assembly origin remains image-relative `ORG 0000h`; final host load address is not assigned.
- **BUILD PASS:** GitHub Actions run [42303465405](https://github.com/JTCyborg/Project126/actions/runs/42303465405), commit `50bf91bf35a0ef89e5d5ebb128fb36b46ceac479`; SjASMPlus assembly and TR-DOS packaging completed successfully. The build assembles the ATM and NeoGS CRC primitives and publishes the new `P126_NGS_IPC.bin`, `NEOGS_IPC.lst` and `NEOGS_IPC.map` alongside existing artifacts. No live Project126 DMA/IPC hardware test has been performed.

## Unified DMA/IPC ABI 1.0

- Normative specification: `docs/P126_DMA_IPC_PROTOCOL.md`; architecture reference: `SCENARIO.md` section 7.1.1.
- Fixed: control/data plane separation; ATM-facing DMA aperture contract; NeoGS-only DMA register ownership; GSCOM commands E0h..E3h and FFh end marker; 18-byte P126 frame header; little-endian fields; message types/flags; CRC-16/CCITT-FALSE; per-direction sequence rules; duplicate suppression; ordered fragmentation; status codes; initial service namespace; READY/end/CBIT completion lifecycle.
- Added shared constants in `shared/p126_ipc_protocol.inc`, imported by the ATM IPC public include.
- Added CRC update and standard test-vector routines on both endpoints: `atm_host/neogs_ipc.asm` and `neogs_sub/p126_ipc.asm`.
- **IN PROGRESS:** the contract and CRC primitives on both processors are implemented in source. Complete frame encode/decode, DMA send/receive, session negotiation, sequence state, resident NeoGS command endpoint, fragment reassembly and service dispatch remain unimplemented.
- **OPEN / MUST NOT GUESS:** ATM staging-buffer addresses, ATM paging/buffer placement and final DMA window integration. The NeoGS 4 MiB physical allocation is now assigned in docs/P126_NEOGS_MEMORY_MAP.md; NeoGS logical 64 KiB windows and hardware page selection remain open. Project125 physical addresses/layout are reference material, not Project126 allocations.
- **Verification:** BUILD PASS for both CRC primitives and all three assembly units is recorded in run [42303465405](https://github.com/JTCyborg/Project126/actions/runs/42303465405). CRC self-test routines are assembled but have not been executed on target hardware. Complete DMA directions and frame transport are not implemented and are not claimed as Project126 HARDWARE PASS.

## Build pipeline and address-placement audit

- Assembler: repository-pinned `tools/sjasmplus.exe` (SjASMPlus 1.23.1).
- Local build entry point: `build_project126.bat` (Windows double-click launcher), which invokes `tools/build_project126.ps1`.
- CI: `.github/workflows/neogs-assembly.yml`; CI invokes the same PowerShell build script as a local build.
- Every successful assembly must produce all three modules:
  - `build/x86_cpu_state.bin`, `build/NEOGS.lst`, `build/NEOGS.map`;
  - `build/ATM_IPC.bin`, `build/ATM.lst`, `build/ATM.map`;
  - `build/P126_NGS_IPC.bin`, `build/NEOGS_IPC.lst`, `build/NEOGS_IPC.map`.
- The script deletes stale outputs before assembling and fails if any product is missing.
- NeoGS assembly translation unit: `neogs_sub/x86_cpu_state_assemble.asm`, version v0.6.0. It exports explicit start/end labels for the CPU-state and ALU modules and displays each module's start, end and size, plus the complete image end and size.
- NeoGS assembly-time assertions enforce non-empty modules, contiguous placement (ALU begins exactly at CPU-state end), and total image size no greater than 256 KiB.
- ATM assembly translation unit exports the IPC module start/end/size and asserts a non-empty image no larger than 64 KiB.
- **Address-space qualification:** both assembly origins are image-relative offsets, not final physical NeoGS/ATM load addresses. The guest x86 decode map and NeoGS physical allocation are now specified; the NeoGS logical 64 KiB window mapping, final physical load address and ATM integration/load point remain to be fixed.
- CI publishes all three binaries, listings and maps plus the TR-DOS disk image in one audit artifact.

## Latest verified assembly

- GitHub Actions run `42274548106`, commit `20f5945e47f118706821d6d47b237be8b9b160a3`: SjASMPlus 1.23.1; both modules assembled with 0 errors and 0 warnings.
- NeoGS: 695 source lines, `x86_cpu_state.bin` 1,155 bytes, `NEOGS.lst` 37,553 bytes, `NEOGS.map` 2,732 bytes.
- ATM: 235 source lines, `ATM_IPC.bin` 181 bytes, `ATM.lst` 14,766 bytes, `ATM.map` 1,407 bytes.
- Combined audit artifact `project126-atm-neogs-assembly-audit` uploaded successfully: [workflow run and artifact](https://github.com/JTCyborg/Project126/actions/runs/42274548106).
- This is an assembly/build result only; the IPC handshake has not yet been exercised on physical ATM/NeoGS hardware.

## PCem reference integrity tooling

- `docs/PCEM_REFERENCE_MAP.md`
- `tools/verify_pcem_reference.py`
- Status: committed. The verifier has not yet been executed in a local checkout.
- Purpose: pin the CPU, memory, I/O, interrupt, timer, keyboard and VGA reference files by Git blob identity.

## x86 CPU architectural state foundation

- Source: `neogs_sub/x86_cpu_state.asm`
- Assembly unit: `neogs_sub/x86_cpu_state_assemble.asm`
- Runtime version emitter: `x86_cpu_emit_version`, string `[P126 X86_CPU_STATE v0.1.0]`. Startup call is not wired because the Project126 firmware entry point and NeoGS memory map are not yet defined.
- PCem comparison points: `PCem/808x.c:resetx86()`, `PCem/cpu.h:CPU_8086`.
- Implemented in source: deterministic register reset, 8086 reset vector FFFF:0000, FLAGS=0002h, 20-bit segment:offset physical-address calculation and target-side self-test vectors.
- Status: source assembled successfully in CI run `42273068373`; target-side self-test has not been executed on NeoGS.
- Not implemented by this module: instruction decoding/execution, memory-region mapping, interrupt delivery, timing or device models.

## x86 ALU foundation

- Source: `neogs_sub/x86_alu.asm`, version `P126 / X86_ALU v0.2.0`.
- PCem comparison points: `PCem/808x.c:setadd8()`, `setsub8()` and adjacent flag helpers.
- Implemented in source: 8-bit and 16-bit ADD/SUB; CF, PF, AF, ZF, SF and OF translation into guest FLAGS; preservation of non-arithmetic flags. A runtime version emitter reports the ALU component on NeoGS #EF.
- Included target-side regression vectors: 8-bit and 16-bit signed overflow, carry/borrow, auxiliary carry/borrow, zero, sign, parity and preservation of TF/IF/DF.
- Status: assembled successfully in CI run `42273068373`; target-side regression vectors have not yet been executed on NeoGS.

## Verification policy

A committed source file is not automatically a successful runtime or hardware test. Keep assembly, emulator, NeoGS runtime and ATM hardware results separate. The current CPU-state and ALU modules have BUILD PASS only; they do not yet constitute an executable x86 CPU.


## TR-DOS boot image

- Disk assembly source: `atm_host/project126_disk.asm`.
- BASIC boot loader: `atm_host/boot_loader.asm`, version `P126_TRDOS_BOOT v0.1.0`; based on the proven Project125 boot sequence.
- ATM host application: `atm_host/project126_main.asm`, version `P126_ATM_HOST v0.1.0`; loaded at 6000h and entered at 6009h.
- The disk contains `BOOT.B`, `PROJ126.C`, and `X86CORE.C`.
- Build outputs: root `disk_A.trd`, `build/disk_A.trd`, `build/ATM_DISK.lst`, and `build/ATM_DISK.map`.
- **BUILD PASS:** GitHub Actions run `42275327342`, commit `79b28a4266fdb3cdd151b7842d0b78ed73e5d2c4`. SjASMPlus assembled the disk unit (436 lines) with 0 errors and 0 warnings; image size 655,360 bytes.
- Verified TR-DOS entries: `BOOT.B` 475 bytes / 2 sectors; `PROJ126.C` 248 bytes / 1 sector; `X86CORE.C` 1,155 bytes / 5 sectors.
- [Download TR-DOS disk image and build artifacts](https://github.com/JTCyborg/Project126/actions/runs/42275327342).
- Functional boundary: boot.B loads and starts the ATM host shell. The x86 core is present as a disk file but is not yet transferred to NeoGS or executed.


## ATM native display shell

- Source: `atm_host/p126_screen_console.asm`, adapted from the working Project125 ATM Turbo 2+ 80x25 text console.
- The console module is placed at `#A000`; the host entry remains at `#6009` in the `#6000` image.
- Startup order: emit the ATM/IPC version banners on `#EF`; initialize ATM shadow ports and the 80x25 text mode; clear the display; draw the Project126 status panel; then write the current host/guest state into the lower log.
- The status panel explicitly reports that BIOS is not loaded and x86 execution has not started. The current shell still does not upload or start NeoGS firmware.
- The TR-DOS disk image continues to contain `BOOT.B`, `PROJ126.C`, and `X86CORE.C`.
- This change is intended to address the previously missing on-screen interface. It is not a claim of physical ATM display validation; that requires the user's runtime test.


## ATM host entry diagnostic

- The first instructions at the BASIC USR target `6009h` now emit the single character `>` to the ATM debug port `#EF`, before stack setup, version banners, or display/paging initialization.
- This is a diagnostic marker only; it does not alter `BOOT.B`, its TR-DOS startup trampoline, `CLEAR 24000`, `LOAD`, or the `USR 24585` transfer address.
- Expected runtime sequence: loader's `02` marker, then `>`, then `[P126 ATM HOST v0.1.0]`. Absence of `>` means control did not reach `6009h`, or the ATM #EF output path is not displaying application writes. Presence of `>` but absence of the banner localizes the failure after entry, before/during the string output.
- This diagnostic is not a claim of hardware runtime validation.


## ATM TR-DOS catalogue and BIOS file staging

- Sources: `atm_host/p126_disk_catalog.asm`, `atm_host/project126_main.asm`, and `atm_host/project126_disk.asm`.
- Implemented: early TR-DOS directory read before ATM video/shadow-port initialization; eight individual one-sector reads (`C=5, B=1`); directory buffer at `#C800..#CFFF`; directory parsing (up to 128 descriptors); filtering of supported TR-DOS file types (`B/C/D/#`); nine visible rows; selected-entry tracking and scrolling with CAPS SHIFT+7 / CAPS SHIFT+6.
- Keyboard matrix correction: UP=CAPS+7 (row #EFFE bit 1), DOWN=CAPS+6 (row #EFFE bit 0), RIGHT=CAPS+8 (row #EFFE bit 2), LEFT=CAPS+5 (row #F7FE bit 4), ENTER=(row #BFFE bit 0). Per-cursor-press timestamped serial logging removed to avoid UI-loop overhead. Source/build verified; hardware retest pending.
- The TR-DOS image contains three 8 KiB BIOS images under TR-DOS names: `BIOS1.C` (from `bios/27c64d.bin`), `BIOS2.C` (from `bios/Bios.bin`), and `COMPAQ.C` (from `bios/Compaq Portable Plus 100666-001 Rev C.bin`).
- Implemented source: ENTER confirms the selected descriptor; ATM temporarily restores the initial TR-DOS mapping, opens the selected `.C` through Project125 ROM calls `C=#0A/#08`, requires exactly 8192 bytes / 32 sectors, and reads the image using `C=5, B=1`. ATM video mapping is reinitialized after disk I/O.
- Implemented source: BIOS image is sent as ABI 1.0 `IMAGE_BEGIN`, one `IMAGE_FRAGMENT` (standard 10-byte extension, index 0/count 1, 8192 data bytes), and `IMAGE_FINISH`. NeoGS validates each frame, installs the payload at physical SYSBIOS page 10h / offset 0000h, and marks the resident BIOS-ready state. CBIT is released only after the service handler completes.
- **BUILD PASS:** GitHub Actions run [42360319486](https://github.com/JTCyborg/Project126/actions/runs/42360319486), commit `e905e205f40f122af20a336c397974a69300ba9d`; NeoGS, ATM IPC, standalone NeoGS IPC, ATM host and TR-DOS image assembly/package completed successfully. Existing generated-path backslash warning remains.
- **HARDWARE:** BIOS selection/transfer/slot installation are pending a fresh ATM/NeoGS target log. Existing catalogue hardware confirmation does not validate BIOS loading.
- **NOT IMPLEMENTED:** 8086 reset-vector execution, VGA register model/initialization through BIOS, NeoGS scanout/framebuffer generation, and NeoGS→ATM frame transport. BIOS image installation is not a BIOS boot PASS.

## ATM startup and TR-DOS catalogue diagnostics

- ATM `#EF` stage diagnostics remain in `atm_host/project126_main.asm` and `atm_host/p126_disk_catalog.asm`; they identify startup, disk-read, directory-scan, drawing and keyboard-input stages.
- The earlier diagnostic commits `7bb87ac204bd7a32d4bc62eb0465664482ad6de3` and `f03c7999ff3b8f3ae27edfe5a856691c816d5da2` were superseded by the TR-DOS access-ordering corrections recorded below.
- The former failure state (catalogue empty / disk-read stage unresolved) is closed by the later successful build and the user's hardware confirmation. Do not treat old diagnostic notes as the current state of the catalogue.

## Current work queue (2026-11-06)

| Area | State | Notes |
|---|---|---|
| ATM host entry and version output | HARDWARE CONFIRMED | Host and IPC banners observed in the user's runtime log. |
| DS12887 RTC integration | HARDWARE CONFIRMED IN PRIOR RUN | ATM shadow-port activation and Project125-derived read-only RTC path; valid timestamp was previously observed. |
| ATM 80x25 status console | HARDWARE CONFIRMED FOR CURRENT CATALOGUE UI | The catalogue interface is displayed on the target ATM. |
| TR-DOS directory read | HARDWARE PASS | Early read before ATM video init; eight individual C=5, B=1 sector reads. User confirmed operation. |
| Unified DMA/IPC ABI 1.0 | IN PROGRESS; BUILD PASS for CRC primitives | Contract, common constants and ATM/NeoGS CRC routines assembled; frame codec, DMA endpoints, session/sequence handling and hardware tests remain. |
| Directory filtering, rendering and scrolling | HARDWARE PASS | Nine-row catalogue and CAPS SHIFT+7/6 navigation confirmed by user. |
| BIOS images in TR-DOS disk | BUILD PASS | BIOS1.C, BIOS2.C and COMPAQ.C, each 8192 bytes; included in successful disk build. |
| BIOS choice on ENTER | SOURCE IMPLEMENTED; BUILD PASS | ENTER confirms the selected descriptor; the one-shot catalogue is disabled and the ATM text UI is cleared after successful transfer. Hardware test pending. |
| BIOS file transfer ATM → NeoGS | SOURCE IMPLEMENTED; BUILD PASS | Project125 TR-DOS file-open/sector-read sequence; ABI IMAGE BEGIN/one FRAGMENT/FINISH; page-42 DMA staging. Hardware test pending. |
| NeoGS BIOS receive and placement | SOURCE IMPLEMENTED; BUILD PASS | Validated image fragment is copied to physical SYSBIOS page 10h; IMAGE_FINISH sets BIOS-ready state. Hardware page-10 readback pending. 8086 execution entry is separate and not implemented. |
| Initial x86 BIOS bring-up | SOURCE IMPLEMENTED; BUILD VALIDATION PENDING | After verified SYSBIOS installation, execute the reset vector and up to 16 further BIOS instructions; stop on HLT, unsupported opcode or memory fault. Target runtime log pending. |
| Full x86 BIOS boot | NOT IMPLEMENTED | Complete BIOS initialization, VGA model/BIOS integration, device services and guest boot remain future work. |



## TR-DOS access ordering correction (2026-11-06)

- Compared Project126 catalogue access with the working Project125 startup and BIOS sector loader.
- Corrected startup ordering: Project126 selects the legacy TR-DOS paging state (`7FFD=#10`, `5C3B=#10`, `EFF7=0`) and reads the directory before ATM video/shadow-port initialization.
- Removed the standalone `C=1` drive-select call; it was not part of Project125's proven file-access sequence.
- Replaced one `C=5, B=8` call with eight individual `C=5, B=1` calls. Each call reloads D/E/HL and clears/checks `#5D0F/#5D10`.
- Directory buffer: `#C800..#CFFF`; parsing, display and keyboard navigation run in the later UI phase.
- **Verification:** commits `94c7436a258ccab48182f72446609738ec7e80ca`, `591c00eed1227bc89ecbf9658942297ac6867193`, and `ea916953044349e68ef3cc8af93fc8f5020b483e`. GitHub Actions run [42302005699](https://github.com/JTCyborg/Project126/actions/runs/42302005699) completed successfully. The user subsequently confirmed the catalogue stage on physical ATM hardware.


## NeoGS physical RAM allocation v0.1

- Normative map: docs/P126_NEOGS_MEMORY_MAP.md; machine-readable constants/assertions: shared/p126_neogs_memory_map.inc.
- Allocation: 256 physical pages × 16 KiB = 4 MiB. Pages 00–0F resident kernel (256 KiB); 10–1F system BIOS slot (256 KiB); 20–2F separate VGA BIOS slot (256 KiB); 30–3F VGA VRAM (256 KiB); 40–41 ATM presentation frame (32 KiB); 42 DMA backing page (16 KiB); 43 IPC scratch (16 KiB); 44–83 guest RAM backing (1 MiB); 84–FF unassigned reserve (1.9375 MiB).
- This is a physical RAM allocation only. It does not assign guest x86 logical ROM/RAM/device addresses, NeoGS logical Z80 windows, ATM staging addresses or DMA register encoding.
- Build integration: the NeoGS assembly translation unit includes the map constants and checks all region boundaries, adjacency, capacities and the 4 MiB limit with assembler ASSERTs. Existing NEOGS.lst/NEOGS.map therefore include the allocation symbols.
- Physical paging and DMA hardware tests are not claimed. BUILD PASS is pending CI for this commit.


## Guest 8086 memory map and ATM-PC/XT hybrid profile v0.1

- Profile: docs/P126_ATM_PC_PROFILE.md; machine-readable guest map and port constants: shared/p126_x86_machine_map.inc.
- Guest physical space: 1 MiB, 20-bit wrap, no A20. Full 1 MiB NeoGS guest-RAM backing remains allocated. Read/write decode at reset: 00000–9FFFF RAM (640 KiB); A0000–BFFFF VGA aperture (128 KiB); C0000–C7FFF VGA BIOS ROM (32 KiB); C8000–FDFFF upper RAM (216 KiB); FE000–FFFFF system BIOS ROM (8 KiB). Exposed guest RAM total: 856 KiB.
- This is a custom ATM-PC/XT hybrid. The 216 KiB C8000–FDFFF region is intentionally RAM, not a conventional PC option-ROM/UMA reservation. VGA aperture follows PCem VGA GC register 6 mapping; 256 KiB VRAM is separate backing.
- The current 8 KiB XT-compatible system BIOS images map at FE000–FFFFF; reset vector FFFF0 is image offset 1FF0. The 256 KiB NeoGS BIOS slot is storage capacity, not a linear guest ROM aperture. Images larger than 8 KiB need a separate banking/window policy.
- Added x86_mem_classify and target-side boundary vectors for low RAM, VGA aperture, VGA BIOS, upper RAM and system BIOS. Runtime memory handlers are not implemented.
- I/O decode profile reserves PC/XT-style DMA/PIC/PIT/PPI/VGA/FDC and ATA task-file ranges; DS12887-compatible 70h/71h is a custom extension with ATM as the physical time source. All guest I/O remains software-modeled; no direct NeoGS physical IN/OUT.
- BUILD PASS pending CI for the current commit; target execution of the new classifier and any guest BIOS POST/boot are not claimed.


### Verification — guest memory map and ATM-PC/XT hybrid profile

- **BUILD PASS:** GitHub Actions run [42305863741](https://github.com/JTCyborg/Project126/actions/runs/42305863741), source commit `4e4edf3bbe25f6ffbe2e71cb6d51f411f546b440`. NeoGS assembly completed with 0 errors and 0 warnings; the new memory map constants and classifier assembled into `build/x86_cpu_state.bin` (1,416 bytes), with updated `NEOGS.lst` and `NEOGS.map`.
- ATM IPC and NeoGS IPC audit units also assembled successfully. TR-DOS disk packaging completed at 655,360 bytes; BIOS1.C, BIOS2.C and COMPAQ.C were each verified as 8,192 bytes / 32 sectors. Artifact: `project126-trdos-disk-and-build` (run 42305863741).
- The disk packaging assembler emitted one pre-existing path-format warning for the generated source filename containing a backslash; no assembly errors occurred. GitHub runner Node.js deprecation notices are unrelated to project source.
- The new classifier has target-side boundary test vectors in source, but the self-test has not yet been executed on NeoGS. No guest memory read/write runtime, BIOS POST, VGA output, emulator PASS or hardware PASS is claimed.


## Guest RAM banked access layer v0.1

- Assigned NeoGS logical WIN3 (C000h–FFFFh) as the dedicated 16 KiB physical RAM bank window, selected through port 23h. WIN0–WIN2 are reserved for executing resident code, data, stack and interrupt handlers during a banked access.
- Added `x86_guest_ram_select_page`, `x86_guest_ram_read8` and `x86_guest_ram_write8` to the NeoGS x86 state module. Guest RAM backing is linear: NeoGS physical offset 110000h + 20-bit guest physical address, pages 44h–83h.
- RAM helpers check the guest address decoder and reject VGA/ROM overlay regions rather than incorrectly treating them as RAM. They do not yet implement VGA/ROM access.
- Updated `docs/P126_NEOGS_MEMORY_MAP.md` and `SCENARIO.md` with the WIN3 contract and execution constraints.
- **Verification status:** source-level only until CI assembles this revision. No target-side page-switch, read/write retention, interrupt-safety or guest execution test is claimed. Final resident placement in WIN0–WIN2 remains an integration requirement.


### Verification — banked guest RAM access v0.1

- **BUILD PASS:** GitHub Actions run [42306324753](https://github.com/JTCyborg/Project126/actions/runs/42306324753), source commit `d53e16500183f65f76d93f7b02786829f15c3191`.
- NeoGS memory module assembled successfully: 0 errors, 0 warnings, image size 1,492 bytes. Build map confirms bank aperture C000h and WIN3 page-select port 0023h. ATM IPC and NeoGS IPC units also assembled; TR-DOS disk generation and artifact upload completed.
- The disk assembler emitted the existing generated-filename backslash warning; the NeoGS module itself had no warnings.
- **Not yet verified:** actual WIN3 page selection/read/write on NeoGS hardware or a cycle-accurate emulator. No runtime RAM-retention PASS is claimed. The helpers require the resident runtime to keep code, data, stack and interrupt handlers outside WIN3.


## Unified guest memory dispatcher

- Source: `neogs_sub/x86_cpu_state.asm`; shared page-bias constants: `shared/p126_neogs_memory_map.inc`.
- Added byte read/write entry points `x86_guest_mem_read8` and `x86_guest_mem_write8`, dispatching by `x86_mem_classify`.
- RAM accesses use the existing guest RAM backend. VGA aperture accesses use the first 128 KiB of the dedicated VRAM allocation as linear staging. VGA BIOS and system BIOS reads use their independent physical slots; writes to either ROM are rejected.
- The VGA aperture implementation is not a complete VGA memory model: plane/latch/read/write-mode semantics and register-controlled mapping remain pending.
- Scenario and physical map documentation record exact guest-to-NeoGS page mapping and the limitations.
- Verification is pending CI for this commit. No emulator or hardware runtime PASS is claimed.


### Verification — unified guest memory dispatcher

- **BUILD PASS:** GitHub Actions run [42306662917](https://github.com/JTCyborg/Project126/actions/runs/42306662917), source commit `b4b21ff7dcc4a161c9912d03162487e02dc542fb`.
- SjASMPlus 1.23.1 assembled the NeoGS unit with 0 errors and 0 warnings. The x86 state module is 842 bytes; combined x86 state/ALU image is 1,616 bytes. ATM IPC (246 bytes) and NeoGS IPC (65 bytes) also assembled with 0 errors and 0 warnings.
- TR-DOS image generated at 655,360 bytes. `X86CORE.C` is 1,616 bytes / 7 sectors; BIOS1.C, BIOS2.C and COMPAQ.C are each 8,192 bytes / 32 sectors. Listings, maps and disk artifact were published.
- The disk assembler retains one pre-existing generated-path backslash warning; the NeoGS and IPC assembly units report no warnings.
- **Not verified:** actual WIN3 paging/read/write on target hardware, ROM contents in physical slots, guest BIOS POST, VGA plane semantics or scanout. This is BUILD PASS only.


## ABI 1.0 frame validation

- Implemented matching ATM and NeoGS frame validators in `atm_host/neogs_ipc.asm` and `neogs_sub/p126_ipc.asm`.
- Validation covers minimum header length, P126 magic, ABI major/minor, legal message type, reserved flags, exact 18+payload length and full CRC-16/CCITT-FALSE.
- Return convention: carry clear/A=0 valid; carry set/A=ABI status code invalid. Validators are non-reentrant.
- Hardware DMA endpoint, transaction lifecycle, sequence/session state and BIOS service dispatch remain pending. This milestone alone does not claim DMA transport.


## ABI 1.0 validator branch-range follow-up

- CI run `42307162663` still failed at five ATM validator relative branches targeting the shared BAD_MAGIC/BAD_VERSION exits. The earlier correction did not cover those destinations.
- Converted those remaining branches to absolute `JP`; validation semantics are unchanged. Build verification is pending on this commit. Do not treat either prior failed run as BUILD PASS.


## ABI 1.0 DMA endpoint routines

- Added ATM frame sender and NeoGS DMA receive endpoint routines. NeoGS DMA destination is reserved physical page 42h / 108000h; WIN3 maps page 42h only after DMA has been disabled and acknowledged.
- NeoGS receiver is currently an exported callable routine, not yet wired into a resident command dispatcher. ATM DMA-window mapping and physical hardware tests remain outstanding.
- CI verification is pending for this revision. No hardware transfer result is claimed.


## ABI 1.0 — callable NeoGS receive dispatcher linked into core image

- Added `p126_ngs_ipc_dispatch_once`: polls ZXSTAT/CBIT, reads ZXCMD, dispatches E0h to the ATM→NeoGS DMA receiver, and acknowledges unsupported command IDs with `NO_OPERATION`.
- Corrected the receive endpoint return contract: after validation it restores HL=C000h and BC=exact frame size; previously the validator clobbered these registers.
- Corrected the NeoGS version error to use shared ABI status `P126_STATUS_BAD_VERSION`.
- Linked `neogs_sub/p126_ipc.asm` into the assembled `X86CORE.C` image after CPU state and ALU. The standalone IPC audit binary/listing/map remains available.
- **Not implemented:** no resident firmware startup/main loop currently calls `p126_ngs_ipc_dispatch_once`; final WIN0-WIN2 placement, firmware load/entry, and active polling loop remain open. This commit provides a callable dispatcher in the packaged core, not a running resident endpoint.
- **Verification target:** BUILD PASS must confirm the enlarged core and TR-DOS packaging. Hardware tests must exercise E0h READY, DMA payload, FFh completion, CRC acceptance/rejection, timeout cleanup, and WIN3 page mapping. No hardware PASS is claimed.


## Resident startup implementation v0.1.0

- Added GS105a stage-0 source `neogs_sub/p126_bootstrap.asm`, assembled at 4000h and emitted as a bounded `P126BOOT.C` TR-DOS file (maximum one 256-byte sector).
- Added ATM loader `atm_host/p126_neogs_loader.asm`. It locates the exact 8.3 files in the preloaded directory, reads TR-DOS sectors through C=5/B=1, resets/probes the stock GS105a ROM, loads stage-0 with #14, enters it with #13, streams the resident core and requires A2h before reporting success.
- Added resident entry/vector and main polling loop to X86CORE. It establishes WIN0/page00, WIN1/page03, stack 7FFEh, initializes WIN2/WIN3, runs the CRC16 self-test, sends A2h, then continuously polls the ABI 1.0 dispatcher.
- Added P126BOOT.C to the TR-DOS image and build validation. ATM performs startup file reads before video initialization, preserving the established TR-DOS paging order.
- DBIT/GSDAT is explicitly confined to stock-ROM bootstrap; after A2h, application payloads are DMA-only.
- **Not claimed:** no hardware verification yet for GSCTR reset timing, ROM #14/#13 sequence, paging, A2h handshake, DMA timing or frame integrity. The resident loop currently validates incoming frames and logs success/rejection; service dispatch and reverse DMA remain future work.


### Verification — resident startup build

- **BUILD PASS:** GitHub Actions run [42309240393](https://github.com/JTCyborg/Project126/actions/runs/42309240393), source commit `2375b849bd684087b9027262c277b097e46f408e`.
- SjASMPlus 1.23.1: resident/core image 2,356 bytes; ATM IPC 519 bytes; standalone NeoGS IPC 414 bytes; stage-0 bootstrap 175 bytes. All assembly units completed with 0 errors and 0 warnings.
- TR-DOS image: 655,360 bytes. `proj126.C` 17,517 bytes / 69 sectors; `X86CORE.C` 2,356 bytes / 10 sectors; `P126BOOT.C` 175 bytes / 1 sector; each BIOS image 8,192 bytes / 32 sectors. The disk assembly retains one pre-existing generated-path backslash warning.
- **BUILD PASS only.** No emulator or hardware boot/DMA test has been run.


## Automatic first-frame DMA smoke test

After resident startup and ATM video initialization, the host now builds an 18-byte ABI 1.0 diagnostics request (sequence 0001h, empty payload), calculates CRC-16/CCITT-FALSE with the production ATM routine and sends it through `p126_ipc_dma_send_frame`. This exercises E0h, READY/CBIT, the complete 18-byte DMA write, FFh and completion acknowledgement. The NeoGS resident independently validates the frame and logs either `DMA FRAME VALID` or `DMA FRAME REJECTED`.

The ATM log `DMA SMOKE FRAME SENT` means the transport handshake completed; it is not by itself proof of receiver CRC acceptance. Compare it with the independent NeoGS #EF diagnostic. This is a target-side smoke test, not a build-time test.


## NeoGS startup failure-stage diagnostics (2026-11-07)

- The target log confirms TR-DOS directory access and ATM UI continue, but `p126_neogs_startup` returns carry before resident-ready acknowledgement. No DMA smoke frame is attempted in this state.
- Added loader stage tracking and explicit `[BOOT] NGS FAIL STAGE=x`: 1 bootstrap file locate/read; 2 bootstrap metadata; 3 NeoGS reset/RAM probe; 4 ROM #14 upload; 5 resident file locate/read; 6 resident length validation; 7 ROM #13/A1h handshake; 8 resident length/A3h handshake; 9 resident stream/TR-DOS sector reads; 0 resident A2h/ready.
- The existing generic failure message and startup order are retained. This change diagnoses rather than presumes the failing operation.
- **Verification:** pending CI. No hardware fix or ROM/DMA runtime PASS is claimed. The next target log should include the stage character.


## GS105a stage-3 cold-start recovery (2026-11-07)

- Updated `atm_host/p126_neogs_loader.asm` to use GS105a ROM command `#F4` for cold restart, extended CBIT polling and the `#20` RAM-size probe.
- Added one cold-restart/probe retry for the stale-DMA-end-marker case documented by the working Project125 driver.
- Added a `#0400` DBIT turnaround delay after each received ROM byte.
- Preserved Project126's 4 MiB RAM requirement (`RAM size high byte >= #40`); Project125's 2 MiB threshold is not used.
- Runtime outcome remains **NOT VERIFIED** until the updated TR-DOS image is run on the target ATM. Required next evidence: stage 3 clears and the log reaches stage 4 or later.


## Stage-3 diagnostic subdivision (2026-11-07)

- Replaced the single stage-3 marker with operation-level markers A-H, preserving the existing failure reporting mechanism.
- A=initial #F4/CBIT; B=RAM probe entry; C=#20/CBIT; D/E/F=RAM-size bytes 0/1/2; G=4 MiB threshold validation; H=retry #F4.
- The next target run must report the letter after `NGS FAIL STAGE=`; this identifies the last operation entered, not a claim that the operation completed.
- No hardware runtime result is inferred from this instrumentation.


## GS105a #20 raw RAM-size diagnostics (2026-11-07)

- Added ATM-side HEX output of all three bytes returned by the stock ROM's `#20` RAM-size command: `[NGS ROM] RAM24=HH:MM:LL`. The message is written directly by ATM to its own #EF channel and is emitted before the 4 MiB threshold check.
- Kept the Project126 minimum at 4 MiB; no threshold relaxation or inferred RAM-size correction was made.
- At this point the stock GS105a ROM, not Project126 firmware, owns the NeoGS CPU. Therefore a Project126 `[NGS]` message cannot be produced during this exchange. NeoGS-side diagnostics are independent and begin only after Project126 bootstrap is uploaded and entered.
- **Verification:** source change pending CI and target run. The raw byte values and whether the threshold passes remain unknown until the user tests the new TR-DOS image.


## Архитектурное решение: Project126 не зависит от объёма, сообщаемого штатным ROM

**Решение зафиксировано 2026-11-07; имеет приоритет над предыдущими записями о пороге GS105a #20.**

- Штатное GS105a ROM используется только как временный транспорт первоначальной загрузки: #14 загружает Project126 bootstrap, #13 передаёт ему управление.
- После старта bootstrap отключает штатное ROM через GSCFG0 (#0F), NOROM bit 0. В текущем исходнике neogs_sub/p126_bootstrap.asm это уже выполняется инструкцией or #09 после чтения/маскирования GSCFG0; bit 3 EXPAG также устанавливается.
- ATM loader сейчас ошибочно требует, чтобы ответ ROM #20 имел high byte не меньше #40, и завершает запуск до загрузки собственного bootstrap. Это условие признано устаревшим и должно быть удалено из рабочего загрузочного пути. ROM #20 может оставаться только необязательной диагностикой, не влияющей на решение о запуске.
- После передачи управления собственная прошивка должна выполнить независимое обнаружение/тестирование физической RAM и управлять страницами самостоятельно.
- Целевой диапазон: 4 MiB / 256 страниц по 16 KiB (000000h–3FFFFFh). Действующая карта распределяет страницы 00h–83h, а 84h–FFh помечает резервом. Резерв — свободное распределение, не аппаратное ограничение.
- Необходимо разработать безопасный полный тест всех 256 страниц с проверкой записи/чтения и целостности, исключив повреждение кода, стека и активных DMA/IPC областей.
- ROM-ответ 3F:40:00 — только наблюдение старого ROM (4,145,152 байта); он не доказывает, что физически отсутствуют три верхние страницы. Версия ROM не является входным условием Project126.
- **Статус реализации:** архитектурное решение принято; загрузчик ATM ещё содержит старую проверку и требует изменения. Наличие NOROM в bootstrap подтверждено исходным кодом, но фактическое отключение ROM и полный тест 4 MiB на оборудовании пока не подтверждены. BUILD/HARDWARE PASS не заявляются.


## Independent NeoGS debug stream; ROM RAM-size probe removed from startup gate (2026-11-07)

- Diagnosis: the user's log stopped at stage G, the ATM-side GS105a #20 4 MiB threshold check. Project126 bootstrap had not been entered, so no Project126-originated NeoGS #EF message was possible. The existing resident image already contains direct NeoGS #EF messages (`P126 RESIDENT`, `ABI CRC16 PASS`, DMA frame valid/rejected), but those occur only after successful stage-0 and resident streaming.
- ATM loader now retains GS105a cold restart #F4 but skips #20 entirely and no longer gates Project126 startup on stock-ROM RAM reporting.
- `neogs_sub/p126_bootstrap.asm` now emits `[NGS] BOOTSTRAP ENTER` directly to NeoGS #EF and `[NGS] NOROM ENABLED` after writing GSCFG0 with NOROM/EXPAG bits. ATM does not synthesize these messages.
- Expected NeoGS diagnostics after target run: BOOTSTRAP ENTER -> NOROM ENABLED -> P126 RESIDENT v0.1.0 -> ABI CRC16 PASS. These are separate from the ATM #EF stream.
- **Status:** source changes committed; CI/build and one-sector bootstrap size verification pending; target hardware verification pending. The actual 4 MiB page test is not implemented by this diagnostic change.


### Follow-up: stage-7 failure and bootstrap stack initialization

- The current ATM loader sets startup stage `'7'` immediately before sending the low address argument and GS105a `#13` jump command for stage-0 at `4000h`; it then waits for bootstrap `A1h`. `NGS FAIL STAGE=7` therefore localizes the failure to the jump/initial bootstrap-ready handshake, not to the removed stock-ROM #20 RAM-size gate.
- Inspection found the newly added bootstrap logger was called before Project126 established its own stack. The bootstrap now initializes `SP=#FFFE` immediately after `DI`, before any `CALL`/`PUSH`; the old later initialization was removed.
- This source correction is committed, but no assembly build or hardware pass is claimed yet. On the next target run, `[NGS] BOOTSTRAP ENTER` is the decisive marker for successful execution of the first Project126 bootstrap instructions.

- Comparison against Project125 identified a concrete transport bug in Project126: `p126_neogs_send_argument` did not preserve A across `p126_neogs_wait_dbit_clear`, which overwrites A with GSSTAT. Project125's corresponding `gs_boot_write_command_argument` stores the argument before the wait and restores it before `OUT GSDAT`. Project126 now follows that proven sequence, fixing the first argument byte for both `#14` RECEIVE BLOCK and `#13` JUMP. Build/hardware confirmation is pending.

- Project126 bootstrap startup now follows Project125's validated ordering: temporary stack at `#3FFF`, direct entry marker, ZX DMA disable, settle delay, NOROM/EXPAG and window mapping, then `SP=#FFFE` after WIN3 is selected. This complements the command-argument preservation fix. Assembly and physical-board verification for these latest commits are pending.


## Project125 loader parity — 256-byte stage-0 boundary (2026-11-07)

- The target reported `NGS FAIL STAGE=2`. In the active Project126 loader, stage 2 is the P126BOOT.C byte-length validation immediately after the file is opened; it occurs before GS105a cold restart, ROM #14 upload, or ROM #13 jump.
- GitHub Actions run [42314399945](https://github.com/JTCyborg/Project126/actions/runs/42314399945) completed BUILD PASS and logged `P126_GS105A_BOOTSTRAP bytes=256` and `P126BOOT.C: 256 bytes, 1 sectors`. The build script allowed 1..256 bytes, but the loader's stage-2 check required the high length byte to be zero, thereby rejecting the valid exact length 0100h.
- Corrected stage-2 validation to accept lengths 1..255 and exactly 256, while rejecting zero and values above 256. The existing #14 header already encodes a 256-byte block as the 16-bit negative length FF00h and streams exactly 256 bytes from the first TR-DOS sector.
- This is a direct correction of the observed stage-2 failure. It does not claim that #14, #13, bootstrap entry, resident transfer, BIOS loading, or hardware execution have passed; those are later stages and require a new target log.
- Reference behavior inspected in Project125: `zx_main/neogs_driver.asm` uses the same 256-byte #C000 sector buffer and encodes #14 length as a 16-bit negative value before issuing RECEIVE BLOCK. Project125 also supports repeated sector-sized chunks for larger loader files; Project126 currently intentionally constrains its stage-0 image to one 256-byte block.


## DMA smoke-test stage diagnostics and receiver acknowledgement fix (2026-11-07)

- ATM sender records stage 1 (local frame validator), 2 (frame/aperture size), 3 (E0 command and READY wait), 4 (DMA payload copy), or 5 (FF end marker and final completion wait). On successful return the stage resets to zero. ATM prints [BOOT] DMA FAIL STAGE=n on its own #EF stream when the smoke test fails.
- NeoGS now logs E0 command reception, DMA armed/READY, and FF/end detection directly through the resident logger on NeoGS's independent #EF port. The resident main loop retains its existing DMA FRAME VALID and DMA FRAME REJECTED outcome messages.
- Fixed the receiver lifecycle against ABI 1.0 section 3.1: CBIT is no longer cleared immediately when FFh is detected. DMA is stopped, page 42h is mapped, frame length and CRC are validated, and only then is CBIT cleared. Malformed-length and validation-error paths also clear CBIT after recording the failure; timeout still disables DMA before releasing the host.
- Verification status: source-level change only until the corresponding GitHub Actions build completes. Hardware READY/payload/FF/CRC exchange remains unverified. The next target log must correlate both independent #EF streams; no DMA PASS is inferred from ATM alone.


## NeoGS IPC standalone build dependency correction (2026-11-07)

- Build log exposed that `p126_ipc.asm` is assembled independently as `NEOGS_IPC` as well as included by the resident core. Calls from this shared source to `p126_ngs_resident_log` failed in the standalone assembly because that symbol belongs to the other assembly unit.
- Replaced those references with a self-contained `p126_ngs_ipc_log` routine inside the IPC module. It writes directly to NeoGS's independent `#EF` output and preserves AF/BC, so the same source assembles in both contexts.
- The fix addresses the exact undefined symbol errors reported by the local SjASMPlus build. Full build/CI confirmation remains pending.


## ATM frame-validator CRC pointer correction (2026-11-07)

- Latest hardware evidence: resident startup, ABI CRC self-test, ATM video/RTC/console/catalog all complete; the DMA smoke test fails at `DMA FAIL STAGE=1`.
- Stage 1 is the ATM-local call to `p126_ipc_validate_frame`, before the E0h command or DMA handshake. The NeoGS DMA receiver has not yet been exercised by this attempt.
- Found and corrected a pointer-clobber defect in the ATM CRC validator: an `EX DE,HL` moved the frame pointer out of DE, then `LD HL,#FFFF` overwrote it. The CRC loop consequently read from address 0000h. DE now remains the frame pointer throughout header CRC processing.
- **Verification:** source correction committed; local SjASMPlus/build and target rerun are still required. Do not claim DMA hardware PASS. If stage 1 clears, the next diagnostic stage is 2 (size), then 3 (E0h/READY), 4 (copy), and 5 (FF/completion).


## DMA stage-1 validator error reporting (2026-11-07)

- After the previous CRC pointer correction, the target still reports `DMA FAIL STAGE=1`. This proves only that local ATM validation is failing; no E0h or DMA transfer has been attempted.
- Added capture of the ATM validator's A/status return and a hexadecimal ATM #EF line `[BOOT] DMA VALIDATOR ERROR=xx` after the stage report. This distinguishes BAD_MAGIC, BAD_VERSION, BAD_FRAME and CRC_ERROR without attributing the error to NeoGS.
- **Verification:** diagnostic instrumentation committed; assembly and hardware rerun are pending. The next log must include the validator status before the underlying rejection can be corrected conclusively.


## DMA/IPC end-to-end trace instrumentation (2026-11-07)

- Added ATM-local #EF markers around DMA sender entry, local frame validation, E0 issue/acknowledgement, DMA-window copy, FF issue, and final acknowledgement. E0 and FF timeout paths now emit distinct ATM diagnostics.
- Added independent NeoGS #EF markers around E0 dispatch, DMA register setup/arming, READY/CBIT release, host-end detection, DMA stop, page-42 mapping, frame validation, and timeout/length-error paths. NeoGS frame rejection includes the ABI status byte in hexadecimal.
- The two streams remain physically independent; ATM messages are not forwarded or re-labelled as NeoGS messages.
- Fixed the NeoGS CRC validator's frame-pointer clobber (the same class of defect previously fixed in ATM) and corrected both validators to start payload CRC at frame offset 18 rather than offset 16.
- Logging is at transaction boundaries, not inside polling loops. It still adds latency around DMA copy; timing-sensitive behavior must be checked on target hardware.
- **Verification:** GitHub Actions run [42351776510](https://github.com/JTCyborg/Project126/actions/runs/42351776510), commit `d9b2a391ddaf0bbf4ccd918b34a58cbecc17f40e`, completed successfully. ATM IPC and NeoGS assembly, including the new trace code, passed; TR-DOS image packaging and artifact publication also completed. This is BUILD PASS only. No hardware trace or DMA runtime PASS is claimed.


#
## 2026-11-07 — First executable 8086 instruction core

- Added `neogs_sub/x86_exec.asm` as the Project126 8086 execution module.
- Implemented guest instruction fetch through the production CS:IP → 20-bit physical address → guest-memory backend.
- Added one-instruction execution for `JMP FAR ptr16:16` (EA), near relative JMP (E9), short relative JMP (EB), NOP (90), and HLT (F4).
- The post-install BIOS reset gate now resets the guest to FFFF:0000 and executes the actual first BIOS instruction. It verifies the resulting F000:E05B state instead of manually reading bytes and writing the decoded target into registers.
- PCem/808x.c is the semantic reference; unsupported instructions still stop with carry. This is an initial executable slice, **not a complete 8086 implementation**. ModR/M, general register operations, ALU dispatch, stack, interrupts, strings, and virtual I/O remain to be ported.
- No claim of BIOS POST or VGA initialization is made by this stage.

## 2026-11-07 — локализация ATM CRC_ERROR и сверка с Project125

- **Аппаратный лог пользователя:** ATM выводит `[ATM IPC] FRAME VALIDATION FAILED`, затем `DMA FAIL STAGE=1` и `DMA VALIDATOR ERROR=04`. Это `P126_STATUS_CRC_ERROR`; отказ происходит в локальном ATM валидаторе до команды E0. NeoGS receiver и DMA engine на этом запуске ещё не задействованы.
- **Сверка с Project125:** изучены `PROJECT125_DMA_IPC.md`, `NeoGS/dma_zx_doc.txt`, `NeoGS/ports.inc`, `zx_main/neogs_transport_v2.asm` и `shared/neogs_io.inc`. Для ATM→NeoGS запись Project125 использует host write в DMA aperture `0000h..3FFFh`; NeoGS настраивает DMA module 1, HAD/MAD/LAD и CST bit 7. Dummy read из документа относится к обратному направлению NeoGS→ATM; dummy write перед ATM→NeoGS не требуется. Отдельно учтено предупреждение Project125 о задержке после включения DMA в сценариях, где управление DMA идёт через штатный GS105a ROM. Текущий P126 обмен выполняется уже резидентной прошивкой, поэтому это предупреждение проверяется на аппаратном этапе, а не объявляется причиной текущего CRC отказа.
- **Изменено:** `atm_host/neogs_ipc.asm` — перед сравнением CRC теперь выводятся две независимые величины: CRC, рассчитанный ATM валидатором, и CRC, сохранённый в байтах 16–17 кадра. Это позволит определить, ошибка ли в вычислении или в подготовке/записи кадра.
- **Эталон smoke frame:** первые 16 байт `50313236010001050000010000000000`; CRC-16/CCITT-FALSE должен быть `FF5B`, хранение little-endian — `5B FF`. Это рассчитано независимо и соответствует стандартному алгоритму Project125 bootstrap.
- **Следующий диагностический критерий:** сравнить в новом логе `CRC CALCULATED=FFFF`-формат и `FRAME CRC=FFFF`-формат. Если отличаются — локализовать вычисление/подготовку; если оба `FF5B`, но валидатор всё равно возвращает 04 — проверять саму последовательность сравнения/адресацию.
- **Проверка диагностического патча:** GitHub Actions run [42352070894](https://github.com/JTCyborg/Project126/actions/runs/42352070894), commit `6cf8fd152fb492d2c5f6c7979386cb4bde643354`, completed with BUILD PASS (ATM/NeoGS assembly and TR-DOS image packaging). Аппаратное подтверждение значений CRC ожидается от следующего запуска пользователя.
- **Статус:** исходная аппаратная ошибка подтверждена логом; вычисленный и сохранённый CRC ещё требуется сопоставить на реальном ATM. DMA аппаратный PASS не заявляется.


## 2026-11-07 — ATM CRC accumulator clobber fixed

Latest hardware trace:
```text
[ATM IPC] CRC CALCULATED=7349 FRAME CRC=FF5B
[ATM IPC] FRAME VALIDATION FAILED
[BOOT] DMA VALIDATOR ERROR=04
```

Diagnosis:
- Stored frame CRC `FF5B` matches the independently verified CRC-16/CCITT-FALSE value for the 16-byte test header.
- The ATM validator had a register-lifetime bug, not a CRC polynomial/byte-order bug. After calculating the header CRC in `HL`, it restored the saved payload pointer with `pop hl`, overwriting the accumulator with the address `frame+18`. The reported `7349` is that pointer value.
- Fixed `atm_host/neogs_ipc.asm` to restore the pointer directly with `pop ix`. The CRC accumulator in `HL` now survives into the payload loop, including the zero-length payload smoke test.
- No DMA registers, handshake order, ABI fields, or CRC algorithm were changed.

Verification boundary: source correction is committed. CI assembly/package result and target hardware rerun are tracked separately; no DMA hardware PASS is claimed until ATM reports `FRAME VALID` and NeoGS independently validates the received frame.


- **CI verification:** GitHub Actions run [42352359828](https://github.com/JTCyborg/Project126/actions/runs/42352359828), source commit `7601e8e58c8c82a0bce4697de3cdcb824f743685`, completed with SUCCESS. The ATM/NeoGS assembly and TR-DOS image packaging step passed. This confirms build correctness only; hardware rerun is still required.


### 2026-11-07 — DMA проходит, NeoGS отклоняет magic

- Новый аппаратный лог подтверждает, что локальный ATM validator прошёл (CRC CALCULATED=FF5B FRAME CRC=FF5B, FRAME VALID), NeoGS принял E0, включил DMA, ATM выполнил копирование и FF, NeoGS остановил DMA и освободил CBIT.
- NeoGS затем вернул DMA FRAME REJECTED STATUS=01 (BAD_MAGIC). Значит, ошибка находится после DMA-передачи — в содержимом, видимом через WIN3/page 42, либо в отображении/адресации staging buffer. CRC/handshake больше не являются текущим препятствием.
- Добавлена временная диагностика в neogs_sub/p126_ipc.asm: сразу после остановки DMA и отображения страницы 42 выводятся первые четыре байта, реально прочитанные из C000h..C003h как [NGS] DMA RX FIRST4=...
- По следующему логу: 50313236 означает, что magic P126 присутствует; тогда надо проверять путь/содержимое при валидации. 00000000, FFFFFFFF или другие значения покажут, что DMA-буфер не содержит ожидаемые первые байты, и позволят локализовать физический адрес/направление/окно.
- Пока не менялись DMA-регистры, адрес 108000h, ABI или handshake: сначала снимаем фактические байты, не подменяя диагностику предположением.
- Проверка: аппаратный лог пользователя подтверждает завершение транзакции, но frame validation пока FAIL. Временная диагностическая сборка должна пройти CI до следующего аппаратного теста.


## 2026-11-07 — DMA data-plane diagnostics

Аппаратный лог подтверждает: ATM local frame validation PASS (CRC=FF5B), E0/READY handshake PASS, ATM aperture copy выполнен, NeoGS получил FF/end и остановил DMA. Однако NeoGS читает 00000000 из начала page 42 через WIN3 и возвращает BAD_MAGIC. Это не является DMA payload PASS: передача управления работает, содержимое staging RAM пока не подтверждено.

В neogs_sub/p126_ipc.asm добавлены:
- чтение и вывод HAD/MAD/LAD после остановки DMA (только наблюдение; семантика readback требует аппаратного подтверждения);
- обратимый WIN3 write/read тест в C100h, вне 18-байтового smoke frame, с обязательным восстановлением исходного байта;
- полный дамп фиксированных 16 байт заголовка из C000h.

Не изменялись адрес 108000h, DMA module 1, направление host→NeoGS, CBIT/FF handshake и ABI. Следующий шаг — сопоставить DMA address readback, результат WIN3 RW test и header dump. BUILD и HARDWARE статусы обновляются отдельно после CI и нового аппаратного лога.


## DMA page-42 pre-map alignment (2026-11-07)

- Hardware result: ATM CRC and E0/READY/FF control path pass; NeoGS post-stop address readback is 108012 after target 108000 for an 18-byte frame; WIN3 RAM probe passes; all 16 received header bytes are zero.
- Interpretation: 18 DMA aperture accesses appear to have advanced the destination address, but payload storage in page 42 is not proven. WIN3 mapping and writeability are independently demonstrated.
- Project125 reference neogs_sub/main.asm maps the destination page into its CPU window before arming ZX DMA and keeps that mapping active through the transaction. Project126 had selected page 42 only after DMA stop.
- Updated neogs_sub/p126_ipc.asm to map page 42 into WIN3 before DMA register setup and leave it selected through receive-buffer inspection. Resident code/stack remain in WIN0-WIN2. No DMA address, module, host aperture, frame ABI or handshake change.
- CI BUILD PASS for this source update and the next target run are tracked separately. The expected first new marker is [NGS] DMA PAGE 42 PRE-MAPPED; the decisive payload check remains the header dump.


## 2026-11-07 — reverse DMA diagnostic added

- Added the ABI 1.0 E1h (NGS_FRAME) reverse-direction smoke exchange. NeoGS generates a 274-byte response in page 42h at physical 108000h: an 18-byte response header plus a deterministic 256-byte 00h..FFh payload and a computed CRC-16/CCITT-FALSE.
- ATM waits for E1h readiness, discards the first DMA aperture read as required specifically for NeoGS->ATM, reads the complete frame, sends FFh, validates the frame CRC, and compares every payload byte.
- The test is invoked after the existing E0h host->NeoGS smoke transaction. It does not replace or alter E0h, DMA target address, module selection, or ABI 1.0.
- Hardware prerequisite: ATM ROM must remain mapped at 0000h..3FFFh during reverse DMA reads. The NeoGS hardware documentation distinguishes this from host->NeoGS writes, which work with RAM mapped.
- Verification boundary: source and packaging build must pass CI; target hardware must separately report [ATM IPC] DMA RX PATTERN PASS. No reverse-DMA hardware PASS is claimed by this source change.


## 2026-11-07 — Project125 DMA parity correction (hardware diagnostic)

- Rechecked the actual Project125 routines, not only the shared constants: `p125_dma_reverse_selftest` in `zx_main/bios_transfer.asm`, `command_load_x86` in `neogs_sub/main.asm`, and `NeoGS/dma_zx_doc.txt`.
- Project125's known-good physical addresses are 00D000h for host→NeoGS writes and 00E000h for NeoGS→host reads, both in page 03h. The reverse host reader performs DI, one discarded read from ROM aperture 0000h, then copies the valid bytes. Forward writes do not perform a dummy write.
- Project126's previous page-42 test had a misleading CPU-only WIN3 read/write probe. The observed address increment (108000h→108012h) proved DMA address-register progression only; it did not prove payload delivery. The all-zero received header and reverse CRC failure remain the baseline hardware failures.
- The fixed smoke endpoints now use the Project125 physical test addresses and explicitly map page 03h into WIN3. The ATM reverse reader now executes DI before the dummy read. The false-positive WIN3 probe has been removed; validation is based on complete frame CRC and the 00..FF payload pattern.
- Diagnostic reservations are D000h..D111h and E000h..E111h in page 03h; the resident stack at 7FFEh is separate. The host→NeoGS diagnostic receiver rejects a frame larger than 3000h to keep the transaction inside page 03h. These are diagnostic-only carve-outs.
- Production staging remains allocated at page 42h (108000h) in the physical map, but page 42h is **not** declared hardware-validated by this commit. After the parity test passes, page-42 DMA must be tested separately before switching the production endpoints back.
- **Verification boundary:** source and documentation change only. A fresh CI build and a new target hardware log are required. No DMA hardware PASS is claimed.


## 2026-11-07 — Project125 DMA implementation ported into Project126

- NeoGS now selects physical page 03h in PG1 through port `#21`, matching the Project125 DMA window model; WIN3/port `#23` is not used for these diagnostic buffers.
- Physical D000h and E000h are accessed by NeoGS at WIN1 logical 5000h and 6000h respectively. DMA engine register addresses remain D000h/E000h.
- Reverse response is contiguous in WIN1 and its header declares the generated 256-byte payload (`0100h`), correcting the previous erroneous `1260h` length.
- ATM DMA aperture operations follow Project125: no dummy write for forward transfer; DI plus one discarded read before reverse data collection.
- Build and hardware verification pending. No hardware DMA PASS is claimed.


## 2026-11-07 — DMA frame-validator and reverse-response corrections

- Hardware trace after the Project125 DMA port: ATM→NeoGS transfers the expected ABI header and NeoGS rejects it with status 04h (CRC_ERROR). NeoGS→ATM is rejected by the ATM validator with status 03h (BAD_FRAME); the previous ATM log label incorrectly called every validation failure a CRC failure.
- Fixed the NeoGS validator's payload-pointer restore so it no longer overwrites the live CRC accumulator in HL.
- Fixed the reverse diagnostic response header: sequence is 0000h and payload length is 0100h at offsets 12–13.
- Confirmed the reverse CRC loop's `B=0 / DJNZ` is the intended 256-iteration loop; it was not changed.
- Renamed the ATM diagnostic to FRAME VALIDATION FAILED with status code, avoiding the false CRC-only diagnosis.
- DMA registers, page mapping, handshake, and Project125 transport sequence are unchanged.
- Verification: source correction only; CI/build and a new hardware run are pending. No hardware DMA PASS is claimed.


## 2026-11-07 — Bidirectional DMA smoke test: HARDWARE PASS

User-provided target log confirms both diagnostic DMA directions end-to-end on physical ATM/NeoGS hardware.

- **ATM → NeoGS:** ATM frame CRC FF5B matches; local validator reports FRAME VALID; E0/READY handshake succeeds; payload copy and FF/end complete; NeoGS stops DMA, reads the expected P126 ABI 1.0 header and reports DMA FRAME VALID. Address readback 00D012 is consistent with the 18-byte header transfer.
- **NeoGS → ATM:** reverse DMA completes; ATM reports CRC calculated/stored D867, DMA RX FRAME CRC VALID and DMA RX PATTERN PASS for the complete deterministic 00h..FFh payload.
- **HARDWARE PASS scope:** bidirectional DMA smoke transport, end-of-transfer handshake, frame format validation, CRC-16/CCITT-FALSE and reverse payload byte comparison.
- **Configuration proven:** Project125 parity diagnostic path, DMA module 1, page 03h; forward destination D000h and reverse source E000h; PG1/WIN1 mapping; no dummy write on forward transfer and one discarded read on reverse transfer.
- **Not proven:** production page 42h / physical 108000h staging, payloads beyond the tested smoke-frame sizes, multi-frame fragmentation/reassembly, sustained streaming, application service dispatch, VGA frame delivery, BIOS transfer or x86 execution. Do not promote the page-03 diagnostic carve-outs to production allocation.
- The earlier failure entries above are historical and remain as debugging chronology; this section supersedes their pending/failed verification status for the two smoke directions only.
- **Next:** retain the now-proven Project125 DMA path unchanged. Validate production page 42h separately, then run full-frame integrity and fragmentation/stress tests. Every fragment must be validated by its complete header, declared length and CRC; byte-count-only checks are insufficient.


## 2026-11-07 — Production DMA page 42 validation implemented (hardware pending)

- Initial page-42 implementation selected WIN3 incorrectly through port #23 with raw page value 42h. This was superseded by the MPAGEX correction recorded below. The DMA destination registers remain module 1, HAD=10h, MAD=80h, LAD=00h (physical 108000h); received data is validated from logical C000h and frame size is bounded to 16 KiB.
- NeoGS reverse test now constructs the response in the same page-42 WIN3 mapping and DMA-reads from physical 108000h. The ATM reverse sequence is unchanged: DI, one discarded ROM-aperture read, exact frame copy, FF/end, full CRC and payload pattern validation.
- ATM forward test frame increased from a header-only request to 274 bytes: 18-byte ABI header plus deterministic payload 00h..FFh. ATM computes CRC across header[0..15] and all 256 payload bytes; NeoGS validates the complete frame after DMA stop.
- Expected DMA progression in both directions is 108000h→108112h. Independent NeoGS log markers identify page-42 mapping and reverse address readback.
- The known-good page-03 Project125-parity transport is not altered in its hardware-tested implementation history. The initial page-42 test used the wrong WIN3 selector; see the later root-cause section for the corrected MPAGEX port/encoding.
- **BUILD PASS:** GitHub Actions run [42356251101](https://github.com/JTCyborg/Project126/actions/runs/42356251101), built commit `a91fc6a86873e4a5208067b55782cb0085ae930e` (includes the page-42 receiver and 274-byte ATM test frame). SjASMPlus assembled NeoGS, ATM IPC and standalone NeoGS IPC with 0 errors/0 warnings; NeoGS IPC image is 1408 bytes, combined NeoGS image 3350 bytes, ATM IPC image 1777 bytes; TR-DOS image packaged successfully. One pre-existing generated-path backslash warning remains in the disk assembler.
- **HARDWARE PENDING:** page-42 target verification is not yet claimed. Do not mark page 42h as hardware PASS until the new ATM/NeoGS target log confirms full CRC and payload checks in both directions.
- **Next after page-42 PASS:** maximum-size single-frame test, then ABI fragmentation/reassembly with per-fragment CRC/sequence/metadata validation, followed by sustained multi-frame streaming stress and error/recovery tests.


### Latest page-42 source build confirmation

- **BUILD PASS:** final self-contained source commit `cd37fcb1e720b4455a815f9b65b34eaf62c6f4b3`; GitHub Actions run [42356391039](https://github.com/JTCyborg/Project126/actions/runs/42356391039) completed successfully. NeoGS main image 3350 bytes, ATM IPC 1777 bytes, standalone NeoGS IPC 1408 bytes; all assembly units report 0 errors and 0 warnings. TR-DOS image packaged at 655360 bytes. The disk assembly emits one pre-existing generated-path backslash warning.
- Build artifact: `project126-trdos-disk-and-build` is attached to the workflow run. This confirms source assembly and disk packaging only; production page-42 physical DMA remains **HARDWARE PENDING**.


## 2026-11-07 — WIN3 page-selector root cause fixed

- **Target evidence:** the 09:44 page-42 run completed ATM→NeoGS DMA at 108000h→108112h but NeoGS read an all-zero header at C000h. The reverse test reported CRC 7C1C, identical to the ATM request frame. The expected CRC for the NeoGS RESPONSE header plus payload 00h..FFh is D867. Thus the earlier reverse PATTERN PASS was a false positive for page-42 response construction: the test read back the previous request data rather than the newly constructed response.
- **Root cause:** Project125 selects WIN3 (C000h–FFFFh) through MPAGEX port #10 and encodes the physical page selector with `RRCA`. Project126 incorrectly used PG3 port #23 and wrote raw page 42h. This made the CPU WIN3 view differ from the physical page targeted by DMA.
- **Source correction:** `neogs_sub/p126_ipc.asm` now selects page 42h using `LD A,42h / RRCA / OUT (#10),A` for both receive validation and reverse-response construction. `shared/p126_neogs_memory_map.inc` now defines/asserts the WIN3 selector port as #10. Both page-selection paths in `neogs_sub/x86_cpu_state.asm` now encode computed physical page numbers with RRCA before MPAGEX output; this corrects the same underlying defect in the general x86 RAM/VRAM/BIOS backing access path. DMA module, physical address 108000h, ATM aperture 0000h, dummy-read rule and E0/FF handshake are unchanged.
- **Selector example:** physical page 42h → MPAGEX selector byte 21h. Resident startup's existing `OUT (#10),01h` for WIN3/page 02h is consistent with this encoding.
- **BUILD PASS:** GitHub Actions run [42357023766](https://github.com/JTCyborg/Project126/actions/runs/42357023766), built code commit `a2fa006fdd8ce5023b7949f92393934cbbd224c5`; assemble-and-package completed successfully and published `project126-trdos-disk-and-build`. Subsequent commits only update documentation.
- **HARDWARE PENDING:** production page-42 PASS requires a new target log showing forward header `50313236` and `DMA FRAME VALID`, plus reverse response CRC D867 and full payload `00h..FFh` validation. The earlier reverse CRC 7C1C must not be treated as proof of the response path.



## 2026-11-07 — Production page 42h bidirectional DMA: HARDWARE PASS

User-provided physical target log (09:52:27) validates the corrected MPAGEX page selector on actual ATM/NeoGS hardware.

- ATM → NeoGS: request CRC 7C1C matches; E0/READY handshake succeeds; DMA address advances 108000h→108112h; NeoGS reads header 50313236010001050000010000010000 at C000h and reports DMA FRAME VALID.
- NeoGS → ATM: DMA ends with readback 108113h (one discarded ROM-aperture read plus 274 transferred bytes); ATM CRC D867 matches the frame CRC; DMA RX FRAME CRC VALID and DMA RX PATTERN PASS confirm the reverse frame and payload 00h..FFh.
- HARDWARE PASS scope: production physical page 42h (108000h) selected into WIN3 via MPAGEX #10 / RRCA; both DMA directions; frame validation; CRC-16/CCITT-FALSE; deterministic 256-byte payload integrity.
- This result supersedes earlier page-42 FAIL/PENDING entries and the misleading reverse result with CRC 7C1C. Keep those earlier entries as chronology, but treat this section as the final status for the 274-byte production-page smoke test.
- Not yet proven: maximum-size frame, fragmentation/reassembly, sustained multi-frame streaming, error/recovery, application service dispatch, VGA frame delivery, BIOS transfer and full x86 execution.
- Next: retain the now hardware-proven page-42 DMA mapping and protocol unchanged; extend validation to maximum-size frames, then fragment metadata/sequence/CRC integrity and sustained streaming stress.


## 2026-11-07 — maximum-size DMA frame test added

- Added the next test after the physical 274-byte production-page-42 bidirectional HARDWARE PASS: one full 16 KiB ABI 1.0 frame in each DMA direction.
- ATM request and NeoGS response both declare payload length 3FEEh (16366 bytes), sequence 0002h, and carry a repeating 00h..FFh pattern across the complete payload. Both endpoints calculate/validate CRC-16/CCITT-FALSE over the entire frame; ATM also compares every reverse payload byte.
- ATM uses one shared 16 KiB buffer at C000h..FFFFh on RAM page 0, reusing the TR-DOS staging window sequentially for TX and RX. No second 16 KiB buffer is allocated.
- NeoGS validates the forward DMA address readback at 10C000h (108000h + 4000h). Reverse DMA readback is checked at 10C001h (one documented dummy read + 4000h data bytes).
- Existing transport sequence, physical page 42h, MPAGEX #10/RRCA, DMA module 1, host aperture and dummy-read rules are unchanged.
- **IMPLEMENTED / BUILD PENDING / HARDWARE PENDING.** Do not mark the 16 KiB test PASS until CI assembly/package succeeds and the target log confirms both complete frame checks and both exact address readbacks.


## 2026-11-07 — 16 KiB test: ATM BAD_MAGIC diagnostic

- The first hardware attempt stopped at ATM-local frame validation (DMA FAIL STAGE=1, validator status 01 = BAD_MAGIC), before E0 or DMA activation.
- The validator receives C000h as frame pointer. The test buffer was placed at ORG #C000; actual bytes at that address were not yet captured, so a page-selection/overwrite cause is not assumed.
- Added target trace to print the failing frame pointer and four actual bytes at that pointer. Next hardware run is diagnostic; do not claim 16 KiB DMA PASS or change the NeoGS DMA engine until the header bytes are known.


## DMA max-frame test: ATM staging-header initialization

- Latest target log: ATM validator reported `BAD MAGIC PTR=C000 DATA=20444D41` (bytes `20 44 4D 41`) and failed at stage 1, before E0/READY or any DMA register activity.
- Root cause confirmed in source/package layout: `project126_disk.asm` packages the ATM host only through `p126_host_program_end`, constrained to `<= A800h`; the former static header under `ORG C000h` was outside the loaded host file. Runtime code had filled payload bytes but had not initialized the header.
- Commit `b366a37318d89f02f613e848e106db9f3fcf219c` changes the test to initialize all 18 header bytes in C000h at runtime before payload generation and CRC.
- Verification status: source correction committed; assembly/build and hardware retest still pending. No DMA hardware PASS is claimed.


### 2026-11-07 — TX startup preflight correction

- Removed the redundant full-frame CRC calculation from the ATM transmit startup path. The 16 KiB CRC was already generated by the frame builder and is authoritatively checked by NeoGS after DMA reception.
- ATM now performs a bounded structural preflight only (magic/version/request/flags/declared size), then enters the Project125-compatible E0/READY/DI/LDIR/FF sequence.
- Full CRC validation remains enabled for NeoGS forward-frame reception and ATM reverse-frame reception.
- DMA hardware configuration, page-42 mapping, ABI 1.0, and reverse dummy-read sequence are unchanged.
- **IMPLEMENTED / BUILD AND HARDWARE RETEST PENDING.**


## 2026-11-07 — NeoGS resident loader aligned with Project125

- Replaced Project126's hand-parsed TR-DOS directory-entry lookup with the proven Project125 ROM file-open ABI: prepare the 8-character name and extension at #5CDD/#5CE5, call TR-DOS C=#0A, then fetch the full descriptor with C=#08. File length and start track/sector now come from the same system variables used by Project125 (#5CE8, #5CEB, #5CEC).
- Replaced the custom stack-relocating sector reader with the Project125 direct C=5/B=1 sector-read sequence into #C000. Sector/track cursor and remaining-sector count advance only after a successful TR-DOS return. Remaining sectors are derived from the exact file length, not the raw directory-entry offsets.
- Replaced Project126's final-byte/A2 race special case with the Project125 V1 ordering: each data byte completes the DBIT-consumed handshake; only after all declared bytes have been sent does the host wait for the final A2 resident-ready acknowledgement. Buffer refill remains demand-driven at 256-byte boundaries.
- File names remain Project126-specific: P126BOOT and X86CORE. The catalogue UI/preload, GS105a #14 bootstrap transfer, #13 stage-0 entry, A1/A3 exchange, ABI, DMA implementation and resident firmware are unchanged.
- This is a source port of the Project125 TR-DOS/DBIT loader sequence, not a hardware result. CI build is required; physical startup is still pending a fresh target log showing the resident A2 acknowledgement and startup stage 0.


## 2026-11-07 — DMA completion watchdog aligned with Project125

- Hardware log after the 16 KiB test showed the resident announcing DMA READY, then reporting DMA WAIT TIMEOUT before the ATM finished its LDIR and sent FF. ATM subsequently treated the already-cleared CBIT as an FF acknowledgement; the printed TX PASS was therefore false and did not indicate a valid frame.
- Source comparison identified the concrete divergence: Project125 uses `DMA_WAIT_OUTER = 8` with eight independent `#FFFF` polling windows in its DMA receive, reverse-read, video and BIOS transfer paths. Project126 used only one `#FFFF` window in both maximum-frame DMA directions.
- Updated `neogs_sub/p126_ipc.asm` to use the same eight-window completion watchdog for both ATM→NeoGS receive and NeoGS→ATM reverse DMA. DMA register setup, page-42 mapping, frame ABI, dummy-read behavior and E0/E1/FF control sequence are unchanged.
- This is a direct timing/timeout parity correction from Project125. The page-42 destination remains Project126-specific because its resident stack/code allocation differs from Project125's page-03 layout.
- Next target run must show `DMA HOST END DETECTED` (forward) and `DMA RX MAX FRAME HOST END` (reverse), followed by full CRC and payload checks. ATM-side TX completion must not be considered a PASS unless NeoGS reports a valid frame.
- Verification status: source commit recorded; CI and hardware retest pending. No 16 KiB DMA HARDWARE PASS is claimed.


## 2026-11-07 — cursor keyboard matrix correction (supersedes prior mapping)

The target log after commit `1bd610d` showed that the catalogue cursor did not move. Rechecking the standard Spectrum matrix corrected the previous bit-order mistake: row `#EFFE` is `0,9,8,7,6`, with bit 0=0, bit 1=9, bit 2=8, bit 3=7, bit 4=6. Therefore CAPS SHIFT+7 (UP) is bit 3 and CAPS SHIFT+6 (DOWN) is bit 4. The earlier bit-1/bit-0 mapping was incorrect and is superseded.

Updated `p126_catalog_scan_keys` to use bit 3/bit 4. Restored one `[CAT] CURSOR KEY DETECTED` diagnostic per recognized key press (not per polling iteration), before the release wait, so the next target log distinguishes keyboard-scan failure from navigation/redraw failure. No hardware PASS is claimed pending a new target run.

Source commit: `aac9d7e60c391510150016d3b29906a7b2f90e3d`.


## 2026-11-07 — устранено повреждение каталога DMA smoke-тестами

Аппаратный лог подтвердил, что после успешной отрисовки каталога курсорные нажатия распознаются, но первая перерисовка очищает строки. Причина найдена в карте памяти и порядке запуска, а не в клавиатуре или экранном renderer:

- `p126_catalog_read_disk` размещает 2 KiB TR-DOS directory buffer по `#C800..#CFFF`.
- Максимальные DMA smoke-тесты используют staging frame в окне `#C000..#FFFF` (16 KiB) для TX и RX. Это та же физическая RAM page 0, поэтому тесты перезаписывают directory buffer после того, как каталог уже нарисован.
- При следующем нажатии `p126_catalog_draw` читает повреждённые записи и перерисовывает строки пустыми. Это точно объясняет наблюдаемое исчезновение дерева.

Исправление: максимальные DMA smoke-тесты исключены из обычного интерактивного boot path. Их код и отдельная проверка DMA остаются в проекте; тесты запускаются в отдельном диагностическом сценарии, где буфер каталога не нужен. Опрос клавиатуры и renderer не меняются.

Аппаратный лог пользователя от 2026-11-07 подтверждает обе стороны DMA 16 KiB: `DMA MAX TX PASS`, `CRC CALCULATED=C609 FRAME CRC=C609` и `DMA MAX RX PASS`. Это hardware PASS для тестового запуска; после исключения smoke-тестов из normal boot требуется проверить сохранность каталога при перемещении курсора.


## 2026-11-07 — catalogue hardware confirmation and BIOS transfer instrumentation

- Latest target log confirms directory read/count/draw, four recognized cursor presses without catalogue loss, and `[CAT] ENTER CONFIRMED`. This is a hardware PASS for catalogue persistence/navigation and Enter recognition only; it proves the BIOS loader was entered, not that BIOS was read or installed.
- ATM BIOS loader now logs transaction milestones: load entry, file-open success, exact-size validation, sector-read begin/completion, ATM video restoration, and each IMAGE operation before/after the CBIT completion wait. Failure paths report distinct reasons (selection, file type, not found, descriptor, size, sector read, IPC/DMA).
- NeoGS IMAGE handlers now emit explicit rejection markers for BEGIN, FRAGMENT and FINISH validation failures. ATM labels the CBIT event as handler completion rather than ACK, because the current ABI transport wait observes CBIT release but does not receive the handler's carry/status result.
- ATM's final catalogue message now says the IMAGE sequence was sent and directs verification to the NeoGS installation result; it no longer claims successful SYSBIOS installation based only on CBIT completion.
- **HARDWARE PENDING:** selected BIOS file read, all three IMAGE operations, and installation/readback in physical page 10h. Required positive marker: `[NGS] SYSBIOS IMAGE INSTALLED AT PAGE 10`. Rejection markers distinguish handler validation failures.
- **BUILD PENDING:** the diagnostic source changes require a fresh CI assembly/package run. No BIOS transfer/install PASS is claimed.


## 2026-11-07 — BIOS loader pre-open trace added

- Target log stopped at `[CAT] BIOS LOAD BEGIN`; therefore the selected-entry lookup, file-type check, TR-DOS mapping transition and both TR-DOS open/descriptor calls were not yet evidenced.
- Compared the Project126 loader against the proven `Project125/zx_main/bios_file_loader.asm`. Preserved the exact TR-DOS filename setup and C=0Ah then C=08h call sequence; no ABI or sector-reader changes were made.
- Added explicit `DI` at loader entry, matching Project125, plus markers after selection resolution/type validation, around TR-DOS mapping, and immediately before/after each #3D13 call.
- These markers are diagnostic boundaries only; they do not assert a root cause. The last visible marker in the next hardware log will isolate the failing stage.
- Source commit: `e9cf9c3638687d5230a8ab50ebea075417013afb`. CI build and hardware retest pending. BIOS read/transfer/install remain **HARDWARE PENDING**.


## 2026-11-07 — BIOS selected-entry pointer fix (build and hardware pending)

- Latest target trace isolated the BIOS loader failure to the file-type check: selection lookup completed, but the loader rejected the entry before changing the TR-DOS map or calling the ROM.
- Root cause was a register-lifetime bug introduced with diagnostics: the selected-entry pointer returned in HL was overwritten by loading the diagnostic message pointer before HL was pushed. The loader consequently inspected the diagnostic string instead of the directory entry.
- Corrected by pushing HL immediately after p126_catalog_find_index succeeds, logging the selection marker, restoring HL, then copying the filename and checking the type byte.
- Catalogue keyboard handling and renderer, TR-DOS ABI/sector reading, DMA and IMAGE protocol are unchanged.
- Expected target evidence: BIOS FILE TYPE C OK, TRDOS MAP SWITCH DONE, then the C=0Ah/C=08h call/return markers.
- CI assembly/package and physical BIOS read/transfer/install verification are pending. Do not claim BIOS hardware PASS yet.


## 2026-11-07 — Preserve DOSEN while restoring TR-DOS mapping (hardware pending)

- Target trace reaches the TR-DOS open ROM call C=0Ah at #3D13 but does not return.
- Project125 performs BIOS disk I/O before ATM video initialization. Project126 performs it afterwards, when p126_atm_video_init has already enabled DOSEN through the #3D2F trampoline and configured automatic TR-DOS ROM selection with #3FF7=#BF.
- The previous p126_bios_enter_trdos_mode reset #EFF7 after DOSEN setup. This contradicted the explicit ordering constraint in p126_screen_console.asm: resetting #EFF7 after shadow-port/DOSEN setup can undo the TR-DOS overlay state.
- Updated the routine to switch only #7FFD to #10 and update #5C3B, leaving #EFF7/DOSEN and #3FF7 untouched.
- Keyboard/catalogue code, TR-DOS ABI, disk-sector reader, DMA, IPC and IMAGE protocol are unchanged.
- Hardware verification pending; require C=0Ah return and subsequent C=08h descriptor markers before declaring this stage successful.


## 2026-11-07 — Selected BIOS filename diagnostic (build/hardware pending)

- Added a timestamped #EF diagnostic line immediately after successful file-type validation: [CAT] BIOS FILE SELECTED: NAME    .C
- The filename is emitted from the same eight-byte #5CDD field that the TR-DOS C=0Ah open routine uses, with the validated C extension appended.
- The logger preserves AF/BC/DE/HL. No catalogue, TR-DOS ABI, disk I/O, DMA, IPC or IMAGE behavior was changed.
- CI and hardware verification pending.


## 2026-11-07 — TR-DOS C=0A boundary trace (hardware pending)

- Selected filename logging is confirmed by the user's hardware trace (BIOS1   .C), but the ROM call at #3D13 still does not return.
- Added a Project125-style, read-only boundary dump immediately before C=#0A: #5C3B, #5CE5, #5D06, live SP, eight bytes at #3D13, and the exact eight-byte name at #5CDD.
- The helper preserves AF/BC/DE/HL and does not change paging, TR-DOS state, DMA or IPC. The C=0A call remains unchanged.
- Awaiting the next hardware log; diagnosis of the ROM mapping is not yet hardware-confirmed.


## 2026-11-07 — Reassert ATM2+ WIN0 TR-DOS ROM selector before BIOS open

- The latest hardware trace confirms the selected file and the C=0Ah input fields: BANKM=#10, extension=#43 ('C'), name length=#09, and filename BIOS1 followed by spaces. The call at #3D13 still does not return.
- Rechecked `docs/Hardware/Описание архитектуры и портов ATM2+.txt`: window 0 has its own memory-manager port `#3FF7`; D7 enables coupling to `#7FFD`, and automatic TR-DOS overlay depends on ROM2 plus the DOSEN-controlled ROM select when execution enters `#3Dxx`. Permanent DOSEN is enabled through the documented `#0177` alias of system port `#FF77` (A9=0).
- Updated `p126_bios_enter_trdos_mode` to reassert `#3FF7=#BF` immediately after restoring `#7FFD=#10` / BANKM. This explicitly restores the WIN0 ROM selector for the subsequent `CALL #3D13` while preserving permanent DOSEN: it does not write `#EFF7` or repeat the `#0177` trampoline.
- This is a narrowly scoped mapping correction derived from the ATM2+ hardware documentation. It does not change the Project125 C=0Ah/C=08h TR-DOS ABI, filename fields, stack setup, disk reader, catalogue, DMA, IPC or IMAGE transfer.
- **BUILD/HARDWARE STATUS:** CI assembly/package and a new physical target log are required. The correction is not yet hardware-proven. Required next evidence: `TRDOS OPEN C=0A RETURN`; if it still stops, retain the new log and continue investigating the ROM entry/runtime rather than assuming this selector write fixed it.


## 2026-11-07 — Preserve high-resolution video page selection during TR-DOS access

- The latest target trace still stopped inside the TR-DOS C=0Ah open call. The ATM video console is initialized before BIOS selection and uses the alternate video page pair selected by BANKM D3=1.
- The BIOS loader previously wrote BANKM=#10 on entry to TR-DOS. That enabled ROM2 (D4=1) but also cleared D3, switching the page selection away from the active high-resolution video pages 7/3 while the console and renderer continued to assume those pages.
- Changed p126_bios_enter_trdos_mode to read the current #5C3B value, set only D4 with OR #10, write the result to #7FFD, and update #5C3B. With the current display configuration this preserves BANKM=#18 instead of forcing #10.
- The existing #3FF7=#BF WIN0 automatic TR-DOS selector remains reasserted. #EFF7, the permanent DOSEN setup, the #0177 trampoline, catalogue, keyboard, TR-DOS C=0Ah/C=08h ABI, sector reader, DMA, IPC and IMAGE protocol are unchanged.
- This fixes an unintended video-page switch in the disk-entry path. It does not by itself prove that the ROM call now returns. Hardware verification still requires C=0Ah RETURN followed by C=08h CALL/RETURN; no BIOS read/transfer/install PASS is claimed.


## 2026-11-07 — Restore permanent DOSEN after RTC access (TR-DOS hang root cause)

- The new hardware trace confirmed BANKM=#18 after the high-resolution page-preservation fix, but the TR-DOS C=0Ah call still did not return. The selected filename and type remained valid.
- A cross-module audit found the state transition that had been missed: Project126 initializes ATM video and establishes permanent DOSEN through #0177, then probes the RTC before BIOS selection. The native DS12887_OPEN/DS12887_CLOSE path writes #80 and then #00 to #EFF7. The latter has A9=1 and closes the permanent DOSEN/shadow-port path. Timestamped logging can repeat the same open/close sequence before the BIOS call.
- Added p126_atm_restore_dosen in p126_screen_console.asm. After native RTC gate closure it re-enters the documented #3Dxx ROM trampoline and writes #C6 to #0177. This re-establishes permanent DOSEN/shadow-port access and restores the project's fixed RG=6 ATM 80x25 text mode.
- DS12887_CLOSE now invokes that helper after its #EFF7=0 write on the native ATM RTC backend. SMUC backend behavior is unchanged. The existing ROM2/BANKM D3 preservation and WIN0 #3FF7=#BF selection are unchanged.
- This correction addresses a concrete destructive #EFF7 write in the RTC path. Hardware verification is still required: after RTC PROBE and timestamped logging, the next BIOS selection must show TR-DOS C=0Ah RETURN and then C=08h CALL/RETURN. BIOS sector read, IMAGE transfer and BIOS execution remain unverified.


## 2026-11-07 — Restore the exact Project125 TR-DOS C=0A call boundary

- The 11:29 hardware trace still stopped after the C=0Ah call marker. A source-level comparison with Project125 showed that Project126 inserted p126_bios_trace_search_state between setting C=10 and CALL #3D13; Project125 enters the ROM directly.
- The trace helper was not actually a passive register-preserving probe: it calls the timestamp logger (which reaches the RTC time-read path), emits port #EF traffic, reads the #3D13 ROM window, and its comment overstated its register preservation. Although the helper restores AF/BC/DE/HL, it does not save IX/IY or alternate register banks.
- Removed the helper invocation from the critical C=0Ah boundary. The sequence is now exactly LD C,10 / CALL #3D13, with no helper or I/O between those instructions. The diagnostic routine remains in the source but is no longer executed on this path.
- No ATM port mapping, DOSEN, BANKM, filename, TR-DOS ABI, sector reader, DMA, IPC or IMAGE behavior was changed in this commit.
- **STATUS:** source committed; CI and physical hardware verification pending. Required target evidence: C=0Ah RETURN, followed by C=08h CALL/RETURN. This is a controlled isolation of the Project126-only boundary instrumentation, not yet a confirmed root-cause fix.


## 2026-11-07 — ATM2+ resident TR-DOS call boundary ported from NedoOS r2731

- Compared Project126's BIOS loader with the ATM2+ resident TR-DOS wrapper in `docs/src.r2731/kernel/main.asm` (`sys_SHADOFF`, `dos3d13_resident`, `shadon_pgsys`). NedoOS does not enter `#3D13` using only the current WIN0 selector: it selects the switchable BASIC-48/TR-DOS ROM page with `#3FF7=#83`, writes the current graphics mode through `#FF77` (A9=1, shadow ports off), then enters the TR-DOS ROM. On return it explicitly restores the resident ATM mapping/shadow-port state.
- Replaced Project126's previous `#3FF7=#BF` pre-call selection with the NedoOS ATM2+ call-boundary sequence. Project126 keeps its active `BANKM.D3` video-page selection and sets only ROM2 via `#7FFD`; each TR-DOS call selects WIN0 `#83`, writes RG=6 (`A=#C6`) to `#FF77` to close shadow ports, then calls `#3D13`.
- Added `p126_bios_trdos_call` and routed all three TR-DOS operations through it: C=0Ah file search, C=08h descriptor retrieval, and C=05h sector reads. The wrapper preserves primary and alternate AF/BC/DE/HL plus IX/IY around preparation and around the post-call ATM restoration, so the TR-DOS return registers remain visible to the existing caller.
- After each ROM call, the wrapper invokes the existing `p126_atm_video_init`, which re-enters the documented `#3D2F` ROM trampoline and restores the Project126 80x25 display, WIN0 auto-TR-DOS selector, page 7/3 video mapping and host/staging mappings. This is the Project126 equivalent of NedoOS `shadon_pgsys`; it intentionally uses Project126's own page map rather than copying NedoOS' page constants.
- The sector reader, C=0Ah/C=08h ABI arguments, filename fields, 32-sector BIOS size, DMA/IPC/IMAGE protocol and catalogue flow are unchanged.
- **STATUS:** source committed; CI run 154 (`42368399500`) is in progress at documentation update time. Physical ATM verification pending. Required evidence: C=0Ah RETURN, C=08h CALL/RETURN, 32 successful C=05h reads, then the existing IMAGE transaction markers. This is a source-level port of the documented NedoOS ATM2+ sequence, not yet a hardware-confirmed fix.


## 2026-11-07 — BIOS IMAGE DMA frame-length correction

- Hardware log confirms the ATM2+ TR-DOS call wrapper is now working on target: C=0Ah returns, C=08h returns, the 8 KiB BIOS file is opened, all 32 sectors are read, and ATM video is restored before IPC.
- The first IMAGE request then failed locally with `[ATM IPC] FRAME STRUCTURE INVALID`, immediately after `DMA TX BEGIN`; no E0 command/DMA transfer was started and NeoGS did not receive a frame.
- Root cause found in `p126_bios_send_frame`: it calculated the end pointer as `P126_BIOS_FRAME + 18 + payload_length` and mistakenly passed that absolute address in BC as the frame byte count. With staging at C000h, IMAGE_BEGIN therefore advertised C018h bytes instead of 24 bytes, so the structural preflight correctly rejected it.
- Fixed BC to be the arithmetic sum `P126_IPC_HEADER_SIZE + p126_bios_payload_length`, independently of the C000h frame base. Expected exact sizes: IMAGE_BEGIN 24 bytes; IMAGE_FRAGMENT 8220 bytes (18-byte header + 10-byte fragment extension + 8192-byte BIOS); IMAGE_FINISH 20 bytes.
- No DMA register, page mapping, ABI field, CRC algorithm, handshake or TR-DOS code changed.
- **STATUS:** source committed; CI and the next physical ATM run are required. Expected next trace: FRAME VALID / SEND E0 / E0 ACK / DMA COPY / SEND FF, then NeoGS frame validation. This correction is not yet hardware-confirmed.



## 2026-11-07 — BIOS IMAGE frame CRC payload offset correction

- Hardware log confirms all three IMAGE frames now pass ATM structural preflight and complete the physical DMA handshake. NeoGS reports the expected frame headers and DMA end addresses: IMAGE_BEGIN 108018h (24 bytes), IMAGE_FRAGMENT 10A01Ch (8220 bytes), IMAGE_FINISH 108014h (20 bytes).
- NeoGS rejects each received frame with status 04h (CRC_ERROR), after DMA completion. The staging page mapping, DMA byte counts and header fields are therefore not the cause of this rejection.
- Root cause found in the BIOS loader's frame builder: after calculating CRC over header bytes 00h..0Fh, it continued reading at frame+10h. That incorrectly included the two CRC storage bytes and omitted the last two payload bytes. The NeoGS validator correctly skips offsets 10h..11h and starts payload CRC at frame+12h.
- Fixed the ATM BIOS sender to increment DE twice after the 16-byte header loop, so CRC calculation resumes at frame+18 and covers exactly payload_length bytes. CRC storage remains little-endian at offsets 16..17.
- No DMA registers, page mapping, frame lengths, ABI fields, handshake, NeoGS receiver or TR-DOS logic changed.
- **STATUS:** source commit dffe64f88b501d485f167a459973bc99cc7fef81. CI run 42368829749 pending at documentation update time. Hardware CRC acceptance and SYSBIOS installation remain unverified; next target log must show NeoGS frame validation PASS for all three frames and the IMAGE service's install result.


## 2026-11-07 12:36 — SYSBIOS IMAGE transfer and installation hardware PASS

- Physical ATM/NeoGS run completed the complete BIOS image transaction after the ATM CRC payload-offset correction.
- ATM successfully opened BIOS1.C through TR-DOS, read all 32 sectors (8192 bytes), and restored the ATM video mode before IPC.
- All three ABI 1.0 frames passed ATM structural preflight, completed E0/READY/DMA/FF/completion handshake, and were accepted by the NeoGS frame validator:
  - IMAGE_BEGIN: 24 bytes; DMA end address 108018h; DMA FRAME VALID; SYSBIOS IMAGE BEGIN.
  - IMAGE_FRAGMENT: 8220 bytes; DMA end address 10A01Ch; DMA FRAME VALID; SYSBIOS IMAGE FRAGMENT.
  - IMAGE_FINISH: 20 bytes; DMA end address 108014h; DMA FRAME VALID; SYSBIOS IMAGE FINISH.
- NeoGS explicitly reported SYSBIOS IMAGE INSTALLED AT PAGE 10. This is hardware confirmation of frame CRC acceptance and installation into physical page 10h (base 040000h).
- HARDWARE PASS: TR-DOS BIOS file read; ATM-to-NeoGS DMA transport for all three IMAGE frames; ABI frame validation/CRC; SYSBIOS image installation at page 10h.
- NOT YET VERIFIED: execution from the 8086 reset vector FFFF0h, BIOS initialization, virtual VGA initialization, framebuffer presentation and guest boot. Installation must not be described as successful x86 BIOS execution.


## 2026-11-07 — Initial BIOS execution gate (superseded)

- The previous resident loop consumed p126_ngs_bios_image_ready but did not invoke x86_bios_reset_vector_probe. That gate prevented all guest instruction execution while the complete PCem semantic port remained unfinished.
- The gate was superseded by the bounded bring-up path below. This does not authorize a full BIOS POST, general CPU functional suite, or guest-program execution.


## Intel 8086 execution core — opcode coverage ledger

- Detailed ledger: `docs/8086_PCEM_OPCODE_COVERAGE.md`.
- Current implementation: neogs_sub/x86_exec.asm contains execution paths for the complete 256-byte primary opcode dispatch map, with ModR/M, ALU, stack, interrupt, string and virtual-I/O handlers. This is dispatch coverage, not proof that all 8086 forms and edge cases are semantically complete.
- **Current primary opcode-byte dispatch coverage: 256 / 256 = 100.00%.** Semantic completeness remains below 100% and is not yet assigned a percentage; PCem form-by-form review and integration gaps remain.
- The 16 MOV-immediate encodings were added in commit `28575e385d5d2a66c5ca448e72f7b4e2f01d2391`.
- The full CPU functional suite, full BIOS POST and guest-program execution remain blocked until the complete 8086 implementation is ported and reviewed. The explicitly requested initial BIOS bring-up is a bounded exception: reset-vector execution plus at most 16 subsequent instructions, stopping on HLT, unsupported opcode or memory fault. Assembly/package CI validates syntax, linkage and image size; target execution still requires a hardware log.

- Added original 8086 register INC/DEC encodings `40–4F`; result flags are calculated by the 16-bit ALU path and CF is restored unchanged. Compile-only CI is pending; no CPU or BIOS functional tests were run.

- Added `XCHG AX,r16` encodings `91–97`; swaps AX with CX, DX, BX, SP, BP, SI or DI without modifying FLAGS. No CPU functional tests were run.

- Added A0–A3 direct-offset MOV AL/AX transfers. Reads and writes route through x86_guest_mem_read8/write8; segment overrides are now applied by the prefix layer. No CPU functional tests were run.


## 2026-11-07 — Latest PCem 8086 semantic review

- Corrected 8Eh MOV Sreg,r/m16: the original PCem 8086 path permits loading CS through selector /1; this is not restricted as it is on later x86 profiles. The PCem one-instruction maskable-IRQ inhibit latch is also applied after every 8Eh selector, including ignored /4-/7 encodings; 8Ch does not arm it.
- Matched PCem's ModR/M extension behavior: 8F POP and C6/C7 MOV immediate execute for every /n selector; FE treats /0 as INC and every nonzero selector as DEC; FF /7 consumes ModR/M and has no operation; 8C/8E /4-/7 are ignored.
- REP/REPE/REPNE string instructions now yield after each iteration, restore IP to the first prefix byte when continuing, and pass through the normal IRQ/NMI boundary before the next iteration. REPE/REPNE initialize ZF as PCem does, including when CX is zero.
- BIOS image installation no longer triggers automatic reset-vector probing or guest execution. It only logs that x86 execution is gated.
- Audited every x86_exec call to x86_modrm_read_rm8/rm16 and added an immediate carry check at all 53 call sites, so guest-memory faults cannot be cleared by later ALU/stack operations. Existing write helpers were also checked: all call sites propagate carry, and direct guest-memory read/write calls in the executor already return on faults. The source change and duplicate-check normalization both passed compile/package CI (runs 42376263313 and 42376288583).
- Compile/package CI passed for the ModR/M behavior update (run 42375880001), MOV CS support (run 42375777549), BIOS execution gate (run 42375738280), REP iteration scheduling (run 42375954899), and MOV Sreg IRQ-inhibit timing (run 42376049909). The final comment/documentation sync also assembled and packaged successfully in run 42376060530.
- No CPU functional tests, BIOS POST, or guest programs have been run. Only assembler/linker/package checks are permitted until the complete Intel 8086 core has been ported and reviewed.




## 2026-11-07 — Bounded 8086 BIOS startup execution enabled

- After the resident loop consumes the BIOS-ready event (which is set only after IMAGE_FINISH and the page-10 byte-for-byte readback pass), it calls x86_bios_startup_trace.
- The routine resets the 8086 to FFFF:0000, executes the reset-vector far jump through x86_cpu_step, verifies CS:IP = F000:E05B, then executes at most 16 more guest instructions.
- Each successful instruction emits the post-instruction CS:IP on NeoGS #EF. HLT ends the slice normally. An unsupported opcode or guest-memory fault stops the slice and logs the stop location.
- **BUILD PASS:** GitHub Actions run [42378305671](https://github.com/JTCyborg/Project126/actions/runs/42378305671), source commit `306bd08edbd95e4aeb102657a3b005d8a02651b5`; NeoGS, ATM and TR-DOS images assembled and packaged successfully.
- This is an intentionally bounded BIOS bring-up, not full POST or a claim of complete 8086 semantics. No unbounded guest loop, VGA POST, or guest OS boot is enabled. Target runtime confirmation is pending.

## 2026-11-07 — SYSBIOS page-10 installation integrity

- The NeoGS IMAGE fragment handler now performs a second pass after copying the 8192-byte SYSBIOS fragment from DMA page 42h into physical page 10h. It compares every destination byte against the preserved source fragment before setting `p126_ngs_image_received`.
- A mismatch rejects the fragment and does not permit IMAGE FINISH to mark the BIOS ready. The production WIN3 mapping is restored to page 42h on both success and mismatch paths.
- This closes the source-level gap between DMA-frame CRC validation and destination-copy integrity. Assembly/package CI passed in GitHub Actions run [42377468291](https://github.com/JTCyborg/Project126/actions/runs/42377468291) for source commit `51ba871dfdbbcb52fd1b3461eec7e08bd1ee3fe8`. Physical target readback remains pending; no CPU execution or BIOS POST is enabled by this change.

## 2026-11-07 — 8086 pre-test readiness checkpoint

- PCem comparison corrected STI behavior: STI sets IF but does not arm the `noint` interrupt-inhibit latch; only MOV Sreg (8Eh) and POP SS arm it in the reviewed paths.
- IRET now restores the FLAGS image exactly as PCem's 8086 path does: the stacked word masked with 0FFFh, without synthesizing reserved bit 1.
- The coverage ledger was reconciled with the implemented REP iteration scheduler and the CPU-side interrupt-inhibit consumer; earlier statements that these pieces were wholly pending were stale.
- **Readiness: NOT READY for CPU functional tests.** Remaining blockers include the host/IPC IRQ/NMI producer and vector source, interrupt servicing between REP iterations, form-by-form PCem semantic review, and TF/NMI/IRQ/HLT plus address-wrap/fault corner-case verification.
- At the time of this checkpoint, only assembly/package validation was permitted and reset-vector execution was disabled. This checkpoint is superseded by the bounded BIOS bring-up section below; the full CPU functional suite and full BIOS POST remain blocked.


## 2026-11-07 — 8086 BIOS stop reason on ATM on-screen debug console

- The first target BIOS trace executed the reset-vector far jump and all 16 instructions in the bounded slice, but the reason for returning to the resident loop was visible only on the independent NeoGS #EF log.
- Added a reverse NeoGS-to-ATM debug text path over the existing GSDAT/DBIT handshake. NeoGS publishes the stop message and current guest CS:IP; the ATM host polls DBIT in its idle loop, reads GSDAT, and renders each byte through the existing `BIOS_DebugConsole_PrintChar` screen console.
- Screen messages now distinguish: reset-vector failure, normal pause at the 16-instruction slice limit, guest HLT, and unsupported opcode/guest-memory fault. The existing #EF trace remains intact.
- No DMA frame format, image installation, CPU instruction semantics, memory map, or keyboard handling was intentionally changed.
- **STATUS:** source committed; assembler/package CI and physical target verification are pending. The screen path depends on the ATM host returning to its idle loop and servicing the reverse DBIT byte stream; the next hardware log should confirm the stop message appears in the lower on-screen debug console.


## 2026-11-07 — Remove the 16-instruction BIOS bring-up slice

- Replaced the fixed 16-instruction stop with continuous execution after the verified BIOS reset-vector far jump.
- BIOS execution now continues until the guest executes HLT, the CPU core reports an unsupported opcode/guest-memory fault, or a 65,535-instruction watchdog expires. The watchdog is a runaway-loop safety guard, not a 16-instruction test slice.
- Per-instruction #EF output was reduced to one CS:IP progress record per 256 instructions to avoid flooding the diagnostic console; the final CS:IP is emitted on HLT, fault, or watchdog stop.
- This enables a longer BIOS initialization run, but does not establish complete 8086 semantic correctness. A watchdog stop may indicate a BIOS loop, and any opcode/memory stop still requires investigation. Full BIOS POST and general CPU functional-suite status must be evaluated separately.
- Source commits: `aa0713bf7a382620130391a471aef29010f0e1ed` (execution logic), followed by the assembly-unit comment update.
- **STATUS:** CI assembly/package and physical ATM/NeoGS execution are pending. Do not treat this source change as a hardware PASS.

## BIOS bring-up checkpoint — before guest I/O device implementation

This is the frozen baseline for the transition from CPU/BIOS execution debugging to the guest I/O subsystem.

- Selected physical test image: BIOS1.C, source candidate `bios/27c64d.bin` (8 KiB). The latest ATM log reports that `BIOS1   .C` was selected and read successfully.
- BIOS reset-vector fetch and far transfer into `F000:E05B` were reported PASS by the target diagnostic.
- BIOS continuous execution proceeds without the previously observed x86 guest-memory fault.
- Latest supplied `spectrum_out.txt` ends at the 65,535-instruction watchdog in the BIOS1 initialization loop. The recorded state is `CS:IP=F000:E06F`, `SI=2978h`, `DX=E602h`, `FLAGS=0013h`; I/O counters report IN=0001h and OUT=2468h. This is a watchdog stop, not a BIOS boot/POST pass.
- The I/O trace contains accesses to several low system-board ports and VGA-related ports, and later reports high DX values. The high DX values must be investigated against the loaded ROM bytes and CPU register semantics; they are not accepted as intended device addresses.
- Current guest I/O backend: `neogs_sub/x86_io.asm`. Only the deterministic test latch at `00E0h` is implemented. Other reads return FFh/FFFFh and other writes are ignored. Diagnostic output uses the NeoGS host debug channel, but guest port numbers are never issued as physical NeoGS I/O.
- The normative initial guest port decode is in `docs/P126_ATM_PC_PROFILE.md`, section 4. It reserves the XT-style DMA, PIC, PIT, PPI, DMA-page, RTC, ATA, VGA and optional FDC interfaces. This table is the architectural source of truth; ad-hoc port lists inferred from a partial BIOS trace are not.
- No PIC/PIT/PPI/DMA/VGA/RTC/ATA/FDC runtime device is yet claimed implemented. No full POST or guest operating-system boot has passed.

### I/O implementation order

1. Stabilize the generic 8086 I/O bus contract: full 16-bit port address, byte/word accesses, deterministic reset state, unmapped open-bus behavior, and side-effect-safe dispatch.
2. Implement the system-board devices required by the selected XT BIOS profile: PPI/system control and keyboard input path; PIC 8259; PIT 8253; DMA 8237 plus page registers.
3. Implement VGA register I/O and the corresponding VRAM/aperture behavior, comparing against the pinned PCem VGA model.
4. Add RTC/CMOS and storage controllers only with their agreed ATM DMA/IPC service contracts.
5. Validate each device with isolated register-level tests before returning to BIOS bring-up. A BIOS watchdog disappearing is not by itself a POST pass.

All device models execute as software on NeoGS. NeoGS must not issue guest IN/OUT port numbers on its own physical Z80 I/O bus. Any external keyboard, clock or storage service is accessed only through the Project126 DMA/IPC contract.

## 2026-11-07 — I/O subsystem implementation started

- Guest system-board I/O tasks were added to the architectural scenario; the frozen BIOS bring-up checkpoint remains the baseline.
- First target: XT-compatible 8255 PPI at 0060h–0063h and keyboard scan-code FIFO. PCem comparison: PCem/ppi.c reset state, PCem/keyboard_xt.c port 60h–62h behavior and port 61h keyboard reset/acknowledge, PCem/io.c word-access fallback.
- The generic I/O bus must preserve the full 16-bit guest port address and implement byte/word behavior consistently with PCem/io.c; test latch 00E0h remains during migration.
- ATM→NeoGS keyboard producer over DMA/IPC, PIC IRQ1 delivery and timer-driven keyboard polling are separate dependent tasks. They are not implied by a PPI register implementation.
- No BIOS POST or keyboard hardware pass is claimed.


## 2026-11-07 — XT PPI / virtual keyboard first source slice

- Implemented the initial 0060h–0063h XT PPI register slice in neogs_sub/x86_io.asm: PB system-control latch, PB6 rising-edge keyboard reset, PB7 data acknowledge, PC input/output nibble composition, mode-set and PC bit-set/reset.
- Added a 16-byte XT scan-code FIFO and x86_io_keyboard_push API. FIFO-full is returned through carry; ATM IPC producer and PIC IRQ1 delivery are not connected.
- x86_cpu_reset now invokes x86_io_reset. The 00E0h diagnostic latch remains supported. Word I/O fallback accesses port and port+1, matching PCem/io.c.
- Known limits: PPI mode 1/2 is not implemented; PA behavior is keyboard-input oriented; PB input-mode electrical behavior is not fully modeled; PC input default 0Dh is provisional.
- PCem references: PCem/ppi.c, PCem/keyboard_xt.c, PCem/io.c.
- BUILD PASS: commit 68ae8eed9036c7388b11a5f74d746ac8286d7625; GitHub Actions run 42394977284; NeoGS 0 errors / 0 warnings; x86 image end 3FFBh, 5 bytes below the 4000h resident image limit; I/O module 796 bytes; TR-DOS package succeeded.
- No register self-test, emulator run, hardware run, keyboard IPC, IRQ1, or BIOS POST pass is claimed.

## 2026-11-07 — resident image capacity constraint discovered during I/O work

- The PPI/I/O source slice builds, but X86CORE.C ends at 3FFBh: 16,379 of the 16,384 bytes available in the current single-page resident image. Only 5 bytes remain.
- The physical memory map reserves kernel pages 00h–0Fh (256 KiB), while the current bootstrap/loader contract still constrains X86CORE.C to one 16 KiB page until an overlay manager exists.
- Added an explicit scenario dependency: implement a resident overlay/module manager and multi-page module loading before adding PIC/PIT/DMA/VGA/RTC/IDE code. Preserve the fixed resident entry, WIN1/page-03 stack and WIN3 guest-memory aperture; do not silently raise the 16 KiB assertion.
- This is a capacity/design blocker, not a device runtime failure. The next implementation task is the overlay loader/dispatcher contract; no extra controller is being squeezed into the remaining five bytes.

## 2026-11-07 — Overlay Manager source audit and design baseline

- Audited the current single-image boot path: stage-0 receives one bounded image through DBIT, copies it to logical 0000h and jumps to 0000h; the current bound is 4000h bytes.
- Confirmed the resident translation unit links CPU state, execution, ModR/M, ALU, I/O and IPC into one flat ORG-0 image. The latest successful X86CORE.C is 16,379/16,384 bytes.
- Confirmed startup window mapping: WIN0→page 00h, WIN1→page 03h, WIN2→page 01h, WIN3→page 02h; operational stack at 7FFEh. WIN3 remains exclusively owned by the guest-memory backend.
- A first source scan of the CPU/IPC translation units found no direct memory operands in logical 8000h–BFFFh. WIN2 is the candidate 16-KiB overlay aperture; full runtime non-use still requires audit. The arbitrary-page selector encoding was subsequently confirmed from the Project125 reference as MPAG #00 with ROR8(physical_page); Project126 hardware validation remains pending.
- Candidate physical overlay pool: pages 04h–0Fh. Pages 00h–03h are excluded from allocation.
- Defined the fixed-origin linking direction, proposed module manifest requirements, ABI 1.0 DMA/IPC load path, page-42 staging, WIN3 destination copy/readback, and resident call/return gate with bounded nested mapping restoration.
- Important implementation constraint: current BIOS IMAGE service is hard-coded to SYSBIOS page 10h and an 8-KiB single-fragment image. It is a reference for frame validation/copy/readback, not a reusable generic overlay loader yet.
- The WIN2 selector register/encoding was subsequently confirmed from Project125: MPAG #00, ROR8(physical_page). The Project126 startup write OUT (#00),#80 corresponds to page 01h. Physical mapping/restoration on the Project126 target remains an implementation gate.
- Design specification: docs/P126_OVERLAY_MANAGER_DESIGN.md.
- **STATUS:** design/source audit complete; runtime overlay manager, ATM module streaming, module service, call gate, CI and physical tests are NOT implemented. No device model was moved out of the resident image and no BIOS/CPU test status is changed.

## 2026-11-07 — WIN2 MPAG encoding confirmed from Project125 reference

- Inspected Project125 `neogs_sub/bank_gateways.asm`, `neogs_sub/main.asm`, `shared/neogs_io.inc` and `PROJECT125_MEMORY_LAYOUT.md`.
- Confirmed the hardware contract: WIN2 uses MPAG port `#00`; its page selector is `ROR8(physical_page)` (one `RRCA`). Project125's bank-call gateways switch MPAG, call the overlay entry while WIN1 retains the stack, then restore the caller's bank before returning.
- Project126's startup write `OUT (#00),#80` is consistent with WIN2→page 01h. Project126 candidate overlay pool remains pages 04h–0Fh; Project125 pages 68h/69h and its device/memory backend are not reused.
- **STATUS:** register/encoding and bank-call pattern are source-confirmed from Project125. Project126 physical mapping test on at least two pages, resident gate, allocator, module receiver and ATM streaming loader remain pending.
- Updated design: `docs/P126_OVERLAY_MANAGER_DESIGN.md`. No runtime source was changed in this checkpoint.

## 2026-11-07 — First pinned X86IO overlay implementation

- Split the first fixed-origin overlay from the resident image: `neogs_sub/x86_io.asm` is now assembled at logical `8000h`; resident CPU call sites resolve to its absolute symbols in the same SjASMPlus translation unit.
- The assembler emits independent `build/X86CORE.C` and `build/X86IO.C` files with `SAVEBIN`. Build and disk packaging enforce X86CORE <= 16 KiB and X86IO <= 4096 bytes.
- ATM startup loads `X86IO.C` from TR-DOS after the resident A2h acknowledgement. The first 256-byte sector is copied backwards into C01Ch to preserve the frame header; subsequent sectors are read directly into the remaining data area. The host sends IMAGE_BEGIN, one IMAGE_FRAGMENT and IMAGE_FINISH through the existing ABI 1.0 DMA sender.
- NeoGS IMAGE kind 01h validates the message ID, image kind, size, one-fragment metadata, u32 total length and exact payload length. It copies the accepted fragment from page 42h to physical page 04h through WIN3 and verifies every byte by readback against the still-preserved DMA source.
- IMAGE_FINISH now runs a reversible WIN2 mapping test across physical pages 04h and 05h at logical BFFFh, saving/restoring both original bytes and leaving page 04h selected through MPAG port 00h/selector 02h. Only a passing test publishes `p126_ngs_io_overlay_ready`. The resident main loop will not start BIOS until both the X86IO overlay and SYSBIOS image are ready.
- The target must emit `[NGS] WIN2 PAGE04/05 TEST PASS`; no physical log has yet confirmed this.
- Shared memory map now states: WIN0/page 00 resident code, WIN1/page 03 stack/fixed data, WIN2 8000h-BFFFh overlay aperture, WIN3 C000h-FFFFh guest-memory aperture. X86IO is currently pinned in page 04h; pages 05h-0Fh remain future overlay pool.
- CI run [42396958741](https://github.com/JTCyborg/Project126/actions/runs/42396958741), commit `5121b2c03242539927acebb1cd7933d2d27d1e78`, completed successfully. Build log: X86CORE.C 15,994 bytes / 16,384; X86IO.C 796 / 4,096; ATM host 17,538 bytes; TR-DOS image 655,360 bytes. NeoGS assembly had 0 errors and 0 warnings; resident and overlay binaries are exported independently with SAVEBIN.
- **STATUS:** fixed pinned X86IO overlay source/build/load path is implemented and CI BUILD PASS. No physical ATM/NeoGS log has yet confirmed module transfer, page-04 readback or WIN2 mapping. This is not a generic dynamic overlay manager: no allocator, manifest, call/return trampoline, nested switching or unload/refcounting exists. No BIOS POST, CPU functional suite or guest program PASS is implied.


## 2026-11-07 — boot-time WIN2 gate self-test

- The X86IO IMAGE_FINISH path exercises the resident call gate before publishing p126_ngs_io_overlay_ready. It saves the first four bytes of free physical page 05h, writes a temporary CALL x86_io_reset / RET stub, maps page05 to WIN2, and executes the stub.
- The resident X86IO wrapper switches WIN2 to page04, invokes x86_io_reset_impl, and must restore page05 so the test stub resumes at 8003h. The test checks that the opcode at 8000h is still CDh and the software selector shadow is #82, then restores the original page05 bytes.
- On completion the map is restored to WIN2/page04 and WIN3/page42. The boot log reports [NGS] WIN2 MAP/GATE TEST PASS or [NGS] WIN2 MAP/GATE TEST FAIL. Failure keeps X86IO_READY clear and blocks BIOS bring-up.
- BUILD PASS: [GitHub Actions run 42398073825](https://github.com/JTCyborg/Project126/actions/runs/42398073825), commit 99f007da68aacc57dd0ff9d87a568b1d4df10600. X86CORE.C 16,322/16,384 bytes; X86IO.C 796/4,096 bytes; all assembly and TR-DOS packaging 0 errors/0 warnings.
- Physical execution remains pending. This exercises one page05→page04→page05 nested return; deeper nesting, repeated calls, register/alternate-register preservation and physical stack limits are not yet proven. No BIOS POST or CPU functional-suite pass is implied.


## 2026-11-07 — X86ALU moved to fixed-origin page05 overlay

- Moved the 1,187-byte 8086 ALU/flags implementation out of the 16 KiB resident image into X86ALU.C at logical origin 8000h, physical page05/selector82. X86IO remains page04/selector02 at 796 bytes.
- Added resident wrappers through the common WIN2 call gate for the ten ALU entry points used by x86_exec: ADD/SUB/ADC/SBB/LOGIC in 8-bit and 16-bit forms. Internal ALU helper calls remain within page05.
- Added IMAGE kind02, destination selector82, readback verification, and an X86ALU gate probe. IMAGE_FINISH calls x86_alu_overlay_probe, checks input A=3C/C=1/HL=1234 and output A=A5/HL=5AA5, then verifies WIN2 returns to page04 before publishing X86ALU_READY.
- ATM now uses one shared fixed-profile loader for X86IO.C and X86ALU.C. Both files are packaged into TR-DOS; build script and CI artifact validate/include X86ALU.C. BIOS execution now waits for X86IO_READY, X86ALU_READY and BIOS_IMAGE_READY.
- BUILD PASS: [GitHub Actions run 42399458157](https://github.com/JTCyborg/Project126/actions/runs/42399458157), commit 705a0d5e41909a2cd42654f9095d7dfa43a57669. X86CORE.C 15,632/16,384 bytes (752 free); X86IO.C 796/4,096; X86ALU.C 1,187/4,096. Assembly and TR-DOS packaging: 0 errors, 0 warnings.
- This is a source/build/package pass only. Physical X86ALU transfer, page05 readback, gate probe and ALU instruction execution are unverified. The dynamic allocator, module table/manifest, generic module loading, unload/refcounting and deeper nested-call validation remain pending.
