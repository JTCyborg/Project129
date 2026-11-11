; Project129 Z88DK resident entry.
; Linked at #6000 as the first bytes of P129BOOT.C.
; Preserves the Project127 host paging/stack entry sequence.

SECTION code_crt_init
PUBLIC _p129_entry
EXTERN _main

_p129_entry:
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
.p129_idle:
        jr      .p129_idle
