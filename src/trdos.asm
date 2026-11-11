; Project129 TR-DOS catalogue preload.
; Read-only mirror of the proven Project127 ROM call contract:
;   ROM entry #3D13, E=zero-based sector, HL=destination, B=1, C=5.
; Reads track 0 sectors 1..8 into the host W3/page-0 buffer at #C800.
; No disk writes, IM or EI are performed here.

SECTION CODE
PUBLIC _p129_trdos_preload
PUBLIC __p129_trdos_result

_p129_trdos_preload:
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        push    iy
        exx
        push    bc
        push    de
        push    hl
        exx
        ex      af,af'
        push    af
        ex      af,af'

        ld      (p129_trdos_saved_sp),sp
        ; Isolated scratch stack, matching the working Project127 reader.
        ld      sp,0B7F0h
        xor     a
        ld      (p129_trdos_io_error),a
        ld      (p129_trdos_io_status),a
        ld      (p129_trdos_sector),a
        ld      hl,0C800h
        ld      (p129_trdos_buffer_ptr),hl

p129_trdos_read_sector:
        ld      a,(p129_trdos_sector)
        cp      8
        jr      nc,p129_trdos_read_complete

        ld      e,a
        ld      d,0
        ld      hl,(p129_trdos_buffer_ptr)
        ld      b,1
        ld      c,5
        xor     a
        ld      (05D0Fh),a
        ld      (05D10h),a

        ; Raw port markers bracket each ROM sector read.
        ld      bc,00EFh
        ld      a,'R'
        out     (c),a
        ld      a,(p129_trdos_sector)
        add     a,'0'
        out     (c),a
        ld      b,1
        ld      c,5
        call    03D13h

        ld      bc,00EFh
        ld      a,'r'
        out     (c),a
        ld      a,(p129_trdos_sector)
        add     a,'0'
        out     (c),a
        ld      a,13
        out     (c),a
        ld      a,10
        out     (c),a

        ld      a,(05D0Fh)
        ld      (p129_trdos_io_error),a
        ld      b,a
        ld      a,(05D10h)
        ld      (p129_trdos_io_status),a
        or      b
        jr      nz,p129_trdos_read_failed

        ld      hl,(p129_trdos_buffer_ptr)
        ld      de,0100h
        add     hl,de
        ld      (p129_trdos_buffer_ptr),hl
        ld      a,(p129_trdos_sector)
        inc     a
        ld      (p129_trdos_sector),a
        jr      p129_trdos_read_sector

p129_trdos_read_complete:
        xor     a
        ld      (_p129_trdos_result),a
        jr      p129_trdos_restore

p129_trdos_read_failed:
        ld      a,1
        ld      (_p129_trdos_result),a

p129_trdos_restore:
        ld      sp,(p129_trdos_saved_sp)
        ex      af,af'
        pop     af
        ex      af,af'
        exx
        pop     hl
        pop     de
        pop     bc
        exx
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af

        ; Z88DK SDCC 16-bit return value: HL=0 on success, HL=1 on error.
        ld      a,(_p129_trdos_result)
        ld      l,a
        ld      h,0
        ret

p129_trdos_saved_sp:     dw 0
p129_trdos_buffer_ptr:   dw 0C800h
p129_trdos_sector:       db 0
p129_trdos_io_error:     db 0
p129_trdos_io_status:    db 0
_p129_trdos_result:      db 0
