; ============================================================================
; Project129 ATM Turbo 2+ beeper smoke test
; Behavior ported from Project127 src/kernel/p127_speaker.asm.
;
; Host Z80 owns physical ULA port #FE. D4 is speaker; D3 is tape output;
; D0..D2 are border colour. The diagnostic caller explicitly selects low
; nibble 0, matching the Project127 startup test message. Only D4 toggles.
;
; This is a bounded one-shot hardware smoke test, not an async sound service
; and not IBM PC Speaker/PIT/PPI emulation.
; ============================================================================
SECTION CODE
PUBLIC _p129_speaker_test_tone

P129_SPEAKER_PORT EQU 0FEh
P129_SPEAKER_MASK EQU 010h

_p129_speaker_test_tone:
        push    af
        push    bc
        push    de
        push    hl
        xor     a
        ld      (p129_speaker_shadow),a
        ld      de,0258h
p129_speaker_test_loop:
        call    p129_speaker_toggle
        ld      b,0FFh
p129_speaker_test_delay1:
        djnz    p129_speaker_test_delay1
        ld      b,0FFh
p129_speaker_test_delay2:
        djnz    p129_speaker_test_delay2
        dec     de
        ld      a,d
        or      e
        jr      nz,p129_speaker_test_loop
        call    p129_speaker_stop
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Toggle only D4, preserving low-nibble border/tape state.
p129_speaker_toggle:
        ld      a,(p129_speaker_shadow)
        xor     P129_SPEAKER_MASK
        ld      (p129_speaker_shadow),a
        out     (P129_SPEAKER_PORT),a
        ret

; Ensure the speaker output is low at exit.
p129_speaker_stop:
        ld      a,(p129_speaker_shadow)
        and     0EFh
        ld      (p129_speaker_shadow),a
        out     (P129_SPEAKER_PORT),a
        ret

SECTION DATA
p129_speaker_shadow:
        db 0
