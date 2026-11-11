# Project126 — PC Speaker to ATM beeper design

Status: design investigation; audio output is NOT implemented or hardware-verified.

## 1. Required guest behavior

The emulated machine exposes the IBM PC/XT-compatible PC Speaker path:

- PIT 8253 channel 2 is programmed through ports 42h/43h.
- PPI port B at 61h controls channel-2 gate (bit 0) and speaker data enable (bit 1).
- A speaker waveform is audible only when both port-61 bits 0 and 1 are set and PIT channel 2 is running in a supported mode.
- The effective square-wave frequency for PIT mode 3 is 1,193,182 / divisor Hz. A divisor of zero means 65,536.
- Clearing either gate/data bit must silence the speaker immediately.
- PIT channel 2 programming alone must not produce sound while the port-61 gate/data bits are disabled.

The existing PCem reference is `PCem/sound_speaker.c` plus `PCem/pit.c`: speaker output depends on the PIT channel-2 gate, enable state, mode and reload value. A static register latch is not sufficient.

## 2. Processor ownership

- NeoGS owns the emulated PIT/PPI and calculates speaker state from guest writes.
- NeoGS must not execute physical `IN/OUT` to the ATM beeper or any other external device.
- ATM owns physical audio output. The host receives compact speaker-state updates through DMA/IPC.
- ATM generates the physical waveform locally. IPC carries state changes, not individual waveform edges.

## 3. ATM output candidate and timing requirement

The standard Spectrum/ATM beeper output candidate is the EAR/MIC bit in port `FEh` (bit 4). A host implementation must preserve the other port-FE bits and must confirm the exact ATM Turbo 2+ hardware path before enabling it.

The host needs a periodic high-rate service to generate the square wave. A 50 Hz frame interrupt is not sufficient for an audible PC Speaker tone. A busy-wait loop in the main host thread is unacceptable because it would starve catalogue input, RTC, IPC and display services. A suitable ATM timer/interrupt source (or a hardware audio path accepting a frequency/divisor directly) must be identified and validated first. The timer service must coexist with video and keyboard handlers.

## 4. Proposed IPC event

Add an AUDIO service/event only after the ATM receive/event path is available and verified.

Suggested state payload (little-endian):
- byte 0: enabled (0/1; derived from PPI port-61 bits 0 and 1)
- byte 1: PIT channel-2 mode (2 or 3 initially)
- bytes 2..3: channel-2 reload divisor (0 represents 65536)
- byte 4: waveform kind (square for initial PC Speaker support)
- byte 5: monotonically increasing state sequence

Send an event only when effective speaker state changes: gate/enable transition, channel-2 mode change, or completed channel-2 reload update. Coalesce low/high byte writes so they do not emit a transient tone. An explicit disabled event is required on guest reset, CPU stop, watchdog and IPC resynchronization.

ATM rejects stale sequence numbers, validates payload length/version, and fails silent on timeout, malformed event or loss of the NeoGS session. It restores the previous port-FE output state when stopping audio.

## 5. Implementation phases and acceptance tests

1. Implement guest-side PPI 61h speaker gate/data state and PIT channel-2 reload/mode tracking on NeoGS. Add register self-tests; no physical sound yet.
2. Validate the ATM hardware output bit and discover a non-blocking timer/interrupt backend. Confirm audibility on real ATM Turbo 2+ and verify keyboard/catalogue/RTC continue working.
3. Add a versioned AUDIO event and host-side event consumer. Keep audio state independent of bulk image/video DMA staging buffers.
4. Test: speaker disabled by default; gate-only silent; data-only silent; both enabled produce tone; divisor changes pitch; clearing either bit silences; divisor zero maps to 65536; reset/watchdog/IPC loss silences; no corruption of port-FE border/tape/paging bits; no missed keyboard input during sustained tone.

Until phases 1–3 are complete, PC Speaker must be reported as unsupported rather than claiming BIOS diagnostic beeps are audible.
