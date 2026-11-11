# Project126 — ATM-PC/XT hybrid machine profile

**Profile ID:** P126-ATMPC-XT-HYBRID-0.1  
**Status:** initial guest memory and I/O decode contract; PPI and PIC register-level slices are implemented, while IRQ delivery and other device models remain pending.

## 1. Selected compatibility model

Project126 uses a custom ATM-PC board profile with an Intel 8086 in Real Mode and a 20-bit address bus. It adopts IBM PC/XT-style system interfaces where they improve compatibility, but it is not a claim of complete IBM PC/XT hardware compatibility.

The machine has a full 1 MiB guest physical RAM backing store in NeoGS. VGA and ROM decode windows overlay that backing store. The address map is deliberately not the conventional 640 KiB RAM plus permanently lost UMA layout: 216 KiB of RAM remains available above the VGA BIOS window.

The CPU semantics remain tied to the pinned PCem 8086 reference. PCem device models are behavioral references, not code to be copied wholesale into the NeoGS firmware.

## 2. Guest physical memory map

All ranges are half-open. Physical addresses are 20-bit and wrap at 1 MiB, as required by the 8086 bus. There is no A20 gate.

| Guest address range | Size | Read path | Write path | Notes |
|---|---:|---|---|---|
| 00000–9FFFF | 640 KiB | Guest RAM | Guest RAM | Low RAM, includes IVT and BIOS Data Area. |
| A0000–BFFFF | 128 KiB | VGA aperture | VGA aperture | VGA memory window. VGA Graphics Controller selects the effective aperture; 256 KiB VRAM is separate backing storage. |
| C0000–C7FFF | 32 KiB | VGA BIOS ROM | Ignored / no-op | Separate VGA BIOS image, independent from system BIOS limit. |
| C8000–FDFFF | 216 KiB | Guest RAM | Guest RAM | Custom upper RAM extension; unlike conventional PC UMA this region is not globally reserved for option ROMs. |
| FE000–FFFFF | 8 KiB | System BIOS ROM | Ignored / no-op | Initial 8 KiB XT-compatible ROM window; contains reset vector at physical FFFF0. |

Totals: 1,024 KiB guest address space; 856 KiB guest RAM exposed at reset; 128 KiB VGA aperture; 32 KiB VGA BIOS; 8 KiB system BIOS boot window. The entire 1 MiB is backed by the separate 1 MiB NeoGS guest-RAM allocation; ROM/VGA overlays take priority over RAM on reads and suppress ordinary RAM writes while enabled.

### BIOS capacity versus visible reset window

The architecture retains a maximum system BIOS image size of 256 KiB, stored in the independent 256 KiB NeoGS system-BIOS slot. The initial XT BIOS images supplied with Project126 are 8 KiB ROMs and are mapped at FE000–FFFFF, matching the ORG 0E000h / 8 KiB layout documented in bios/bios.asm. The reset instruction fetch at FFFF0 therefore resolves to offset 1FF0 within the selected 8 KiB image.

A future BIOS image larger than 8 KiB requires an explicit ROM-window/banking policy before it can be declared bootable. The 256 KiB storage limit must not be misrepresented as a 256 KiB linear guest-visible ROM window. No banking register or runtime bank switch is assigned by this revision.

### ROM priority and write behavior

1. System BIOS overlay FE000–FFFFF has priority over RAM.
2. VGA BIOS overlay C0000–C7FFF has priority over RAM.
3. VGA aperture A0000–BFFFF routes to VGA, not guest RAM.
4. All other addresses route to guest RAM.
5. BIOS writes do not modify the hidden RAM backing while the ROM overlay is active. A future shadow-RAM feature requires an explicit control bit and cache/invalidation rules.

## 3. VGA memory and I/O

The initial VGA memory aperture is A0000–BFFFF (128 KiB maximum CPU-visible window). The adapter owns 256 KiB VRAM. The actual active aperture and bank mapping are controlled by VGA registers; the decoder must follow PCem vid_vga.c and vid_svga.c, including Graphics Controller register 6 mapping choices. The 128 KiB guest window is not a declaration that all 256 KiB VRAM is linearly visible at once.

VGA I/O decode:
- 3C0–3CF: Attribute Controller, Sequencer, DAC and Graphics Controller.
- 3B0–3BF: monochrome CRTC/status aliases.
- 3D0–3DF: color CRTC/status aliases.
- The active CRTC base follows the VGA Miscellaneous Output register, as in PCem vga_in() / vga_out().

The VGA BIOS guest ROM window is C0000–C7FFF (32 KiB), matching the PCem IBM VGA device's rom_init(..., 0xc0000, 0x8000, ...) placement.

## 4. System-board I/O decode

The profile reserves the following PC/XT-style interfaces. They are guest-visible software devices on NeoGS. Any request requiring a physical resource is forwarded to ATM only through the unified DMA/IPC ABI 1.0.

