; Project129 Z88DK resident entry.
; This must be the first executable bytes of P129BOOT.C at #6000.
; Do not use code_crt_init here: --no-crt has no CRT dispatcher to call.

SECTION CODE
PUBLIC _p129_entry
EXTERN _p129_c_entry

_p129_entry:
        ld      a,'>'
        ld      bc,00EFh
        out     (c),a
        di
        ld      sp,0BFFFh
        ld      a,010h
        ld      bc,07FFDh
        out     (c),a
        ld      (05C3Bh),a
        xor     a
        ld      bc,0EFF7h
        out     (c),a

; Distinguish reaching the C call site from successful C main() execution.
        ld      a,'C'
        ld      bc,00EFh
        out     (c),a
        call    _p129_c_entry

; main() is expected to remain resident forever. Reaching this marker means
; the C entry returned unexpectedly, rather than failing before the call.
        ld      a,'R'
        ld      bc,00EFh
        out     (c),a
p129_idle:
        jr      p129_idle
