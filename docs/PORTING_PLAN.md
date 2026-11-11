# Project129 porting plan

## Reference and scope

Behavioral reference: `JTCyborg/Project127`, branch `main`; scenario baseline is ATM Turbo 2+ System Core 0.8.8. Project127's source is an ATM Turbo 2+ Z80 assembly implementation. Project129 must preserve its boot sequence, subsystem ordering, device ownership and externally observable behavior while replacing the implementation with Z88DK C and only the assembly glue required by Z88DK/ATM.

Do not copy Project127 assembly modules into the Project129 executable. Use them to verify contracts and hardware behavior.

## Boot scenario (Project127 contract)

1. TR-DOS starts tokenized BASIC file `BOOT`.
2. BASIC line 10 initializes debug port `#EF` and executes `CLEAR 24000`.
3. BASIC invokes the TR-DOS interception sequence `RANDOMIZE USR 15619`.
4. TR-DOS loads `P129BOOT.C` as CODE at decimal 24576 (`#6000`).
5. BASIC emits the post-load marker and invokes `RANDOMIZE USR 24576`.
6. Resident entry disables interrupts, establishes a safe stack, configures the ATM paging state required by the host, and emits diagnostics through `#EF`.
7. The initial bootstrap must stop at a stable idle point before enabling optional drivers.

The first Z88DK milestone is deliberately narrow: produce a valid TR-DOS image and prove the BASIC-to-C-entry handoff. Do not initialize video, RTC, keyboard, HDD or interrupt delivery in this milestone.

## Revised implementation order (user decision, 2026-11-11)

Project129 must bring up the ATM-native user interface immediately after the resident C entry and before storage, RTC, memory manager, mapper, IRQ, keyboard or disk services. The order is:

