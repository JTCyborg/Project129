# Project126 — NeoGS physical RAM map

**Revision:** 0.2 (guest RAM bank-window access contract)  
**Status:** build-time allocation contract; physical paging/DMA access still requires hardware validation.

## Scope

This document assigns byte ranges in the NeoGS 4 MiB physical RAM. It defines the logical window contract needed by the first guest-RAM memory backend. DMA register encoding and ATM host buffer addresses remain separate contracts.

The allocation unit is a 16 KiB physical page. There are 256 pages (00–FF), total 0x400000 bytes. All ranges are half-open: start included, limit excluded.

## Physical allocation

| Pages | Physical range | Size | Owner / purpose |
|---|---:|---:|---|
| 00–0F | 000000–03FFFF | 256 KiB | Resident NeoGS kernel and runtime. Hard maximum remains 256 KiB. Page 03 contains two explicitly reserved Project125-parity DMA diagnostic buffers at D000h..D111h and E000h..E111h; the operational stack remains at 7FFEh. |
| 10–1F | 040000–07FFFF | 256 KiB | System x86 BIOS image slot. Enforces the 256 KiB system BIOS limit. |
| 20–2F | 080000–0BFFFF | 256 KiB | VGA BIOS image slot. Separate from system BIOS; reserved capacity, not a required image size. |
| 30–3F | 0C0000–0FFFFF | 256 KiB | VGA VRAM backing store. |
| 40–41 | 100000–107FFF | 32 KiB | One complete ATM presentation-frame buffer. Actual pixel ABI and hardware mode remain open. |
| 42 | 108000–10BFFF | 16 KiB | Production DMA aperture backing page for ABI 1.0 frames. Current hardware test maps it into WIN3; one active DMA transaction. |
| 43 | 10C000–10FFFF | 16 KiB | IPC/session scratch and transient frame-codec workspace. Not a second DMA buffer. |
| 44–83 | 110000–20FFFF | 1 MiB | Guest x86 RAM backing store. This is a physical NeoGS allocation, not the guest logical address map. |
| 84–FF | 210000–3FFFFF | 1.9375 MiB | Unassigned expansion reserve. No subsystem may consume it without updating this map and its assertions. |

## Project125-parity DMA diagnostic carve-outs

The current smoke test intentionally uses the same NeoGS physical addresses as the proven Project125 DMA tests, rather than assuming the new page-42 allocation is already known-good:

- ATM → NeoGS: destination 00D000h (page 03h, offset 1000h), frame size currently 274 bytes.
- NeoGS → ATM: source 00E000h (page 03h, offset 2000h), frame size 274 bytes.
- Project126 maps physical page 03h into WIN1 through PG1 port #21, matching Project125. Physical D000h/E000h appear at logical 5000h/6000h. The active resident stack is at logical 7FFEh in WIN1/page 03h (physical offset 3FFEh), so these two small diagnostic regions are disjoint from the stack.
- These ranges preserve the Project125-parity hardware reference points. They are not production buffers and must not be used for general frame traffic. The current Project126 page-42 validation firmware uses page 42h (108000h) instead; page-03 remains a known-good fallback/reference only.
- The earlier page-03 diagnostic receiver was limited to 3000h bytes to avoid crossing the page boundary. The page-42 receiver now bounds each frame to the full 4000h-byte physical page.

This carve-out is deliberately narrow and must be removed or replaced by a validated page-42 transport test before general frame traffic is enabled.

## NeoGS logical window contract

The resident memory backend reserves logical window WIN3 (C000h–FFFFh) as a banked physical-RAM aperture. The WIN3 page is selected through MPAGEX port 10h (the independent C000h–FFFFh selector), not PG3 port 23h. Match the Project125 encoding: rotate the physical page number right once (`RRCA`) before writing it to MPAGEX. For physical page 42h the selector byte is 21h. Guest RAM physical pages 44h–83h are therefore reachable as a sequence of bank selections. While this backend is active, resident code executes in WIN0, the operational stack and fixed data remain in WIN1, and the currently selected fixed-origin overlay (X86IO page04 or X86ALU page05) executes in WIN2. WIN3 is volatile and is not restored after a memory access; it is exclusively owned by the guest-memory backend. Interrupt handlers that can run during a banked access must reside outside WIN3 and must not use WIN3 as their own data window.