| Port range | Model / purpose | Status |
|---|---|---|
| 0000–000F | 8237-compatible DMA controller | X86DEV/page06 partial register model: address/count, command/status/request/mask/mode and byte flip-flop; transfer engine pending |
| 0020–0021 | 8259-compatible master PIC | X86IO/page04 partial model: ICW/OCW, IMR/IRR/ISR, fixed-priority arbitration, keyboard IRQ1 and CPU acknowledge; PIT IRQ0 pending |
| 0040–0043 | 8253-compatible PIT | X86DEV/page06 static register model: channel reload/latch, access modes and byte sequencing; clock/output/IRQ0 pending |
| 0060–0063 | 8255-compatible PPI / XT keyboard and system control | X86IO/page04 initial XT model: keyboard FIFO, PPI mode 0, port B reset/ack; ATM keyboard event producer pending |
| 0070–0071 | DS12887-compatible RTC/CMOS extension | Custom ATM-PC extension; time source is ATM; guest register model pending |
| 0080–0083 | DMA page registers | X86DEV/page06 partial register model: channel page latches |
| 00E0 | Project126 diagnostic latch | Implemented 16-bit read/write test latch; not a PC hardware device |
| 00A0, 0213 | Generic Turbo XT BIOS board-control ports | X86DEV/page06 static latches: NMI gate state and expansion-unit enable state; no actual NMI delivery or expansion hardware |
| 01F0–01F7, 03F6 | Primary ATA-compatible guest disk task file/control | Software device architecture reserved; task-file/IPC service pending |
| 03B0–03DF | IBM VGA/CGA/MDA register interfaces | 03B8h/03D8h static mode latches implemented in X86DEV; CRTC registers, status/retrace and rendering pending |
| 03F0–03F5, 03F7 | 765-compatible floppy controller (3F7 status/direction) | Reserved; floppy service remains a separate device decision |
| 03F8–03FF, 02F8–02FF | 8250-compatible COM1/COM2 UARTs | BIOS2 source probes these UARTs; guest UART model/ATM serial bridge pending |
| 03BC, 0378, 0278 | Parallel printer ports | BIOS2 source probes three possible LPT bases; guest printer service pending |
| 00C0 | Legacy data-bus test latch | X86DEV/page06 read/write latch; does not emulate a physical bus |
| 0201 | Game controller port | BIOS2 source probes joystick bits; guest model pending |
| 0241, 0341 | Optional board timer probes | BIOS2 source probes optional BCD timers; behavior not modeled |
| 03D8, 03B8 | CGA/MDA mode-control ports | X86DEV/page06 static mode latches; CGA/MDA rendering and retrace status pending |

Port 03F6 is assigned to the ATA control register and is intentionally excluded from the floppy-controller register set (the legacy PC/XT decode shares this neighborhood). The RTC ports are a deliberate custom extension; the physical DS12887/time source remains on ATM. This does not grant NeoGS direct access to a physical RTC.

The source file `bios/bios.txt` documents a Generic Turbo XT BIOS for 8088/V20 systems and is associated with the BIOS2 family, not proven byte-for-byte equivalent to the currently selected BIOS1 image. Its startup code is useful as a reference for the extra board-control, video, UART, printer, joystick and optional timer probes above; do not assume BIOS1 executes every one of these paths. The current BIOS1 watchdog trace at F000:E06E is a table-driven port/value writer with DX high byte E6h. Its actual DS:SI table contents still require the wired watchdog memory dump to be observed; the 16:46 spectrum_out.txt predates that diagnostic build.

Unknown or unimplemented guest ports return FFh on reads and ignore writes in this initial profile. They must never be forwarded as physical NeoGS port operations.

## 5. BIOS images currently packaged

The TR-DOS image builder includes three 8 KiB system BIOS choices:
- BIOS1.C — source bios/27c64d.bin.
- BIOS2.C — source bios/Bios.bin; the associated source bios/bios.asm identifies this family as a Generic Turbo XT BIOS for 8088/V20-compatible systems and documents an 8 KiB image at the top of the F000 segment.
- COMPAQ.C — source bios/Compaq Portable Plus 100666-001 Rev C.bin; machine-specific assumptions may differ from the generic XT profile.

Each packaged image is currently required by the build to be exactly 8192 bytes. This profile defines the intended guest placement, not successful POST/boot for every image. Compaq-specific hardware services and all BIOS boot paths still require runtime compatibility testing.

VGA BIOS is a separate image and is not one of these three system BIOS choices. Its file source and guest image contents are not yet staged in the TR-DOS catalog.

## 6. PCem comparison points

- CPU reset and 20-bit address behavior: PCem/808x.c, PCem/cpu.h.
- Memory mapping and read/write dispatch: PCem/mem.c, PCem/mem.h.
- IBM VGA ROM and aperture setup: PCem/vid_vga.c (vga_init(), rom_init).
- VGA aperture mapping: PCem/vid_svga.c (Graphics Controller register 6 handling).
- VGA register dispatch: PCem/vid_vga.c (vga_in(), vga_out()).

## 7. Explicitly not implemented by this profile document