1. Resident entry and C handoff (runtime-confirmed).
2. ATM RG6 80x25 console initialization and status/log output.
3. TR-DOS catalogue preload and directory handling.
4. DS12887 RTC read/display (SMUC path runtime-confirmed).
5. Physical Nemo IDE/SMUC read-only bring-up (user-requested priority ahead of the remaining subsystems).
6. UINT32 range/check API (implementation added; runtime confirmation pending).
7. ATM-side keyboard/input (current implementation milestone; keyboard is deliberately moved ahead of speaker by the user's 2026-11-11 decision).
8. ATM-side speaker output and the guest PIT/PPI-to-host audio path (after keyboard).
9. Remaining memory, mapper, video, storage-service, timer/event and interrupt work, preserving Project127 contracts and dependencies.

The UI uses the Project127/Project126 ATM text layout: character plane on page 7, attributes on page 3, 80 columns x 25 rows, 12 status rows and 13 scrolling log rows. UI output is mirrored to debug port #EF. No live IRQ is enabled by UI initialization.

## Current implementation status (2026-11-11)

- Bootstrap 0.3.17: adds the first resident physical-page allocator foundation. It models the agreed 1 MiB / 64 × 16 KiB pages, reserves the boot W3 page P0 plus resident/video pages P2/P5/P3/P7, and provides top-down allocation, reserve/free, pin/unpin reference counts and free-page accounting. Startup exercises full-pool exhaustion/reuse and pin lifetime. The allocator is metadata-only. Bootstrap 0.3.18 adds a software-only four-window map shadow and transactional W3 remap (pin new page, commit/rollback, release old page); it deliberately performs no hardware OUT. Physical RAM access, cross-page copy and bank-manager integration remain incomplete; the UI ownership lease is implemented separately. Build/runtime confirmation is pending. Build/runtime confirmation is pending.
- Bootstrap 0.3.16: the user's 0.3.15 runtime log confirms keyboard inactivity completion: after the last key transition it emits `[KBD] DONE` and `[P129] KEYBOARD COMPLETE`, immediately followed by `[SPEAKER] ATM #FE D4 TONE BEGIN`. The next stage adds the Project127-compatible one-shot ATM beeper smoke test on port `#FE`, bit D4, approximately 0.57 seconds at 7 MHz. It initializes the output shadow with low nibble zero, matching Project127's explicit test contract (`BORDER/TAPE STATE=0`), toggles only D4, and ends with D4 low. The user's 0.3.16 runtime log confirms that the tone routine reached its end marker. Audible output has not yet been independently confirmed. This is a physical ATM beeper smoke test only; it is not IBM PC Speaker/PIT/PPI emulation and does not provide asynchronous audio.

- Bootstrap 0.3.15: the user's 0.3.14 runtime log confirms ZX fallback make/break transitions (matrix row 3 changes `1F` -> `1E`/`1D` -> `1F`). ATM XT negotiation remains unverified and fell back to ZX. The monitor now uses the Project127 software delay loop and resets a 20-window inactivity countdown on each observed transition. Project127 describes 41 windows as approximately 10 seconds at 7 MHz; 20 windows target approximately 5 seconds. Expiry emits `[KBD] DONE` and `[P129] KEYBOARD COMPLETE`; the user's 0.3.15 runtime log confirms these markers. The timeout is configured for approximately five seconds, but exact wall-clock duration has not been measured.

- Bootstrap 0.1.0: BASIC/TR-DOS load, resident entry and Z88DK C handoff are runtime-confirmed by the user.
- Bootstrap 0.3.7: ATM RG6 80x25 console and TR-DOS catalogue preload are runtime-confirmed. The user verified all eight sector reads, the 2048-byte directory snapshot, two catalogue entries (`boot.B`, `p129boot.C`), and visible UI/log output.
- Bootstrap 0.3.8: a read-only DS12887 driver is implemented in `src/rtc.asm`. It probes native GLUK (`#EFF7/#DFF7/#BFF7`) first, falls back to SMUC (`#FFBA/#DFBA`), validates Status D/A, waits for UIP to clear, takes a stable seconds/minutes/hours/seconds snapshot, and converts BCD/binary plus 12/24-hour formats. It restores the DOSEN/RG6 state through the Project126 `#3D2F` / `#0177` trampoline after native GLUK access.
- The ATM status panel now has a dedicated `REAL TIME CLOCK` field; `src/main.c` probes and reads the RTC after UI and TR-DOS catalogue startup, then publishes `HH:MM:SS` or `??:??:??`.
- Bootstrap 0.3.8 DS12887 detection and time read are runtime-confirmed by the user: `BACKEND=SMUC`, valid `HH:MM:SS` output (`19:16:36`). The native GLUK path and live on-screen second refresh still need separate confirmation.
- Bootstrap 0.3.9 Nemo IDE/SMUC probe is runtime-confirmed by the user: IDENTIFY returned LBA28 sector count `00004EC0`, and absolute LBA 63 was read successfully with 512-byte BPB and `55AA` signature. The transport is read-only and does not issue WRITE/FLUSH or change ATM paging.
- Bootstrap 0.3.10 FAT16 root directory is runtime-confirmed by the user. The log shows `IO.SYS`, `MSDOS.SYS`, `DOS <DIR>`, `COMMAND.COM`, `WINA20.386`, `CONFIG.SYS`, `AUTOEXEC.BAT`, followed by `DIRECTORY READ OK` and `FILE COUNT=0007`. This confirms BPB-derived root-sector calculation, LBA28 reads and FAT16 8.3 root-entry parsing on the user's Nemo IDE disk. Nested directories, file contents and writes are not implemented.
- Bootstrap 0.3.11 adds `src/range.c`: a UINT32 half-open physical-range validator bounded by 1 MiB, with overflow rejection and eight boundary regression cases. The resident startup reports PASS/FAILED before idle. Build-script source hashing, link inclusion and map-symbol/residency checks are added. Compile/runtime confirmation is pending.
- Bootstrap 0.3.13 corrects the hexadecimal literal syntax in `src/keyboard.asm` for the actual `z88dk-z80asm` assembler (for example, `#FE` -> `0FEh`); the previous 0.3.12 build failed during assembly before linking. The keyboard implementation remains compile/runtime unverified. The keyboard driver adds `src/keyboard.asm`, ported against the Project127 ATM_KBD contract: mode-2 state registers, mode-3 lastscan event, and ZX 8x5 matrix fallback if the ATM_KBD handshake fails. The resident loop polls and logs event/state changes on #EF; the build checks both keyboard entry points. Compile/runtime confirmation is pending. The ATM XT handshake path is not considered verified until the user confirms `[KBD] ATM XT ACTIVE` and key make/break logs; ZX fallback remains separately testable.
- The catalogue preload uses the same TR-DOS ROM contract as Project127: entry `#3D13`, track 0 sectors 1..8, destination `#C800..#CFFF`, scratch stack `#B7F0`, and error/status bytes `#5D0F/#5D10`.
- Runtime confirmation of Bootstrap 0.3.0 UI startup is pending. Full W3 lease integration remains to be completed; do not report the UI ownership stage as complete.

## Full Project127 startup scenario to preserve

The Z88DK port must reproduce this runtime order and its observable stage markers, not merely provide a similar set of drivers:

1. Enter at `#6000`; disable interrupts, establish the `#BFFF` stack, perform the Project127 ATM paging/shadow-register initialization and emit the entry/stack/debug diagnostics.
2. Preload the TR-DOS catalogue, initialize the W3 ownership state and initialize the UI; mark the UI ready only after its initialization succeeds.
3. Perform the read-only DS12887 probe/read.
4. Initialize the 1 MiB / 64-page physical memory model; reserve video pages, boot/system pages and the IM2 table page.
5. Validate the linked image layout and P5/P2 residency; run physical-page, negative-path, UINT32 range, top-down arena, logical address-space and logical-span preflight checks.
6. Initialize the software page-map shadow; validate page encoding/window ports; run protected-window handoff, map transaction commit/rollback, stack handoff, resident-window, W3 ownership and W3 recovery checks.
7. Initialize the IRQ model and validate masks, vector/table bounds, interrupt context and batch handling. Install only the masked ATM #FF vector. Keep `DI`; live IRQ activation remains skipped until the hardware gate is controlled and separately validated.
8. Run the physical W3 page sweep, allocator/API checks, full-pool allocation stress, pin/unpin reference-count checks and cross-page logical-span copy checks.
9. Run the TR-DOS directory service, then the ATM video mode cycle and VRAM restore/CRC check.
10. Run the ATM speaker smoke test.
11. Probe/read the physical Nemo IDE/SMUC device and list its root directory.
12. Enter the ATM-side keyboard monitor: poll the Unreal Speccy ATM_KBD protocol first, fall back to the ZX matrix only if ATM_KBD is unavailable, log transitions, and finish on the defined inactivity timeout.

The first milestone in Project129 intentionally implements only steps 1-2's boot handoff and a safe idle. Later milestones must add the remaining scenario steps in this order, with each stage's dependencies and pass/fail markers retained. Do not claim the full 0.8.8 scenario is ported because the bootstrap has reached idle.

## Project127 subsystem order to preserve

1. Boot entry and diagnostic channel.
2. UINT32 range/check API.
3. ATM RAM page allocator and memory operations.
4. TR-DOS disk service (boot medium and file service only).
5. ATM native video.
6. DS12887 RTC through SMUC.
7. Keyboard/input.
8. Physical Nemo IDE/SMUC block storage.
9. Speaker/audio.
10. Timer/event service and interrupt/dispatch foundation.

Project129 implementation-order exceptions (2026-11-11): physical HDD was explicitly moved immediately after RTC. The user has now specified keyboard next and speaker immediately after keyboard. These decisions change implementation priority only; they do not change Project127's reference contracts or the eventual subsystem behavior.

## Architectural contracts

- ATM host RAM: 1 MiB; 64 physical pages of 16 KiB.
- ATM Z80 address space remains 64 KiB; this is not a program-size ceiling.
- API addresses, lengths and file offsets are unsigned 32-bit values. Validate addition overflow before calculating end addresses.
- ATM host owns physical external hardware and controller ports.
- Nemo IDE/SMUC storage is a physical block device, not a virtual HDD image. Required block operations: IDENTIFY, READ, WRITE, FLUSH, with LBA, buffer and transfer-length validation.
- RTC is DS12887 through SMUC and serviced by the ATM host.
- Any NeoGS/companion CPU has an independent RAM address space and must access host-owned devices only through the agreed host transport/DMA.
- Debug channel is port `#EF`; retain stable, parseable stage markers.
- Fixed resident layout: W0 is ROM; W1/P5 contains remap-critical resident code/data; W2/P2 contains the resident stack/control state; W3 is the only remap target while the resident code and stack remain fixed.
- W3/UI ownership sequence: UI ACTIVE -> QUIESCED -> HANDOFF ownership -> QUIESCED with no owner -> UI ACTIVE. Reject transitions while the UI owns a busy W3 lease. Snapshot/rollback must restore the complete ownership tuple and software mapping.
- During QUIESCED/HANDOFF, no UI console or other W3-dependent UI operation may run. A remap is never performed while the executing code or active stack resides in the target window.
- ATM page mapper contract: window ports are `#3FF7/#7FF7/#BFF7/#FFF7`; physical page encoding is `#7F - page`. The software shadow/transaction layer must validate protected windows before any hardware OUT.
- Do not activate live IRQ delivery until the ATM interrupt gate, vector, frame and dispatcher are independently validated.

## Program-size and banking acceptance

The 16 KiB physical page size and 64 KiB Z80 logical address space are window/addressing constraints, not application-size limits.

Project129 must separately demonstrate:

- resident/application image larger than 16 KiB;
- executable application payload larger than 64 KiB;
- code and data located in different physical pages;
- banked function calls and returns across page switches;
- nested bank calls with mapping restoration;
- reads/writes spanning page boundaries;
- TR-DOS loading of the complete multi-part application chain.

A large static array alone is not proof of banked execution. The runtime log must identify loaded bank images, selected page/window and an actually executed banked routine. Do not mark banked execution active before this evidence exists.

## Validation policy

For every milestone record: source/build identifiers, exact build command/tool versions, image size and contents, runtime log, and pass/fail status. Never report a compile or emulator test as passed unless it was actually run. Avoid isolated tests that do not advance an acceptance criterion.


### 0.3.14 keyboard assembler correction

The 0.3.13 assembler reached keyboard control-flow validation and reported an out-of-range relative branch (`jr z,p129_kbd_poll_matrix`, displacement +129). Replaced that branch with absolute conditional `jp`. This is a control-flow encoding correction only; keyboard compile/runtime remains pending user build and emulator validation.


### Interrupt architecture evidence review — 2026-11-11

- Added `docs/INTERRUPT_ARCHITECTURE.md` to separate Z80 architectural facts, Project127/Unreal emulator evidence, and ATM Turbo 2+ hardware claims still requiring confirmation.
- Project127 reference: `src/kernel/p127_irq.asm` 0.6.0 uses a masked IM2 setup, I=#B0, fixed W2/P2 table/handler, and the #FF vector byte under its checked Unreal Speccy configuration (`FloatBus=0`, `FloatDOS=0`). It does not enable interrupts in the installer.
- Do not generalize that emulator vector to all physical boards. A full 257-byte repeated trampoline table is the generic safe option when the IM2 acknowledge byte may vary; a single vector slot is valid only under a verified deterministic vector contract.
- PIT, keyboard IRQ, external ZX-Bus IRQ and NMI-triggered Shadow ROM switching remain unverified for the current Project129 target. The existing EC07 timer article is about two sound-card timers, not proof of an ATM system PIT interrupt.
- Project129 remains DI-only. No asynchronous IRQ/NMI or speculative hardware port programming is enabled until fixed-page placement, mapper safety, vector/acknowledge policy and live delivery are verified.


### Bootstrap 0.3.18 — software page mapper foundation

- Added src/map.h and src/map.c, following the Project127 p127_map.asm contract without linking or copying its assembly.
- Initial shadow map is W0=ROM, W1=P5 resident, W2=P2 stack/control, W3=P0 boot mapping. P0 is reserved by the allocator so top-down allocation cannot hand out the page currently mapped in W3.
- ATM page encoding is 0x7F - page; window selectors are #3FF7/#7FF7/#BFF7/#FFF7. The mapper exposes these as software metadata only.
- Only W3 can be remapped by this API. W0/W1/W2 remain fixed; the protected-window mask is checked before staging.
- A W3 transaction pins the new allocated page before commit, snapshots the four-window map, supports rollback, and on accept unpins the previous allocated W3 page. p129_map_restore_boot releases the leased page and restores W3=P0.
- Startup reports the mapper state and runs a transaction lifecycle check after the allocator check.
- This is not hardware page switching: no OUT to ATM paging ports is performed. Physical mapping and W3/UI lease integration remain later stages.
- The allocator free pool is 59 pages (64 total minus P0/P2/P3/P5/P7).


### Bootstrap 0.3.19 — W3/UI ownership lease

- Added a resident UI ownership state machine: OFFLINE -> ACTIVE -> QUIESCED -> HANDOFF -> QUIESCED -> ACTIVE. Invalid transitions are rejected.
- UI character output and RTC clock refresh are gated: they perform no console work unless the state is ACTIVE. This prevents normal UI writes while W3 is handed to a banked-memory owner.
- Exported quiesce, handoff-begin, handoff-end and resume entry points for the forthcoming bank manager. Startup validates the legal transition chain and rejection of out-of-order transitions, then leaves the UI ACTIVE.
- This is an ownership gate, not the physical page mapper. Existing UI W3 video-page writes remain the only direct W3 page-port operations; the software page-map transaction API is not yet wired to the lease or to physical OUT. Arbitrary W3 bank execution is not enabled.


### Bootstrap 0.3.20 — W3/UI lease and page-map integration

- Added p129_map_w3_lease_begin/end orchestration. Begin quiesces the UI, enters HANDOFF, pins and commits an allocated W3 page in the software shadow map, and leaves the UI in HANDOFF. End restores W3=P0, releases the page pin, and resumes the UI.
- Added an integrated lifecycle check that allocates a page, transfers ownership, checks the mapped page and pin count, restores the boot map, and frees the page.
- This remains software-only: the shadow map is not physical ATM page-port state. No physical banked reads/writes or execution are enabled.


### Bootstrap 0.3.21 — nested W3 bank ownership manager

- Added an eight-level resident W3 bank ownership stack on top of the W3/UI lease.
- The outer enter acquires the UI lease and pins the first allocated page. Nested enters pin the child page and switch the software W3 shadow while retaining the parent page pin. Leave restores the parent page and releases the child pin; the outer leave restores W3=P0 and resumes the UI.
- Added a three-level nested enter/leave acceptance check, including depth, active-page and reference-count validation at each return.
- This is a software ownership/page-map manager only. It does not yet execute code from W3, transfer the CPU stack, copy data through physical pages, or issue physical ATM page-mapper OUT operations. Those require the verified physical mapper backend and resident assembly trampoline.

### Bootstrap 0.3.22 — physical ATM2+ W3 page mapper

- Hardware contract verified against the checked-in ATM2+ architecture document and Project127/Project126 reference: hidden dispatcher ports are #3FF7/#7FF7/#BFF7/#FFF7; W3 is #FFF7; RAM page N is selected by writing #7F-N (D6=1 selects RAM, D7=0 avoids the #7FFD low-page mux).
- Shadow ports/DOSEN are opened by the existing UI initialization through the TR-DOS ROM trampoline #3D2F with port #0177, matching Project127/Project126. The RTC GLUK close path also restores this state. The mapper initializes only after UI startup.
- Added a resident assembly OUT backend for W3 only. Transaction commit, rollback, boot restore and nested bank enter/leave now perform the physical #FFF7 write as well as updating the software shadow. W0/W1/W2 are not written by this backend.
- Added a physical page-isolation check: allocate two pages, acquire UI HANDOFF, save two bytes in each page, write distinct patterns, switch back and forth through #FFF7, verify isolation, restore original bytes, return W3 to P0 and release both pages.
- This proves page selection/data isolation only after the user runs the new build and reports `[MAP] PHYSICAL W3 PAGE SWITCH / ISOLATION PASS`. It does not yet implement cross-page copy, stack transfer, resident trampoline execution or banked CALL/RET. The nested bank manager now switches the physical W3 page, but its nested selftest still checks ownership/depth and page restoration rather than executing code from the bank.


### Bootstrap 0.3.23 — physical page-to-page copy

- Added `p129_map_page_copy`, copying between allocated 16 KiB pages through the physical W3 aperture. A 32-byte resident staging buffer maps source and destination sequentially.
- The source remains pinned as the outer bank lease. Each destination chunk is entered as a nested bank, written, then left to restore the source. The outer leave restores P0 and resumes UI.
- Range validation uses widened arithmetic; zero-length copies are accepted; same-page overlapping copies use memmove direction.
- Startup validates a 256-byte copy from the end of one page to another, then validates an overlapping same-page copy.
- This is a page-local copy primitive, not yet a multi-page linear loader, stack transfer, or banked code execution.


### Bootstrap 0.3.24 — multi-page module storage and I/O

- Added a resident page-vector descriptor and allocate/release APIs for modules up to 59 physical pages. Pages are independently allocated; contiguity is not assumed.
- Added bounded 32-bit-offset read/write APIs. Transfers split at every 16 KiB boundary and map each page through W3, returning to the fixed resident window after each chunk.
- Startup allocates a 65,600-byte module, writes and reads 64 bytes straddling the 64 KiB boundary, compares them, and releases the pages.
- This provides multi-page storage and I/O, not yet HDD/FAT16 streaming, stack transfer, or execution of banked code.


### Bootstrap 0.3.25 — FAT16 root-file streaming into banked modules

- Adds a read-only FAT16 file loader for ordinary 8.3 files in the fixed root directory. It rereads and validates the partition BPB, derives FAT/root/data regions, validates FAT16 cluster-count geometry and LBA28/device bounds, locates the requested 11-byte name, and follows the file's cluster chain with a file-size-derived upper bound.
- Each data sector is read by the existing Nemo IDE PIO transport into the resident sector buffer and copied to the allocated module through the multi-page W3 API. The module remains allocated after a successful load; the startup target is root file IO.SYS.
- This milestone does not support subdirectories, long filenames, FAT12/FAT32, writes, or executing the loaded image. Cluster traversal is bounded by the required cluster count and validates each referenced cluster before reading it.
- Build/runtime confirmation is pending. Expected runtime evidence is [HDD] FAT16 FILE LOAD PASS with exact byte size and allocated page count.
