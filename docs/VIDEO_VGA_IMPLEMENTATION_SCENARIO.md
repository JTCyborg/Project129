# Project126 — VGA and ATM frame pipeline implementation scenario

Revision 0.1. Status: implementation plan and staged work baseline.
Behavioral reference: Project126/PCem only. Project125 is explicitly excluded as a source of VGA code or behavior.

## 1. Fixed architecture

- One IBM-compatible VGA adapter, including its CGA/EGA compatibility modes. No separate CGA/MDA device.
- Exactly 256 KiB VGA VRAM: NeoGS physical pages 30h–3Fh (0C0000h–0FFFFFh).
- Guest VGA aperture: A0000h–BFFFFh. The guest memory dispatcher now routes A0000h–BFFFFh through the X86VGA module; the module applies the active GDC[6] aperture map and VGA plane semantics.
- VGA BIOS storage remains separate at pages 20h–2Fh; guest option-ROM window C0000h–C7FFFh.
- Optional large-frame workspace: pages40h–41h, up to 32 KiB for ATM formats larger than one DMA staging page.
- Production DMA staging: page42h, 16 KiB. The current RG6 converter writes its complete 4 KiB frame directly after the ABI header in this page. Larger future formats use pages40h–41h as a conversion workspace and copy chunks through page42h. IPC/session scratch: page43h.
- ATM is the owner of physical hardware. All guest x86 ports are software models; all NeoGS↔ATM exchange uses DMA/IPC.

## 2. Source-of-truth PCem paths

- PCem/vid_vga.c and vid_vga.h: VGA adapter setup, port decode, CRTC mono/colour aliasing and 256 KiB allocation.
- PCem/vid_svga.c and vid_svga.h: Attribute Controller, Sequencer, Graphics Controller, CRTC, DAC, latches, plane masks, aperture mapping and banking.
- PCem/vid_svga_render.c and vid_svga_render.h: text/graphics scanout, planar/packed decoding, palette and pixel generation.

Do not port host-only SDL, Allegro, OS timers, native windowing, host memory mapping or file APIs. Preserve guest-visible behavior using deterministic Project126 state.

## 3. Responsibility split

### VGA core on NeoGS

Owns guest VGA registers, port decode, 256 KiB VRAM, aperture semantics, latches/planes, mode state and scanout. The x86_cpu_state.asm memory dispatcher routes the VGA aperture to X86VGA; VGA behavior belongs in that module, not in a linear memory-page mapping.

### ATM frame converter on NeoGS

- Reads VGA state and VRAM through the VGA module API, never as an assumed linear bitmap.
- Decodes VGA mode, geometry, pitch, start address, panning, palette and text/planar/packed layout.
- Consumes a versioned ATM mode descriptor delivered by the host. It must not infer ATM mode from VGA registers.
- Converts to the exact active ATM memory layout and emits the mode-specific frame size, up to 32768 bytes.
- Writes the complete converted frame to pages40h–41h. Publish it only after conversion completes; do not modify the frame while DMA is transmitting it.
- Defines deterministic scaling/colour policy for any VGA mode not natively representable by the selected ATM mode.

### ATM host and frame service

ATM reports its current mode and accepts the finished frame. NeoGS video service owns scheduling, frame ownership, fragmentation and DMA/IPC. ATM host applies a frame to the active ATM video-memory layout only after complete reassembly and validation.

## 4. Transport contract

The DMA aperture is 16 KiB including the 18-byte ABI header; a regular ABI frame carries at most 16366 payload bytes. The 16 KiB page42h staging buffer is a transport chunk, not the maximum logical frame size.

Use the existing ordered ABI 1.1 fragmentation extension: 10-byte fragment extension, at most 16356 bytes of frame data per fragment, individual CRC-16/CCITT-FALSE validation, common frame/message ID and ordered reassembly. Keep page42h as the 16 KiB DMA staging page and page43h as scratch. The current 4 KiB RG6 frame fits in one reverse-DMA transfer; a maximum 32 KiB future frame requires three fragments. On timeout, missing fragment, sequence error or CRC failure, reject the frame.

## 5. Implementation stages

### Stage 0 — baseline audit
Record PCem references and the existing physical allocations. Preserve the BIOS2 INT CD stop point and do not modify CPU/IVT code as part of video work.

### Stage 1 — VGA register and port core
Implement PCem-compatible port decode, mono/colour CRTC alias selection, Attribute Controller flip-flop, Sequencer, Graphics Controller, CRTC protection, DAC index/data and status-read side effects. Add deterministic register tests.

### Stage 2 — VGA memory semantics
Replace linear A0000h–BFFFFh staging with map select, chain-4/chain-2, plane selection, latches, read modes 0/1, write modes 0–3, rotate, set/reset, logical operation, bit mask and map mask. Verify all four planes independently.

### Stage 3 — VGA scanout
The first text-mode capture path now reads VGA character/attribute cells using PCem CRTC MA/start/stride rules and preserves the VGA latches. Full pixel scanout remains: port planar 4-bpp and packed 8-bpp rendering, then add cursor/blink, panning, palette and deterministic graphics patterns.

