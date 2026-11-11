# Project126 — PCem reference map

## Pinned reference snapshot

The `PCem/` directory is a reference snapshot, not the Project126 runtime.

- Reference tree: `6e2021e66d6be53f6cadf168f56da2062e91455a`
- Source repository used for comparison: `JTCyborg/Project124/PCem`
- Project126 CPU target: Intel 8086, Real Mode, 20-bit physical address bus.
- The reference contains implementations for many CPU generations and PC configurations. Project126 must select and adapt only behavior relevant to the agreed 8086 machine profile.

The exact Git blob IDs of the primary reference files are enforced by `tools/verify_pcem_reference.py`. Updating the PCem snapshot is a deliberate reference-baseline change and must update that manifest in the same reviewed commit.

## CPU and execution

| Project126 subsystem | PCem reference | What must be compared |
|---|---|---|
| 8086 instruction execution | `PCem/808x.c` | Opcode behavior, execution order, instruction side effects, 8086-specific behavior |
| Opcode operation helpers | `PCem/x86_ops.h` and related `x86_ops*` files | Arithmetic, logic, flags, operand widths and shared instruction semantics |
| CPU model selection/state | `PCem/cpu.h` | 8086 vs 8088 selection and CPU state assumptions; do not import 286+ behavior |
| Memory access integration | `PCem/mem.c`, `PCem/mem.h` | Byte/word access semantics, mapping boundaries, ROM/RAM dispatch and side effects |
| Port dispatch | `PCem/io.c`, `PCem/io.h` | Width, address and device-dispatch semantics for guest IN/OUT |
| Interrupt controller | `PCem/pic.c` | Interrupt request, mask, priority and acknowledge behavior |
| Timer/event source | `PCem/timer.c` | Event scheduling and timing interactions relevant to the selected machine profile |
| Keyboard model | `PCem/keyboard.c` | Guest-visible keyboard/controller behavior, not host UI implementation |

## VGA and video compatibility

| Project126 subsystem | PCem reference | What must be compared |
|---|---|---|
| VGA adapter integration | `PCem/vid_vga.c`, `PCem/vid_vga.h` | VGA port decode, register integration, BIOS ROM and adapter lifecycle |
| VGA core | `PCem/vid_svga.c`, `PCem/vid_svga.h` | Sequencer, Graphics Controller, Attribute Controller, CRTC, latches, planes and aperture behavior |
| VGA rendering | `PCem/vid_svga_render.c` | Text and graphics scanout, planar/packed addressing, palette and pixel generation |
| CGA compatibility behavior | `PCem/vid_cga.c` | CGA-compatible register and rendering behavior inside the VGA compatibility target |
| EGA compatibility behavior | `PCem/vid_ega.c` | EGA-compatible register and rendering behavior inside the VGA compatibility target |

Project126 has one mandatory VGA adapter with CGA/EGA compatibility inside that model. The presence of standalone CGA/EGA implementations in PCem does not authorize adding separate guest adapters to the initial Project126 configuration.

## Porting rules

1. PCem is the behavioral and architectural reference. It is not assumed to be directly buildable as the NeoGS firmware.
2. The target implementation must respect the Project126 execution platform and resource limits. Host-specific PCem UI, SDL, operating-system, file-system and native-host memory mechanisms are not to be transplanted into NeoGS.
3. The guest CPU remains Intel 8086 Real Mode. Do not introduce 80186, 286, protected-mode, A20-gate or later-CPU requirements.
4. The guest has its own 1 MiB address space. Do not silently substitute PCem's selected machine RAM layout or the classic 640 KiB + UMA assumption.
5. Every implemented component must name the PCem source files/functions used for comparison. Any intentional behavioral divergence must have a written reason and a regression test.
6. An opcode is not considered implemented merely because a dispatch case exists. Operand decoding, memory side effects, flags, control flow, interrupt behavior and boundary cases must be checked.
7. VGA correctness must be tested through guest-visible registers and rendered output, not merely by confirming writes to VRAM.

## Current repository baseline

At the time this reference map was added, Project126 contained the PCem reference tree and architecture documentation, but did not yet contain a Project126 NeoGS runtime, build target or executable regression harness. The reference files must therefore not be mistaken for an already integrated x86 emulator.

## Required audit output

For each CPU/VGA implementation milestone, record:

- Project126 source file and component version.
- PCem source file(s) and relevant function(s)/code path(s).
- Supported opcode, register, mode or device behavior.
- Regression test identifier and observed result.
- Any known divergence and why it is required by Project126.
- Build ID/commit of the exact firmware that produced the diagnostic log.
