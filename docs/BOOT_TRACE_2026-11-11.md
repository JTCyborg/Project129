# Project129 boot trace — 2026-11-11

## Captured runtime output

The user supplied the following bytes from the debug channel:

```text
01 50 31 32 39 5D 4C 4F 41 44 02 3E
```

Decoded payload:

```text
[P129]LOAD>
```

## Acceptance interpretation

| Milestone | Result | Evidence |
|---|---|---|
| BASIC boot program reached the post-load diagnostic | PASS | `[P129]LOAD` |
| TR-DOS CODE-load command returned to BASIC | PASS | The marker is emitted by BASIC line 21, after `LOAD "p129boot" CODE 24576` |
| Resident assembly entry at `#6000` was reached | PASS | `>` is emitted by `_p129_entry` in `src/entry.asm` |
| C `main()` was entered | NOT YET OBSERVED | Expected marker `[P129] C IMAGE EXECUTED` is absent from this capture |
| Full Project127 startup scenario is ported | NOT CLAIMED | This build remains the bootstrap/entry milestone |

## Next diagnostic boundary

The BASIC-to-resident handoff is now evidenced through the first instruction sequence of `_p129_entry`. The remaining unverified transition is the assembly call to Z88DK's `_main` symbol and execution of the C image.

The next expected output is:

```text
[P129] C IMAGE EXECUTED
[P129] Z88DK C ENTRY
```

If these lines do not appear, investigate the linked image layout, symbol resolution and call target for `_main`. Do not change the already evidenced BASIC/TR-DOS handoff without new contradictory runtime evidence.

## Validation limits

This record documents the supplied runtime bytes only. It does not claim a fresh local build, binary inspection, or a complete emulator acceptance run.
