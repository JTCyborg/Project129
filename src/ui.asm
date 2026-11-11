; Project129 ATM Turbo 2+ RG6 80x25 console.
; Port of the proven Project127/Project126 text-console memory layout.
; Character plane: ATM page 7; attribute plane: ATM page 3.
; All external debug output remains mirrored by the C caller to port #EF.

SECTION CODE
PUBLIC _p129_ui_init
PUBLIC _p129_ui_putc
PUBLIC _p129_ui_clock_update
PUBLIC _p129_ui_quiesce
PUBLIC _p129_ui_handoff_begin
PUBLIC _p129_ui_handoff_end
PUBLIC _p129_ui_resume
PUBLIC _p129_ui_lease_state
PUBLIC _p129_ui_lease_selftest
EXTERN _p129_rtc_hour
EXTERN _p129_rtc_minute
EXTERN _p129_rtc_second

P129_UI_PAGE7 EQU 078h
P129_UI_PAGE3 EQU 07Ch
P129_UI_HOST_PAGE5 EQU 07Ah
P129_UI_HOST_PAGE0 EQU 07Fh
P129_UI_TOP EQU 12
P129_UI_LOG_ROWS EQU 13
P129_UI_WIDTH EQU 80

_p129_ui_init:
        push    af
        push    bc
        push    de
        push    hl
        di

        ; Match Project127's ATM paging/shadow-port/video initialization.
        xor     a
        ld      bc,0EFF7h
        out     (c),a
        ld      a,018h
        ld      bc,07FFDh
        out     (c),a
        ld      (05C3Bh),a
        ld      bc,p129_ui_ports_open
        push    bc
        ld      bc,02A53h
        push    bc
        ld      bc,00177h
        ld      a,0C3h
        jp      03D2Fh

p129_ui_ports_open:
        ld      a,0BFh
        ld      bc,03FF7h
        out     (c),a
        ; Keep W1/P5 mapped: resident code is loaded at #6000 in W1.
        ; The UI accesses both video planes through W3 only.

        ; ATM RG6 text mode trampoline, identical to Project127 reference.
        ld      hl,0FFECh
        ld      (hl),001h
        inc     hl
        ld      (hl),077h
        inc     hl
        ld      (hl),001h
        inc     hl
        ld      (hl),0EDh
        inc     hl
        ld      (hl),079h
        inc     hl
        ld      (hl),0C3h
        inc     hl
        ld      (hl),p129_ui_mode_ready & 0FFh
        inc     hl
        ld      (hl),p129_ui_mode_ready >> 8
        ld      a,0C6h
        jp      0FFECh

p129_ui_mode_ready:
        call    p129_ui_restore_pages
        ld      a,1
        ld      (p129_ui_lease_state),a
        xor     a
        ld      (p129_ui_row),a
        ld      (p129_ui_col),a
        call    p129_ui_clear
        ld      hl,p129_ui_title
        ld      a,0
        ld      c,1
        call    p129_ui_print_at
        ld      hl,p129_ui_subtitle
        ld      a,1
        ld      c,1
        call    p129_ui_print_at
        ld      hl,p129_ui_status
        ld      a,11
        ld      c,1
        call    p129_ui_print_at
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; C calls this helper with the character in A (via inline assembly).
_p129_ui_putc:
        push    af
        push    bc
        push    de
        push    hl
        ld      a,(p129_ui_lease_state)
        cp      1
        jp      nz,p129_ui_done
        ; Restore the caller's character after checking the ownership gate.
        pop     hl
        pop     de
        pop     bc
        pop     af
        push    af
        push    bc
        push    de
        push    hl
        cp      13
        jr      z,p129_ui_cr
        cp      10
        jr      z,p129_ui_lf
        cp      8
        jr      z,p129_ui_bs
        cp      32
        jr      c,p129_ui_done
        cp      128
        jr      c,p129_ui_char_ok
        ld      a,'?'