- Runtime RAM/ROM/VGA read and write handlers.
- VGA register/plane/latch implementation and renderer.
- VGA/RTC/IDE/FDC device emulation; PIT clock decrement/output/IRQ0; DMA transfer engine and FDC/IDE request service; complete PPI/keyboard electrical behavior.
- Guest BIOS banking for images larger than 8 KiB.
- ATM-side physical I/O request service handlers.
- BIOS POST/boot validation on NeoGS.

A source-level address map and compile-time assertions are not BUILD/EMULATOR/HARDWARE PASS for those runtime components.



### X86DEV overlay (physical page 06h)

The 8237 DMA, 8253 PIT and XT board-control register models have been split from X86IO into a fixed-origin overlay on physical page06 (WIN2 selector03h). X86IO delegates ports through resident nested overlay wrappers. ATM loads `X86DEV.C` from TR-DOS after X86ALU; the NeoGS IMAGE service validates and reads back the image, calls its reset/self-test entry through the overlay gate, and publishes `X86DEV_READY` only after the signature and return mapping checks succeed. The board-control self-test covers 00A0h, 0213h, 00C0h, 03B8h and 03D8h latches. The resident CPU/BIOS readiness gate now requires X86IO, X86ALU, X86DEV and SYSBIOS.

The dynamic page allocator now reserves page06 for X86DEV and allocates only pages07h–0Fh (nine pages). The allocator regression was updated to check all nine pages and page07 first-fit reuse.

### PIT 8253 register-model status

A static 8253 programming/readback slice is implemented for ports 0040h–0043h:
- Three channel reload registers, LSB-only/MSB-only/LSB+MSB access modes, shared per-channel read/write sequencing, and count-latch commands.
- Control-word channel selection, mode storage (including mode 6/7 aliases to 2/3), and BCD flag storage.
- Reset-time self-test checks channel 0 reload=1234h, low/high readback and count-latch readback, plus channel 1 LSB-only programming/readback.
- Still pending: decrementing counters, clock source/divisor timing, output pin states, speaker integration and IRQ0 generation. This is a register-file model, not a functioning timer.

### DMA 8237 register-model status

A register-level 8237-compatible controller slice is implemented in `neogs_sub/x86_io.asm`:
- Ports 00h–07h: four channel address/count pairs with the shared low/high-byte flip-flop.
- Ports 08h–0Fh: status/terminal-count read, command, software request, single-channel mask, mode, clear flip-flop, master clear, clear mask and all-mask write.
- Ports 80h–83h: channel page registers.
- Reset-time self-test checks channel 0 address=1234h and count=5678h low/high programming/readback, channel 1 page register 81h, channel 2 mask/unmask commands and master-clear state.
- Still pending: DMA bus transfer engine, channel arbitration/DRQ from devices, terminal-count generation, auto-initialize, memory-to-memory mode, FDC/IDE integration and forwarding transfer requests through DMA/IPC. This is not yet a functioning disk DMA path.

### PIC 8259A master register-model status

The first master-PIC register slice is implemented in `neogs_sub/x86_io.asm` for ports 0020h–0021h:
- Command port 20h: ICW1 initialization, OCW3 IRR/ISR read selection, non-specific EOI and specific EOI.
- Data port 21h: ICW2 vector-base programming, ICW3/ICW4 sequence consumption, and IMR read/write.
- Reset state: vector base 08h, IMR=FFh, IRR=00h, ISR=00h. A reset-time register self-test checks ICW1/2/4 sequencing, IMR readback, OCW3 IRR/ISR selection, and specific/non-specific EOI, then restores this reset state.
- Implemented: fixed-priority IRR/IMR arbitration, keyboard FIFO IRQ1 request, CPU-boundary PIC acknowledge, ISR transition and EOI release. A reset-time self-test exercises ICW1/2/4, IMR readback, OCW3 IRR/ISR selection, IRQ1 vector/acknowledge and specific/non-specific EOI.
- Still pending: PIT-driven IRQ0, ATM-side keyboard event producer over DMA/IPC, priority rotation, auto-EOI, full cascade and special-mask behavior. This is not a complete 8259A or BIOS POST pass.

### PPI / XT keyboard implementation status

The initial runtime slice is being added in neogs_sub/x86_io.asm for ports 0060h–0063h:
- 60h: PPI port A / keyboard scan-code FIFO consumer (XT input behavior; generic output-latch mode is not yet complete).
- 61h: PPI port B / system-control latch, including PB6 rising-edge XT keyboard reset and PB7 data acknowledge (PB input-mode behavior remains incomplete).
- 62h: PPI port C input/output composition; board configuration input is a deterministic profile value pending explicit ATM-PC switch definition.
- 63h: PPI mode-set and bit-set/reset control register.
- Initial BIOS mode-0 control word is 99h. PPI mode 1/2 handshake modes and board-specific port-C switch wiring are outside this first slice.
- Keyboard scan-code production is exposed as a software API for the future DMA/IPC input service. Each accepted FIFO byte now raises virtual PIC IRQ1; the CPU interrupt boundary acknowledges it through the PIC and the handler can consume port 60h. The ATM-side keyboard event producer over DMA/IPC remains unimplemented.
