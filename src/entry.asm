; Project129 Z88DK resident entry.
; This must be the first executable bytes of P129BOOT.C at #6000.
; Do not use code_crt_init here: --no-crt has no CRT dispatcher to call it.

SECTION CODE
PUBLIC _p129_entry
EXTERN _main

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
        call    _main
p129_idle:
        jr      p129_idle