p129_ui_char_ok:
        ld      (p129_ui_char),a
        ld      a,(p129_ui_row)
        add     a,P129_UI_TOP
        ld      d,a
        ld      a,(p129_ui_col)
        ld      e,a
        ld      a,(p129_ui_char)
        call    p129_ui_write_char
        ld      a,(p129_ui_col)
        inc     a
        cp      P129_UI_WIDTH
        jr      c,p129_ui_store_col
        xor     a
        ld      (p129_ui_col),a
        call    p129_ui_newline
        jr      p129_ui_done
p129_ui_store_col:
        ld      (p129_ui_col),a
        jr      p129_ui_done
p129_ui_cr:
        xor     a
        ld      (p129_ui_col),a
        jr      p129_ui_done
p129_ui_lf:
        call    p129_ui_newline
        jr      p129_ui_done
p129_ui_bs:
        ld      a,(p129_ui_col)
        or      a
        jr      z,p129_ui_done
        dec     a
        ld      (p129_ui_col),a
        ld      a,(p129_ui_row)
        add     a,P129_UI_TOP
        ld      d,a
        ld      a,(p129_ui_col)
        ld      e,a
        ld      a,32
        call    p129_ui_write_char
p129_ui_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

p129_ui_clear:
        ; Character plane: physical page 7 mapped into W3 only.
        call    p129_ui_map_chars
        ld      hl,0C1C0h
        ld      de,0C1C1h
        ld      (hl),32
        ld      bc,063Fh
        ldir
        ld      hl,0E1C0h
        ld      de,0E1C1h
        ld      (hl),32
        ld      bc,063Fh
        ldir

        ; Attribute plane: switch W3 to physical page 3.
        call    p129_ui_map_attrs
        ld      hl,0E1C0h
        ld      de,0E1C1h
        ld      (hl),047h
        ld      bc,063Fh
        ldir
        ld      hl,0C1C1h
        ld      de,0C1C2h
        ld      (hl),047h
        ld      bc,063Fh
        ldir
        ld      hl,0E1C0h
        ld      de,0E1C1h
        ld      (hl),04Fh
        ld      bc,02FFh
        ldir
        ld      hl,0C1C1h
        ld      de,0C1C2h
        ld      (hl),04Fh
        ld      bc,02FFh
        ldir
        ld      hl,0E4C0h
        ld      de,0E4C1h
        ld      (hl),044h
        ld      bc,033Fh
        ldir
        ld      hl,0C4C1h
        ld      de,0C4C2h
        ld      (hl),044h
        ld      bc,033Fh
        ldir
        call    p129_ui_restore_pages
        ret

; HL=zero-terminated string, A=row, C=column.
p129_ui_print_at:
        ld      (p129_ui_text_ptr),hl
        ld      (p129_ui_print_row),a
        ld      a,c
        ld      (p129_ui_print_col),a
p129_ui_print_loop:
        ld      hl,(p129_ui_text_ptr)
        ld      a,(hl)
        or      a
        ret     z
        ld      (p129_ui_char),a
        inc     hl
        ld      (p129_ui_text_ptr),hl
        ld      a,(p129_ui_print_row)
        ld      d,a
        ld      a,(p129_ui_print_col)
        ld      e,a
        ld      a,(p129_ui_char)
        call    p129_ui_write_char
        ld      a,(p129_ui_print_col)
        inc     a
        cp      P129_UI_WIDTH
        jr      c,p129_ui_print_col_ok
        xor     a
        ld      (p129_ui_print_col),a
        ld      a,(p129_ui_print_row)
        inc     a
        ld      (p129_ui_print_row),a
        jr      p129_ui_print_loop
p129_ui_print_col_ok:
        ld      (p129_ui_print_col),a
        jr      p129_ui_print_loop

p129_ui_write_char:
        push    af
        push    bc
        push    de
        push    hl
        ld      (p129_ui_char),a
        ld      a,d
        ld      (p129_ui_write_row),a
        ld      a,e
        ld      (p129_ui_write_col),a
        ld      a,(p129_ui_write_row)
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,001C0h
        add     hl,de
        ld      a,(p129_ui_write_col)
        ld      c,a
        and     1
        ld      (p129_ui_parity),a
        ld      a,c
        srl     a
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (p129_ui_offset),hl
        ld      a,(p129_ui_write_row)
        cp      P129_UI_TOP
        ld      a,044h
        jr      nc,p129_ui_attr_ready
        ld      a,04Fh
