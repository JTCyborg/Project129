# Project126 — Overlay / Module Manager

**Revision:** 0.2  
**Date:** 2026-11-08  
**Status:** modular resident/overlay build, host-side X86MODS catalog validation, page-addressed IMAGE ABI 1.1, resident dynamic-page allocator and module registry are implemented and CI-built. Generic dynamic-module IMAGE loading and physical/emulator runtime validation remain open.

## 1. Purpose and size model

The 16 KiB limit applies to one independently mapped physical page, not to the complete x86 implementation. The resident image and each overlay are assembled and packaged separately. The current CI build produces:

| Image | Size | Limit |
|---|---:|---:|
| X86CORE.C resident | 8,507 bytes | 16,384 |
| X86IO.C | 1,878 bytes | 4,096 |
| X86ALU.C | 1,378 bytes | 4,096 |
| X86DEV.C | 3,400 bytes | 4,096 |
| X86EXEC.C | 8,376 bytes | 16,384 |

The total is 23,539 bytes across five images. More overlays can be added without imposing a 16 KiB aggregate-program limit. A single overlay still cannot exceed its independently mapped 16 KiB page.

The build remains a SjASMPlus assembly/link layout with explicit resident and overlay origins. It does not depend on C-style automatic relocation. Resident code and data must stay in the resident image; code/data used by an overlay must be accessed only while that overlay is mapped.

## 2. Physical memory and execution windows

- WIN0/page 00 contains resident code and fixed data.
- WIN1/page 03 contains the operational stack and resident runtime data.
- WIN2 (8000h-BFFFh) is the overlay execution/data aperture, selected through MPAG port 00h.
- WIN3 (C000h-FFFFh) is the banked guest-memory / DMA staging aperture, selected through MPAGEX port 10h. Resident code and stack never execute from WIN3.
- Physical pages 04h, 05h, 06h and 07h are pinned to X86IO, X86ALU, X86DEV and X86EXEC.
- Physical pages 08h-0Fh are the dynamic overlay pool. Pages 00h-03h are never allocator-owned.

The physical page selector for a window is ROR8(physical_page), implemented by one RRCA before writing the corresponding mapping port. WIN2 and WIN3 use different mapping ports; their selector values must not be confused with one another.

## 3. Build manifest and host loader

The build generates `X86MODS.C`, a 39-byte TR-DOS CODE file:

- 7-byte header: magic `P126`, revision 1, record count 4, record size 8;
- four 8-byte records: module ID, physical page, flags, reserved, exact image size (u16 LE), CRC-16/CCITT-FALSE (u16 LE).

The host loader opens and validates the manifest before loading overlays. It validates the header and each record, then checks each staged overlay's ID, physical page, exact byte length and CRC against the manifest before sending IMAGE_BEGIN. A mismatch stops startup before the image transfer.

The host-side descriptor table contains module ID, IMAGE kind, physical page, maximum size, TR-DOS filename and diagnostic stage. The loader iterates this table rather than maintaining four separate startup call sites. The manifest and descriptor page values are cross-checked.

## 4. IPC IMAGE ABI 1.1

ABI 1.1 changes the six-byte IMAGE_BEGIN payload to make the destination explicit:

| Offset | Field | Size |
|---|---|---:|
| 0 | transaction/message ID | 2 |
| 2 | image kind | 1 |
| 3 | physical destination page | 1 |
| 4 | exact image size | 2 |

The ATM host supplies the page from its module descriptor. The NeoGS receiver validates the allowed kind/page combination and derives the WIN3/MPAGEX selector from the physical page using RRCA. It no longer chooses a WIN3 selector directly from a hard-coded per-kind selector constant.

Current profiles remain pinned:
- SYSBIOS kind 00h -> page 10h, exactly 8 KiB;
- X86IO kind 01h -> page 04h;
- X86ALU kind 02h -> page 05h;
- X86DEV kind 03h -> page 06h;
- X86EXEC kind 04h -> page 07h.

The host and receiver use the same ABI minor version. The selected SYSBIOS loader also sends page 10h explicitly.

The receiver stages the fragment in physical page 42h, copies it through WIN3 to the selected target page, reads every installed byte back against the staging source, and only then accepts IMAGE_FINISH. Current overlays are sent as one fragment. Since the IPC frame is 16 KiB and the fragment has an 18-byte IPC header plus a 10-byte extension, one fragment can carry at most 16,356 image bytes. A full 16,384-byte module requires multi-fragment streaming; this is not yet implemented in the ATM fixed-profile loader.

## 5. Resident allocator and module registry

The resident WIN2 call gate is in `neogs_sub/p126_overlay_gate.asm`. It switches WIN2 to the requested overlay, calls the IX entry, and restores the previous selector at a resident RET trampoline. It supports up to eight nested calls and protects active/current pages from release.

The allocator owns pages 08h-0Fh and provides first-fit allocation and guarded release. The module registry now adds:
- IDs 01h-04h: fixed mappings to pages 04h-07h;
- IDs 05h-0Fh: dynamic mappings to pages 08h-0Fh;
- `p126_overlay_register_dynamic`: atomically claims a specified free dynamic page and registers the ID;
- `p126_overlay_unregister_dynamic`: releases the page only when it is neither current nor active, then clears the registry entry;
- `p126_overlay_call_module`: resolves a loaded module ID to its physical page, derives the WIN2 selector, and enters through the existing call gate.

Resident startup runs both allocator and module-registry self-tests. The registry is a resident API and data structure; the generic IMAGE kind/manifest-to-registry installation path is the next integration step. The current four packaged images still use their pinned profiles.

A module entry must be in the 8000h-BFFFh aperture and must be a valid exported entry for that module. The low-level gate accepts IX; callers of the higher-level registry API must pass only validated entry points. No pointer into WIN2 may be retained across a call that can remap WIN2.

## 6. Current validation state

Latest CI build: [run 42475417807](https://github.com/JTCyborg/Project126/actions/runs/42475417807), commit `85232bed2e12a12e5e9de15dcda2d6a5a0f7c153`. SjASMPlus reports zero errors and zero warnings. The build emits the five image sizes listed above.

CI validates assembly, image sizes, manifest generation, disk packaging and publication. It does not prove that the runtime self-tests pass in the emulator or on physical hardware. That requires a fresh Project126 disk run and inspection of the resulting `spectrum_out.txt`/resident log.

## 7. Remaining implementation gates

- [x] Remove the aggregate 16 KiB program-size assumption; build resident and overlay images independently.
- [x] Keep the resident image and each overlay within their own page limits.
- [x] Generate and parse the X86MODS catalog; verify overlay size and CRC before IMAGE_BEGIN.
- [x] Iterate host module descriptors through one shared loader.
- [x] Pass the physical destination page in IMAGE_BEGIN ABI 1.1 and derive the WIN3 selector from it.
- [x] Preserve SYSBIOS page 10h semantics under ABI 1.1.
- [x] Implement dynamic page allocation, registration, lookup/call and guarded unregister in the resident module registry.
- [x] Run allocator and registry self-tests during resident startup.
- [ ] Add a generic overlay IMAGE kind and connect manifest module IDs to dynamic registry registration.
- [ ] Add multi-fragment streaming so an image can use the full 16 KiB physical page.
- [ ] Validate exported entry offsets and module bounds before indirect calls.
- [ ] Confirm startup allocator/registry self-tests and overlay transfers in a fresh emulator run.
- [ ] Confirm the same behavior on physical hardware.

Do not add new device models to the resident image merely to grow functionality. Keep device implementations in independent overlays and keep all external-world exchange behind the established ATM/NeoGS DMA/IPC boundary.
