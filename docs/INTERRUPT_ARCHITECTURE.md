# Project129 — ATM Turbo 2+ interrupt architecture

Status: implementation contract and evidence ledger, 2026-11-11.

## 1. CPU-level facts

- Z80 maskable INT is accepted only when IFF1 permits it. IM 1 vectors to 0038h; IM 2 forms a vector-table address from I and the byte supplied on the data bus, then fetches a little-endian handler address.
- Z80 NMI vectors to 0066h and is independent of the maskable INT enable state.
- These CPU rules do not by themselves prove which ATM Turbo 2+ peripherals are wired to INT/NMI, what vector byte they drive, or what memory overlay is switched by NMI.

## 2. Project127 emulator evidence

The read-only Project127 reference has `src/kernel/p127_irq.asm` (module 0.6.0) and `unreal.ini`.

The reference emulator configuration specifies:
- `HIMEM=ATM710`, `RAMSize=1024`;
- `ATMKBD=0` (PC/XT keyboard-controller emulation disabled);
- `[ULA]`: `int=50`, `intlen=32`, `FloatBus=0`, `FloatDOS=0`;
- `PortFF=0`.

Project127's masked IM2 installer consequently uses the deterministic emulator vector byte FFh. It places the 257-byte IM2 reservation in fixed W2/P2 at B000h, sets I=B0h, writes the handler pointer to B0FFh (the word occupies B0FFh/B100h), selects IM2, and deliberately does not execute EI in the installer. The handler is constrained to 8000h..9FFFh in the fixed P2 mapping. The reference code also preserves a host-frame chain through 0038h.

This is evidence for the Project127 + Unreal Speccy configuration, not proof that every physical ATM Turbo 2+ board or peripheral always places FFh on the data bus.

## 3. IM2 table sizing

The Z80 IM2 acknowledge byte is not inherently FFh. If the actual data-bus byte can vary across 00h..FFh, an implementation that promises the same destination for every possible vector must make every indexed word fetch valid, including the boundary case where the low byte is FFh and the second byte is in the next page. A 257-byte filled region is a common safe construction for a repeated-byte trampoline table.

Project129 must not assume that this generic construction is required when its selected emulator/hardware contract guarantees a single vector byte. Conversely, it must not use Project127's single B0FFh slot as a universal physical-hardware assumption without validating the bus/vector contract.

## 4. Fixed-memory and bank-switch safety

- The IM2 table, interrupt entry/exit code, interrupt-owned state, and interrupt stack must remain accessible while any remappable window is changed.
- Project127 uses fixed W2/P2 for the table and handler. Project129 must preserve the same safety property, but its physical page ownership and memory layout must be reconciled with the current allocator before assigning those addresses.
- Bank switching must not occur from the interrupt entry path until a separate design proves stack transfer, mapping restoration, nested entry behavior, and rollback.
- The handler must save the full required register context, including alternate AF and BC/DE/HL banks if the interrupted program may use them. RETI is the exit for a genuine maskable interrupt; a synthetic CALL test is not a substitute for a live interrupt test.
- Do not execute EI as a generic epilogue. The interrupt source acknowledgement, re-entry policy, IFF ownership, and host ISR chaining must be defined first.

## 5. Sources that remain unverified for ATM Turbo 2+

The supplied description mentions a PIT/КР580ВИ53 interrupt source, keyboard-controller interrupts, external ZX-Bus IRQ, and NMI-triggered Shadow ROM switching. These are not yet confirmed by the Project127 emulator configuration or the examined Project127 IRQ module.

In particular:
- Project129's `docs/memory/ec07vi53.htm` describes 8253/8254 timer operation and gives ports for two timers on a sound card. It is not evidence that these ports are the ATM system timer or that a timer output is wired to CPU INT.
- `ATMKBD=0` in the Project127 reference explicitly disables the emulated PC/XT keyboard controller; it cannot validate a keyboard IRQ path.
- Z80 NMI vector 0066h is a CPU fact; automatic ATM Shadow ROM switching on NMI still requires an ATM hardware source/schematic or a verified emulator implementation.
- External bus IRQ wiring and vector/acknowledge behavior also require a hardware-specific source.

Do not invent port addresses, acknowledge sequences, interrupt priorities, or NMI memory-overlay behavior.

## 6. Implementation sequence

1. Keep boot DI-only and IRQ disabled.
2. Define the exact Project129 fixed physical mapping and reserve a stable interrupt table/code/stack region in it.
3. Implement a masked IM2 table/handler installer with explicit vector-source policy; verify the vector fetch word and fixed mapping before committing ownership.
4. Preserve and document any host 0038h frame-service chain required by the selected ATM/Unreal contract.
5. Add register-frame and readiness-gate checks without enabling asynchronous IRQ.
6. Identify each real/emulated source, vector byte, acknowledgement and re-entry behavior from reliable ATM-specific evidence.
7. Run a bounded live frame-INT test, then source-specific timer/keyboard tests. Only enable normal IRQ after the live path, RETI, context, mapping and acknowledgement checks pass.
8. Treat NMI/Shadow ROM as a separate stage; test its mapping/return semantics independently.

## 7. Non-goals for this milestone

No live EI, PIT programming, keyboard IRQ, ZX-Bus IRQ, NMI handler, or Shadow ROM switching is enabled by this document. No IRQ code is copied into Project129 until the fixed-page allocator and bank mapper agree on the permanent resident layout.
