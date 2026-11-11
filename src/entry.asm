; Project129 Z88DK resident entry.
; Linked as the first bytes of P129BOOT.C at #6000.
; C ABI symbol p129_main is provided by src/main.c.

SECTION code_crt_init
PUBLIC _p129_entry
EXTERN _p129_main

_p129_entry:
        di
        ld      sp,0BFFFh
        call    _p129_main
.p129_idle:
        jr      .p129_idle
