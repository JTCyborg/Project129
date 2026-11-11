# Project126 — ATM host module and program interface

## 1. Responsibility boundary

The ATM Turbo 2+ host Z80 (7 MHz) owns physical hardware and host-side services: physical keyboard input, TR-DOS and storage access, RTC/time source, and final display output. The NeoGS Z80 (240 MHz) owns the x86 machine, virtual devices, VGA emulation and frame rendering.

The ATM module is a transport/host-services layer. It must not contain x86 CPU execution or VGA rendering. NeoGS has no direct physical-device access; requests for host resources cross this interface.

ATM and NeoGS retain independent debug channels at port #EF.

## 2. Source modules

- `atm_host/neogs_ipc.inc` — public port definitions and calling convention.
- `atm_host/neogs_ipc.asm` — ATM-side IPC transport driver.
- `atm_host/neogs_ipc_assemble.asm` — relocatable assembly unit and placement labels.
- `build/ATM_IPC.bin` — assembled ATM transport module.
- `build/ATM.lst`, `build/ATM.map` — listing and symbol/address map.
- `shared/p126_ipc_protocol.inc` — shared DMA/IPC ABI constants imported by both processors.
- `neogs_sub/p126_ipc.asm` and `neogs_sub/p126_ipc_assemble.asm` — NeoGS-side CRC primitive and independent assembly/audit unit.
- `build/P126_NGS_IPC.bin`, `build/NEOGS_IPC.lst`, `build/NEOGS_IPC.map` — NeoGS IPC primitive build products.

The current assembly origin is `ORG 0000h`, used only to produce auditable image-relative offsets. It does not assign a final physical ATM load address. That address depends on the ATM memory map and integration with the TR-DOS/host program, which are not yet fixed.

## 3. Physical IPC transport

The driver uses the documented Spectrum/ATM-facing NeoGS ports:

| Port | Direction from ATM | Meaning |
|---|---|---|
| #BB | OUT | GSCOM command; sets CBIT |
| #BB | IN | GSSTAT; CBIT is bit 0, DBIT is bit 7 |
| #B3 | OUT | GSDAT host-to-NeoGS byte |
| #B3 | IN | GSDAT NeoGS-to-host byte |
| #33 | OUT | GSCTR control; not used by this driver |

The handshake follows the established Project125 host transport v2 implementation:

- A command is written to #BB; the caller waits until CBIT clears.
- A host data byte is written to #B3 only when DBIT is clear; the sender waits until DBIT clears again before considering the byte consumed.
- A byte from NeoGS is read only after DBIT becomes set. Reading #B3 acknowledges/consumes the published byte.
- CBIT and DBIT are independent signals and must never be substituted for one another.
- Every wait is bounded by a 16-bit polling timeout. A timeout is reported with Carry set; the last GSSTAT sample remains available in `p126_ipc_last_status`.

The driver does not issue a hardware reset automatically. Reset ownership and recovery policy belong to the system startup state machine.

## 4. Public Z80 calling convention

All entry points are callable with `CALL`. The module is assembled as a relocatable byte image; after integration, callers use the linked labels.

| Entry point | Input | Output |
|---|---|---|
| `p126_ipc_read_status` | — | A=status; updates last status |
| `p126_ipc_wait_cbit_clear` | — | Carry clear when CBIT=0; set on timeout; A=last status |
| `p126_ipc_wait_dbit_clear` | — | Carry clear when DBIT=0; set on timeout; A=last status |
| `p126_ipc_wait_dbit_set` | — | Carry clear when DBIT=1; set on timeout; A=last status |
| `p126_ipc_send_command` | A=command | Waits for CBIT clear |
| `p126_ipc_send_argument` | A=argument | Preloads GSDAT before command dispatch; intended for legacy GS105a #13/#14 ABI |
| `p126_ipc_send_byte` | A=data | Sends one byte and waits for DBIT clear |
| `p126_ipc_receive_byte` | — | A=data after DBIT set and GSDAT read |
| `p126_ipc_emit_version` | — | Writes `[P126 ATM_IPC v0.1.0]` to ATM #EF; preserves AF/BC/HL |