p129_ui_attr_ready:
        ld      (p129_ui_attr),a
        ; W3 is the only remapped window. This keeps the resident code in
        ; W1/#6000 executable while both video planes are updated.
        call    p129_ui_map_chars
        ld      hl,(p129_ui_offset)
        ld      a,(p129_ui_parity)
        or      a
        jr      nz,p129_ui_write_odd_char
        ld      de,0C000h
        add     hl,de
        ld      a,(p129_ui_char)
        ld      (hl),a
        jr      p129_ui_write_attr
p129_ui_write_odd_char:
        ld      de,0E000h
        add     hl,de
        ld      a,(p129_ui_char)
        ld      (hl),a
p129_ui_write_attr:
        call    p129_ui_map_attrs
        ld      hl,(p129_ui_offset)
        ld      a,(p129_ui_parity)
        or      a
        jr      nz,p129_ui_write_odd_attr
        ld      de,0E000h
        add     hl,de
        ld      a,(p129_ui_attr)
        ld      (hl),a
        jr      p129_ui_write_done
p129_ui_write_odd_attr:
        ld      de,0C000h
        add     hl,de
        inc     hl
        ld      a,(p129_ui_attr)
        ld      (hl),a
p129_ui_write_done:
        call    p129_ui_restore_pages
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

p129_ui_newline:
        ld      a,(p129_ui_row)
        inc     a
        cp      P129_UI_LOG_ROWS
        jr      c,p129_ui_newline_store
        call    p129_ui_scroll
        ld      a,P129_UI_LOG_ROWS-1
p129_ui_newline_store:
        ld      (p129_ui_row),a
        xor     a
        ld      (p129_ui_col),a
        ret

p129_ui_scroll:
        push    af
        push    bc
        push    de
        push    hl
        ; Scroll character planes while W3 maps page 7.
        call    p129_ui_map_chars
        ld      hl,0C500h
        ld      de,0C4C0h
        ld      bc,00300h
        ldir
        ld      hl,0E500h
        ld      de,0E4C0h
        ld      bc,00300h
        ldir
        ld      hl,0C7C0h
        ld      de,0C7C1h
        ld      (hl),32
        ld      bc,0003Fh
        ldir
        ld      hl,0E7C0h
        ld      de,0E7C1h
        ld      (hl),32
        ld      bc,0003Fh
        ldir

        ; Scroll and clear attribute planes while W3 maps page 3.
        call    p129_ui_map_attrs
        ld      hl,0E500h
        ld      de,0E4C0h
        ld      bc,00300h
        ldir
        ld      hl,0C501h
        ld      de,0C4C1h
        ld      bc,00300h
        ldir
        ld      hl,0E7C0h
        ld      de,0E7C1h
        ld      (hl),044h
        ld      bc,0003Fh
        ldir
        ld      hl,0C7C1h
        ld      de,0C7C2h
        ld      (hl),044h
        ld      bc,0003Fh
        ldir
        call    p129_ui_restore_pages
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Map only W3. W1 contains the resident image at #6000 and must never
; be switched while executing this module.
p129_ui_map_chars:
        ld      a,P129_UI_PAGE7
        ld      bc,0FFF7h
        out     (c),a
        ret

p129_ui_map_attrs:
        ld      a,P129_UI_PAGE3
        ld      bc,0FFF7h
        out     (c),a
        ret

p129_ui_restore_pages:
        ld      a,P129_UI_HOST_PAGE0
        ld      bc,0FFF7h
        out     (c),a
        ret

 ; Update the fixed status panel clock from the DS12887 ASCII buffers.
