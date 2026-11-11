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

A dependency-driven reorder requires a recorded reason and an explicit interface impact review.

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