Wait routines clobber BC. The byte routines use private module storage and are not re-entrant; only one ATM caller may use the transport at a time. The caller must serialize transactions.

## 5. Unified DMA/IPC application protocol

The normative ABI is specified in [P126_DMA_IPC_PROTOCOL.md](P126_DMA_IPC_PROTOCOL.md), version 1.0. All application payloads use the same framed ZX DMA transport. GSCOM/CBIT is the control-plane doorbell and READY/end handshake; DBIT/GSDAT remains only a low-level compatibility primitive for stock-ROM/bootstrap work and is not an application payload channel.

The ATM and NeoGS modules import common constants from `shared/p126_ipc_protocol.inc`. The common definitions include frame layout, message types, flags, service IDs, status codes, control command IDs and CRC parameters. CRC-16/CCITT-FALSE byte-update and standard 123456789 → 29B1h self-test routines now exist on both processors (`atm_host/neogs_ipc.asm` and `neogs_sub/p126_ipc.asm`).

The current ATM driver still does not implement complete frame send/receive, DMA-window transfers, sequence/session handling or error recovery. The NeoGS endpoint, staging buffers and final ATM/NeoGS memory placement are not implemented. In particular, ATM code must never access NeoGS-local DMA ports #1B..#1F.

## 6. Version and verification

- ATM source version: `P126 ATM_IPC v0.2.0`; shared application ABI: `P126 DMA/IPC ABI 1.0`.
- The assembly unit continues to generate `build/ATM_IPC.bin`, `build/ATM.lst` and `build/ATM.map`.
- The CRC self-tests are present as executable code on both processors but are not yet called by startup and have not been run on target hardware.
- **BUILD PASS for the dual-endpoint CRC primitives:** GitHub Actions run [42303465405](https://github.com/JTCyborg/Project126/actions/runs/42303465405), commit `50bf91bf35a0ef89e5d5ebb128fb36b46ceac479`; ATM IPC, NeoGS IPC and x86 modules assembled, and TR-DOS packaging completed successfully.
- Assembly success will prove syntax and image-boundary assertions only; live DMA/IPC requires separate deterministic hardware tests.


## 7. TR-DOS disk image and boot chain

The Project126 build now creates a standard 80-track, 2-side, 16-sector TR-DOS image named `disk_A.trd` (655,360 bytes), both at the repository root and as `build/disk_A.trd`.

The image is assembled using SjASMPlus `EMPTYTRD` and `SAVETRD`, following the Project125 disk-image workflow. Its required directory entries are:

- `BOOT.B` — BASIC boot program adapted from the working Project125 loader. It preserves the TR-DOS startup trampoline, the `CLEAR 24000` barrier, loads `PROJ126.C` at address 24576 and transfers control to 24585.
- `PROJ126.C` — ATM host application at 6000h. It emits its own version and the ATM IPC module version to the independent ATM debug port #EF, then remains in a HALT loop.
- `X86CORE.C` — current assembled x86 CPU-state/ALU module, stored as a separate TR-DOS CODE file.

The host application is an initial bootable shell. It does not yet read `X86CORE.C`, upload it to NeoGS, or start an x86 executor. That requires the NeoGS-side resident receiver and a defined launch protocol, neither of which is represented as complete by this disk packaging step.

The build validates the 655,360-byte image and checks that all three directory entries exist with non-zero length and sector allocation. It produces `build/ATM_DISK.lst` and `build/ATM_DISK.map` for source/address auditing. CI build PASS: run `42275327342` (commit `79b28a4266fdb3cdd151b7842d0b78ed73e5d2c4`), 436 disk-assembly lines, 0 errors and 0 warnings. The image contains BOOT.B (475 bytes / 2 sectors), PROJ126.C (248 bytes / 1 sector), and X86CORE.C (1,155 bytes / 5 sectors). [Download disk image and build artifacts](https://github.com/JTCyborg/Project126/actions/runs/42275327342).
