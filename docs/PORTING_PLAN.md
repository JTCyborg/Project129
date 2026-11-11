# Project129 porting plan

## Reference and scope

Behavioral reference: `JTCyborg/Project127`, branch `main`. Project127's source is an ATM Turbo 2+ Z80 assembly implementation. Project129 must preserve its boot sequence, subsystem ordering, device ownership and externally observable behavior while replacing the implementation with Z88DK C and only the assembly glue required by Z88DK/ATM.

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