### Stage 4 — ATM mode descriptor and converter
The host now publishes a versioned descriptor for its current RG6 80x25 text mode. X86VID validates that descriptor and converts a VGA text screen to a compact 4000-byte character/attribute frame. Other ATM layouts and VGA graphics-to-ATM conversion remain future work.

### Stage 5 — frame transfer and DMA/IPC
The current RG6 frame is written directly after the 18-byte header in page42h, then sent as a fixed 16 KiB reverse-DMA response with CRC validation. The ATM host validates the VIDEO response and copies the 4000-byte payload into the active page7/page3 text layout. After the first valid frame, the host idle loop requests refreshes every 64 iterations; one failed refresh disables polling to avoid log/transport floods. This is loop-paced rather than synchronized to VGA/ATM vertical blank. Pages40h–41h are reserved for future larger frame formats; fragmented transfers are still required for those modes.

### Stage 6 — BIOS and end-to-end tests
Run BIOS2 INT 10h text/graphics paths. Validate guest register access, aperture, scanout, ATM conversion, reassembly and final ATM placement. Keep the current BIOS2 INT CD stop point unchanged.

## 6. Acceptance criteria

- Exactly 262144 bytes of VRAM; all four planes pass read/write/latch tests.
- Implemented VGA register behavior matches the corresponding PCem paths.
- BIOS2 INT 10h text and supported graphics tests produce expected VGA scanout.
- Current RG6 text conversion produces exactly 4000 deterministic bytes; future ATM modes must define and test their own output lengths.
- The current 4000-byte RG6 frame is transferred in one validated 16 KiB reverse-DMA frame; larger formats must use ordered fragmentation without mutating an in-flight source.
- ATM text memory is updated only after the complete reverse-DMA frame passes header, length and CRC validation.
- Build logs report component versions, image sizes and test results. Assembly success is not hardware/display verification.

## 7. Implementation progress (2026-11-08)

### Completed in source (not yet build-verified)

- Added X86VGA as dynamic module ID05 / physical page08 and X86VID as dynamic module ID06 / physical page09, separate from the 4 KiB X86DEV overlay.
- Extended the build output, TR-DOS disk packaging, six-record X86MODS manifest, host loader and NeoGS IMAGE receiver for X86VGA and X86VID.
- IMAGE_FINISH registers page08 only after the received image has passed the existing physical-page readback check; the resident then calls the module through the overlay gate.
- Added an overlay probe and register-file self-test. The test covers Sequencer, Attribute Controller flip-flop, Graphics Controller and DAC RGB read/write sequencing.
- Added VGA guest I/O dispatch for ports 3C0h–3DFh, including active mono/colour CRTC aliasing and the PCem-visible register read/write side effects.
- Added resident overlay-gate wrappers so X86IO reaches VGA without directly accessing an inactive WIN2 page.
- Added build-time VGA overlay size assertions and TR-DOS entry validation.

### Current implementation boundary

The current X86VGA code now has source implementations for register/port access and VGA aperture semantics, including GDC[6] window selection, chain-4/chain-2, four-plane latches, read mode 1 and write modes 0–3. It is still not a complete VGA adapter: scanout/rendering, timing, text cursor/blink and packed/planar pixel conversion remain to be implemented and tested.

The ATM RG6 80x25 text converter, mode descriptor exchange, reverse-DMA VIDEO response, host frame validation and page7/page3 screen application are now present in source. Graphics-mode conversion and additional ATM modes remain to be implemented. The existing BIOS2 INT CD debugging state remains untouched.

No SjASMPlus build or emulator run has been performed for these changes yet. The source changes must be assembled and exercised before reporting build or runtime success.

### Stage 1/2 source progress

The VGA overlay now contains:
- PCem-style port register file for Attribute Controller, Sequencer, Graphics Controller, CRTC and DAC.
- CRTC mono/colour alias decode, CRTC write protection, Attribute Controller flip-flop reset on 3DAh reads, DAC component sequencing and palette derivation.
- GDC[6] memory-window decode for A0000h-BFFFFh, A0000h-AFFFFh, B0000h-B7FFFh and B8000h-BFFFFh.
- Four-plane interleaved VRAM access through physical pages30h-3Fh and WIN3/MPAGEX.
- Chain-4 and chain-2 addressing, four latches, read mode 0/1, write modes 0-3, Sequencer Map Mask, GDC bit mask, Set/Reset and logical operations.
- A save/restore-safe startup self-test that checks the register interface, mono/colour CRTC aliasing, all four planar write/read planes, and chain-4 packed access at the final aperture byte.

The status-register retrace bit is currently a deterministic read-sample toggle so BIOS polling cannot stall while scanline timing is absent. It is a temporary compatibility aid, not a timing-accurate replacement for PCem's svga_poll().

The memory aperture is now routed through X86VGA; the previous linear page-bias mapping is no longer used for A0000h-BFFFFh.
