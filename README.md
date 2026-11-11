# Project129

ATM Turbo 2+ System Core port based on the **Project127 execution scenario**, reimplemented in **Z88DK C + Z80 assembly**.

Project129 is a separate implementation. Project127 is the behavioral reference; its assembly modules are not linked into Project129. Project127 remains unchanged.

## Fixed rules

- Target: ATM Turbo 2+ (Z80 host), TR-DOS boot disk.
- Z88DK is the application/compiler toolchain; small Z80 assembly stubs are allowed where the ABI or hardware entry requires them.
- Boot contract follows Project127: tokenized BASIC `BOOT` -> TR-DOS interception via `RANDOMIZE USR 15619` -> load `P129BOOT.C` at `#6000` -> enter with `RANDOMIZE USR 24576`.
- Debug output: ATM port `#EF`.
- Preserve Project127 subsystem order and ownership contracts. Do not pull in Project125/126/128 implementation.
- All address, length, file-offset and range APIs use unsigned 32-bit values with overflow checks.
- ATM host owns physical devices and controller ports. Any companion subsystem must use the defined host transport/DMA contract; no direct external-device access from a companion CPU.

## Build

The build uses Z88DK for the resident image and SjASMPlus for TR-DOS packaging. See `tools/build_project129.ps1`.

## Status

- [x] Repository separated from Project127.
- [x] Project127 boot contract and subsystem sequence recorded.
- [ ] Z88DK resident entry and #EF diagnostic boot confirmed on ATM emulator.
- [ ] UINT32 range/check API.
- [x] ATM physical-page allocator metadata and software W3 page-map transaction layer.
- [ ] Physical ATM page switching, cross-page memory operations and W3/UI lease integration.
- [ ] TR-DOS disk service.
- [ ] ATM native video.
- [ ] DS12887 RTC via SMUC.
- [ ] Keyboard/input.
- [ ] Physical Nemo IDE/SMUC block storage.
- [ ] Speaker/audio.
- [ ] Timer/events/interrupt dispatch.

A subsystem is complete only after its implementation, stable interface, boundary/error-path checks and runtime evidence are present. Build success alone is not runtime validation.