_p129_ui_clock_update:
        push    af
        push    bc
        push    de
        push    hl
        ld      a,(p129_ui_lease_state)
        cp      1
        jp      nz,p129_ui_clock_done
        ld      a,(_p129_rtc_hour)
        ld      (p129_ui_clock_digits),a
        ld      a,(_p129_rtc_hour+1)
        ld      (p129_ui_clock_digits+1),a
        ld      a,(_p129_rtc_minute)
        ld      (p129_ui_clock_digits+3),a
        ld      a,(_p129_rtc_minute+1)
        ld      (p129_ui_clock_digits+4),a
        ld      a,(_p129_rtc_second)
        ld      (p129_ui_clock_digits+6),a
        ld      a,(_p129_rtc_second+1)
        ld      (p129_ui_clock_digits+7),a
        ld      hl,p129_ui_clock_label
        ld      a,2
        ld      c,1
        call    p129_ui_print_at
        ld      hl,p129_ui_clock_digits
        ld      a,2
        ld      c,18
        call    p129_ui_print_at
p129_ui_clock_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; W3 ownership gate: 0=OFFLINE, 1=UI ACTIVE, 2=QUIESCED, 3=HANDOFF.
_p129_ui_lease_state:
p129_ui_lease_state: db 0

_p129_ui_quiesce:
        ld      a,(p129_ui_lease_state)
        cp      1
        jp      nz,p129_ui_lease_reject
        ld      a,2
        ld      (p129_ui_lease_state),a
        xor     a
        ret

_p129_ui_handoff_begin:
        ld      a,(p129_ui_lease_state)
        cp      2
        jp      nz,p129_ui_lease_reject
        ld      a,3
        ld      (p129_ui_lease_state),a
        xor     a
        ret

_p129_ui_handoff_end:
        ld      a,(p129_ui_lease_state)
        cp      3
        jp      nz,p129_ui_lease_reject
        ld      a,2
        ld      (p129_ui_lease_state),a
        xor     a
        ret

_p129_ui_resume:
        ld      a,(p129_ui_lease_state)
        cp      2
        jp      nz,p129_ui_lease_reject
        ld      a,1
        ld      (p129_ui_lease_state),a
        xor     a
        ret

p129_ui_lease_reject:
        ld      a,1
        ret

; Validate legal transitions and invalid-order rejection; leave UI ACTIVE.
_p129_ui_lease_selftest:
        ld      a,(p129_ui_lease_state)
        cp      1
        jp      nz,p129_ui_lease_test_fail
        call    _p129_ui_handoff_begin
        or      a
        jp      z,p129_ui_lease_test_fail
        call    _p129_ui_quiesce
        or      a
        jp      nz,p129_ui_lease_test_fail
        ld      a,(p129_ui_lease_state)
        cp      2
        jp      nz,p129_ui_lease_test_fail
        call    _p129_ui_handoff_begin
        or      a
        jp      nz,p129_ui_lease_test_fail
        ld      a,(p129_ui_lease_state)
        cp      3
        jp      nz,p129_ui_lease_test_fail
        call    _p129_ui_quiesce
        or      a
        jp      z,p129_ui_lease_test_fail
        call    _p129_ui_handoff_end
        or      a
        jp      nz,p129_ui_lease_test_fail
        call    _p129_ui_resume
        or      a
        jp      nz,p129_ui_lease_test_fail
        call    _p129_ui_resume
        or      a
        jp      z,p129_ui_lease_test_fail
        xor     a
        ret
p129_ui_lease_test_fail:
        ; Best-effort recovery to ACTIVE after an unexpected transition result.
        ld      a,(p129_ui_lease_state)
        cp      3
        call    z,_p129_ui_handoff_end
        ld      a,(p129_ui_lease_state)
        cp      2
        call    z,_p129_ui_resume
        ld      a,1
        ret

p129_ui_row: db 0
p129_ui_col: db 0
p129_ui_char: db 0
p129_ui_parity: db 0
p129_ui_attr: db 0
p129_ui_write_row: db 0
p129_ui_write_col: db 0
p129_ui_offset: dw 0
p129_ui_text_ptr: dw 0
p129_ui_print_row: db 0
p129_ui_print_col: db 0
p129_ui_title: db "PROJECT129 | ATM TURBO 2+ | SYSTEM CORE",0
p129_ui_clock_label: db "REAL TIME CLOCK:",0
p129_ui_clock_digits: db "??:??:??",0
p129_ui_subtitle: db "SYSTEM STARTUP / HARDWARE DIAGNOSTICS",0
p129_ui_status: db "TR-DOS: READY | MEMORY: -- | DEVICES: --",0