This is a logical execution contract, not a claim that the whole resident kernel fits in three windows. WIN2 is a banked overlay aperture and may be changed only by resident code executing from WIN0 with the stack in WIN1, while no code in the old WIN2 mapping is active. The resident nested call gate now switches between trusted fixed-origin overlays and restores the caller's WIN2 selector; a dynamic module table/allocator remains future work. WIN0 and WIN1 mappings must not be changed while executing resident code or using the resident stack there.

## Ownership and rules

1. The kernel region is the resident code/data/stack budget. Its 256 KiB ceiling is hard; the system BIOS slot is independent.
2. System BIOS and VGA BIOS have distinct backing slots. Guest-visible ROM mapping/overlay addresses are not assigned here.
3. VGA VRAM is exactly 256 KiB. The 32 KiB ATM presentation frame is separate scanout/export storage, not VGA VRAM.
4. ABI 1.0 uses a maximum 16 KiB DMA frame. Page 42 is the NeoGS-side DMA backing page. Larger payloads use ABI fragmentation.
5. The IPC scratch page is reserved RAM and must not be exposed as a second concurrent DMA transaction.
6. Guest RAM backing is a full 1 MiB allocation. The guest 8086 decoder may map RAM, ROM overlays, VGA apertures and devices differently; this does not imply the conventional IBM PC 640 KiB + UMA layout.
7. The banked guest-RAM helper accesses the guest backing linearly at physical offset 110000h + guest physical address. VGA/ROM overlays are dispatched before this helper; it deliberately rejects those regions. ATM BIOS-image staging uses page 0 at C000h..FFFFh; DMA transfers use physical page 42h.
8. Physical page numbers are allocation identifiers only. Actual NeoGS logical windows and DMA register programming must follow hardware documentation; do not infer a direct Z80 address from a physical page number.

## Build enforcement

The machine-readable source is shared/p126_neogs_memory_map.inc. It is included by neogs_sub/x86_cpu_state_assemble.asm. Every standard NeoGS assembly build evaluates adjacency, capacity and non-overlap assertions and exports allocation symbols in build/NEOGS.map.

The build can prove internal consistency and fit within 4 MiB. It cannot prove physical paging or DMA access; those require separate emulator/hardware tests.

## Deliberately unresolved

- Guest x86 logical 1 MiB address map: RAM/ROM overlays, VGA apertures, option ROM and device windows.
- WIN2 is the fixed-origin overlay aperture at 8000h–BFFFh, selected by MPAG port 00h using the Project125 RRCA selector encoding. X86IO/X86ALU/X86DEV/X86EXEC are pinned to physical pages 04h/05h/06h/07h with WIN2 selectors 02h/82h/03h/83h respectively; only pages08h–0Fh belong to the dynamic pool. WIN3 remains the banked guest-memory aperture through MPAGEX port 10h. Dynamic allocation and target validation remain pending.
- DMA register address encoding and exact DMA transaction setup.
- ATM host staging-buffer addresses and host paging state.
- Guest-visible system-board profile, I/O ports, PIC/PIT/keyboard/RTC.
- VGA BIOS actual maximum image size and guest ROM mapping.
- Video frame pixel format, stride, palette and actual ATM output mode.


## Guest memory backing access v0.1

The x86 byte dispatcher routes each classified guest physical address to its backing allocation through WIN3:

| Guest range | Backend | NeoGS pages | Access |
|---|---|---:|---|
| 00000–9FFFF | Guest RAM | 44–6B | Read/write |
| A0000–BFFFF | Linear VGA aperture staging | 30–37 | Read/write |
| C0000–C7FFF | VGA BIOS slot | 20–21 | Read-only |
| C8000–FDFFF | Guest RAM | 74–83 | Read/write |
| FE000–FFFFF | System BIOS slot | 10 | Read-only |

The system BIOS slot is 256 KiB but the current guest-visible reset mapping is 8 KiB at FE000–FFFFF. The image is stored at the beginning of the slot; the reset vector FFFF0 therefore addresses slot offset 1FF0. The VGA BIOS guest window is 32 KiB and uses the first two pages of its separate 256 KiB slot.

The initial VGA aperture backend maps the guest's 128 KiB A0000–BFFFF range linearly to the first eight pages of the 256 KiB VRAM allocation. This is an explicit staging implementation, not VGA-compatible plane addressing. Sequencer/GC registers, latches, plane masks, read/write modes and scanout remain unimplemented.

The common API is `x86_guest_mem_read8` and `x86_guest_mem_write8`. ROM writes fail with carry set. The selector's page-bias constants are asserted in the shared NeoGS map. All accesses use the WIN3 MPAGEX page-select port 10h with the Project125 RRCA selector encoding; the runtime placement constraints described above still apply.


### Verification — unified guest memory dispatcher

- **BUILD PASS:** GitHub Actions run [42306662917](https://github.com/JTCyborg/Project126/actions/runs/42306662917), source commit `b4b21ff7dcc4a161c9912d03162487e02dc542fb`.
- SjASMPlus 1.23.1 assembled the NeoGS unit with 0 errors and 0 warnings. The x86 state module is 842 bytes; combined x86 state/ALU image is 1,616 bytes. ATM IPC (246 bytes) and NeoGS IPC (65 bytes) also assembled with 0 errors and 0 warnings.
- TR-DOS image generated at 655,360 bytes. `X86CORE.C` is 1,616 bytes / 7 sectors; BIOS1.C, BIOS2.C and COMPAQ.C are each 8,192 bytes / 32 sectors. Listings, maps and disk artifact were published.
- The disk assembler retains one pre-existing generated-path backslash warning; the NeoGS and IPC assembly units report no warnings.
- **Not verified:** actual WIN3 paging/read/write on target hardware, ROM contents in physical slots, guest BIOS POST, VGA plane semantics or scanout. This is BUILD PASS only.


## Resident startup mapping revision 0.3

The first executable resident image is loaded by the Project126 GS105a stage-0 bootstrap into physical page 00 and entered at logical 0000h. The resident entry enables NOROM/EXPAG, maps WIN0 (port 20h) to physical page 00 and WIN1 (port 21h) to physical page 03, and moves the operational stack to logical 7FFEh. Temporary bootstrap execution uses WIN1/page 03 and WIN3/page 02 with its stack at FFFEh; after handoff WIN1/page 03 owns the operational stack and WIN3 remains the volatile guest-memory bank window. WIN2 is initialized to physical page 01 until X86IO is installed. X86IO is left selected at page04 after its mapping/gate tests; X86ALU is installed into page05 and entered only through the resident gate.

ATM reads P126BOOT.C and X86CORE.C from TR-DOS before video paging is enabled. P126BOOT.C is a one-sector GS105a #14/#13 bootstrap; X86CORE.C is the resident entry plus IPC and x86 core. After the resident A2h acknowledgement, ATM reads X86IO.C and X86ALU.C through TR-DOS and sends both as ABI 1.0 IMAGE transactions over DMA. DBIT/GSDAT is used only during the stock-ROM bootstrap. After A2h, application frames use ABI 1.0 DMA exclusively.


## ROM independence and full physical RAM ownership

The GS105a stock ROM is a temporary bootstrap transport only. Project126 stage-0 is uploaded with ROM command #14 and entered with #13. The bootstrap sets GSCFG0.NOROM (local port #0F, bit 0) before handing execution to the resident image; it also enables EXPAG. No runtime memory-capacity decision may depend on the stock ROM #20 response.

The 4 MiB physical map describes the target addressable resource: 256 pages of 16 KiB, 000000h–3FFFFFh. Pages 84h–FFh are currently unassigned expansion reserve, not unavailable memory. The runtime must be able to discover/test all physically installed pages and allocate the currently unassigned range when needed. A complete 256-page destructive/non-destructive memory test strategy must preserve the executing kernel, stack, bootstrap, DMA and IPC state (for example by using a reserved test window and restoring its contents).

The previously observed ROM response 3F:40:00 is diagnostic output from the stock ROM only; it is not authoritative proof that the top three pages are absent. The ATM-side pre-bootstrap check requiring RAM24 high byte >= #40 is superseded and must be removed from the startup path. Actual NOROM operation, page detection and full-range read/write retention remain HARDWARE-UNVERIFIED.


## Production DMA page-42 hardware validation stage (2026-11-07)

- The current diagnostic firmware maps physical page 42h into WIN3 through MPAGEX port #10 before arming DMA. It encodes the page selector exactly as Project125 does: `A=42h; RRCA; OUT (10h),A`, producing selector byte 21h. PG3 port #23 is not the WIN3/MPAGEX selector. Resident code, data and stack remain in WIN0-WIN2; WIN3 is used only as the 16 KiB staging aperture at logical C000h-FFFFh.
- ATM→NeoGS DMA destination is physical 108000h (DMA_MOD=1, HAD=10h, MAD=80h, LAD=00h). NeoGS validates the received frame from logical C000h after stopping DMA. The page bound is 4000h bytes, inclusive of a full-page frame.
- NeoGS→ATM test frame is built at logical C000h in the same mapped physical page; DMA source is 108000h with the same module/address registers. The existing ATM ROM dummy-read and CRC/pattern checks remain unchanged.
- The forward test frame is now 274 bytes: 18-byte ABI header plus deterministic 256-byte payload 00h..FFh. Both endpoints validate the full frame CRC. The reverse test uses the same 274-byte deterministic response.
- This is a source/build test stage, not a hardware PASS. Require CI BUILD PASS and a new target log showing page 42 pre-mapped, forward DMA readback 108112h, NeoGS FRAME VALID, reverse DMA readback 108112h, ATM FRAME CRC VALID and PATTERN PASS. If page-42 mapping fails, restore the page-03 Project125 parity test without changing its proven sequence.


## WIN3 selector correction — 2026-11-07

The production page-42 DMA test initially wrote the raw physical page number 42h to port 23h. This was incorrect: Project125 selects the independent WIN3 window with MPAGEX at port 10h and rotates the physical page number right once before the OUT. The corrected page-42 selector sequence is `LD A,42h / RRCA / OUT (10h),A` (selector byte 21h). Both ATM→NeoGS receive-buffer access and NeoGS→ATM response construction must use this exact mapping. DMA module/address registers remain module 1, HAD=10h, MAD=80h, LAD=00h (108000h). Hardware verification of the corrected production mapping is pending.



## Production page-42 DMA hardware validation — 2026-11-07

The corrected WIN3 selector (LD A,42h / RRCA / OUT (#10),A) has now passed a physical ATM/NeoGS test. The ATM→NeoGS frame was visible at logical C000h with signature 50313236 and full header 50313236010001050000010000010000; NeoGS validated it and reported DMA FRAME VALID. The reverse transfer returned CRC D867 and the complete 00h..FFh payload pattern passed at ATM. DMA destination/source physical base remains 108000h. This validates page 42h mapping and the 274-byte bidirectional smoke frame only; it does not validate maximum-size transfers or streaming/fragmentation.


## SYSBIOS IMAGE profile

The SYSBIOS IMAGE profile accepts exactly one 8192-byte image. ATM stages the complete ABI frame in RAM page 0 at C000h..FFFFh and sends it through the production DMA page 42h. After frame validation, the resident handler copies the 8192-byte fragment to physical page 10h, offset 0000h. The copy alternates WIN3 between page 42h (MPAGEX selector 21h) and page 10h (selector 08h), leaving resident code and stack outside WIN3.

The guest-visible BIOS window remains FE000h..FFFFFh. Its reset vector FFFF0h maps to offset 1FF0h in the 8 KiB image. The remaining 248 KiB of the physical system BIOS slot are reserved capacity and are not exposed by this initial guest mapping.

This SYSBIOS profile is implemented in source. After the page-42 frame passes the complete ABI CRC, the resident handler copies the 8192-byte image into page 10h and performs a second byte-for-byte comparison of all 8192 destination bytes against the still-preserved staging fragment before setting `image_received`. A mismatch rejects the fragment and leaves the BIOS image unready. The comparison is source-level implemented. Assembly/package CI passed in GitHub Actions run [42377468291](https://github.com/JTCyborg/Project126/actions/runs/42377468291) for source commit `51ba871dfdbbcb52fd1b3461eec7e08bd1ee3fe8`. Physical page-10 readback on the target and subsequent 8086 execution remain unverified; CPU execution stays gated pending separate CPU-completeness approval.


## First fixed-origin X86IO overlay (2026-11-07)

The first overlay slice moves `neogs_sub/x86_io.asm` out of the 16 KiB resident image:

- Resident `X86CORE.C`: 15,994 bytes (limit 16,384; 390 bytes remain).
- Overlay `X86IO.C`: 796 bytes, assembled at logical origin `8000h` (`8000h–831Bh`).
- ATM opens `X86IO.C` after the resident A2h handshake, reads the first sector into C000h, copies it backwards to C01Ch to preserve the DMA frame header, and reads remaining sectors directly after the first data block.
- ATM sends IMAGE_BEGIN / one IMAGE_FRAGMENT / IMAGE_FINISH using ABI 1.0 DMA. The image kind is 01h and the profile size limit is 1000h bytes.
- NeoGS copies the fragment from DMA page 42h to physical kernel page 04h through WIN3 and verifies every installed byte against the still-preserved DMA source.
- IMAGE_FINISH runs a reversible WIN2 mapping test across physical pages 04h and 05h at logical BFFFh, restores both original bytes, leaves page 04h selected through MPAG port 00h/selector 02h, then sets `IO_OVERLAY_READY` only on test success. The target log must show `[NGS] WIN2 PAGE04/05 TEST PASS`.
- Resident CPU call sites are statically linked to the X86IO labels in the same SjASMPlus assembly pass. Page 04h is pinned in WIN2; there is not yet a dynamic overlay call gate or allocator.
- BIOS execution is gated until both `IO_OVERLAY_READY` and `BIOS_IMAGE_READY` are set.

GitHub Actions run [42396958741](https://github.com/JTCyborg/Project126/actions/runs/42396958741), commit `5121b2c03242539927acebb1cd7933d2d27d1e78`, passed assembly and TR-DOS packaging with the split images. It reported `X86CORE.C=15994` and `X86IO.C=796`. This is BUILD PASS only. Physical ATM/NeoGS transfer, page-04 readback and WIN2 mapping remain to be confirmed from a target log.


## Fixed-origin X86ALU overlay (2026-11-07)

The 8086 ALU implementation has been moved out of WIN0 into a second fixed-origin overlay on physical page 05h:

- Resident X86CORE.C: 15,632 bytes of the 16,384-byte WIN0 limit (752 bytes free).
- X86IO.C: 796 bytes, origin 8000h, physical page 04h / selector 02h.
- X86ALU.C: 1,187 bytes, origin 8000h, physical page 05h / selector 82h.
- The 10 ALU entry points used by x86_exec are resident wrappers. Each enters the shared WIN2 call gate; the ALU implementation's internal calls remain direct within page05.
- ATM uses the shared fixed-profile loader to stream X86IO.C and X86ALU.C after A2h. IMAGE kind 02h targets page05; the receiver verifies every byte through WIN3 before IMAGE_FINISH.
- IMAGE_FINISH probes x86_alu_overlay_probe through the resident gate and confirms that WIN2 returns to page04 before publishing X86ALU_READY.
- BIOS execution is gated on X86IO_READY, X86ALU_READY and BIOS_IMAGE_READY.
- BUILD PASS: [GitHub Actions run 42399458157](https://github.com/JTCyborg/Project126/actions/runs/42399458157), commit 705a0d5e41909a2cd42654f9095d7dfa43a57669. X86CORE 15,632/16,384; X86IO 796/4,096; X86ALU 1,187/4,096. Assembly and TR-DOS packaging: 0 errors, 0 warnings.
- This validates source/build/package only. The new ATM X86ALU transfer, page05 readback, gate probe, and ALU execution on physical ATM/NeoGS remain unconfirmed.
