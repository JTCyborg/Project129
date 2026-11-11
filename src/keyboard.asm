; ============================================================================
; Project129 ATM keyboard driver
; Ported from Project127 src/kernel/p127_keyboard.asm.
;
; ATM host owns physical ULA port FEh. NeoGS/x86 must never perform this I/O.
; Preferred path: Unreal Speccy ATM_KBD mode 2 + event mode 3.
; Fallback: standard ZX 8x5 matrix, diagnostic only.
;
; C API:
;   p129_keyboard_init() -> p129_keyboard_xt_active (0/1)
;   p129_keyboard_poll() -> A=1 when an event/state change is available
;   p129_keyboard_lastscan, _r2, _r3, _r4, _r5
;   p129_keyboard_matrix[8]
; ============================================================================

SECTION CODE
PUBLIC _p129_keyboard_init
PUBLIC _p129_keyboard_poll
PUBLIC _p129_keyboard_xt_active
PUBLIC _p129_keyboard_lastscan
PUBLIC _p129_keyboard_r2
PUBLIC _p129_keyboard_r3
PUBLIC _p129_keyboard_r4
PUBLIC _p129_keyboard_r5
PUBLIC _p129_keyboard_matrix

P129_KBD_PORT              EQU 0FEh
P129_KBD_MODE_XT           EQU 2
P129_KBD_MODE_EVENT        EQU 3
P129_KBD_ROW_MASK          EQU 01Fh

_p129_keyboard_init:
        xor     a
        ld      (_p129_keyboard_xt_active),a
        ld      (_p129_keyboard_snapshot_valid),a
        ld      (_p129_keyboard_lastscan),a
        ld      (_p129_keyboard_r2),a
        ld      (_p129_keyboard_r3),a
        ld      (_p129_keyboard_r4),a
        ld      (_p129_keyboard_r5),a
        ld      hl,_p129_keyboard_matrix
        ld      de,_p129_keyboard_previous
        ld      b,8
        ld      a,01Fh
p129_kbd_init_clear:
        ld      (hl),a
        inc     hl
        ld      (de),a
        inc     de
        djnz    p129_kbd_init_clear

        ld      a,P129_KBD_MODE_XT
        call    p129_kbd_set_mode
        jr      c,p129_kbd_init_done
        ld      a,1
        ld      (_p129_keyboard_xt_active),a
p129_kbd_init_done:
        ld      a,(_p129_keyboard_xt_active)
        ld      l,a
        ld      h,0
        ret

; A=2 or A=3. Carry indicates handshake failure.
p129_kbd_set_mode:
        ld      (_p129_keyboard_requested_mode),a
        ld      bc,055FEh
        in      a,(c)
        cp      0AAh
        jr      nz,p129_kbd_mode_fail
        ld      bc,008FEh
        in      a,(c)
        cp      8
        jr      nz,p129_kbd_mode_fail
        ld      a,(_p129_keyboard_requested_mode)
        ld      b,a
        ld      c,P129_KBD_PORT
        in      a,(c)
        cp      0FFh
        jr      nz,p129_kbd_mode_fail
        or      a
        ret
p129_kbd_mode_fail:
        scf
        ret

; Poll one ATM XT event or one ZX matrix snapshot.
; A=1 on a new event/state transition, A=0 otherwise.
_p129_keyboard_poll:
        ld      a,(_p129_keyboard_xt_active)
        or      a
        jp      z,p129_kbd_poll_matrix
        call    p129_kbd_read_mode2
        ld      a,P129_KBD_MODE_EVENT
        call    p129_kbd_set_mode
        jr      c,p129_kbd_xt_recover
        ld      bc,000FEh
        in      a,(c)
        ld      (_p129_keyboard_lastscan),a
        ld      a,P129_KBD_MODE_XT
        call    p129_kbd_set_mode
        jr      c,p129_kbd_xt_recover

        ld      a,(_p129_keyboard_lastscan)
        or      a
        jr      nz,p129_kbd_event
        ld      a,(_p129_keyboard_r3)
        ld      b,a
        ld      a,(_p129_keyboard_prev_r3)
        cp      b
        jr      nz,p129_kbd_event
        ld      a,(_p129_keyboard_r4)
        ld      b,a
        ld      a,(_p129_keyboard_prev_r4)
        cp      b
        jr      nz,p129_kbd_event
        ld      a,(_p129_keyboard_r5)
        ld      b,a
        ld      a,(_p129_keyboard_prev_r5)
        cp      b
        jr      nz,p129_kbd_event
        ld      hl,0
        ret

p129_kbd_event:
        ld      a,(_p129_keyboard_r3)
        ld      (_p129_keyboard_prev_r3),a
        ld      a,(_p129_keyboard_r4)
        ld      (_p129_keyboard_prev_r4),a
        ld      a,(_p129_keyboard_r5)
        ld      (_p129_keyboard_prev_r5),a
        ld      hl,1
        ret

p129_kbd_xt_recover:
        ld      a,P129_KBD_MODE_XT
        call    p129_kbd_set_mode
        ld      hl,0
        ret

p129_kbd_read_mode2:
        ld      bc,000FEh
        in      a,(c)
        ld      (_p129_keyboard_r2),a
        ld      bc,040FEh
        in      a,(c)
        ld      (_p129_keyboard_r3),a
        ld      bc,080FEh
        in      a,(c)
        ld      (_p129_keyboard_r4),a
        ld      bc,0C0FEh
        in      a,(c)
        ld      (_p129_keyboard_r5),a
        ret

; Standard ZX matrix fallback, used only if ATM_KBD mode negotiation fails.
p129_kbd_poll_matrix:
        call    p129_kbd_scan_matrix
        ld      a,(_p129_keyboard_snapshot_valid)
        or      a
        jr      z,p129_kbd_matrix_changed
        ld      hl,_p129_keyboard_matrix
        ld      de,_p129_keyboard_previous
        ld      b,8
p129_kbd_matrix_compare:
        ld      a,(de)
        cp      (hl)
        jr      nz,p129_kbd_matrix_changed
        inc     de
        inc     hl
        djnz    p129_kbd_matrix_compare
        ld      hl,0
        ret

p129_kbd_matrix_changed:
        ld      hl,_p129_keyboard_matrix
        ld      de,_p129_keyboard_previous
        ld      bc,8
        ldir
        ld      a,1
        ld      (_p129_keyboard_snapshot_valid),a
        ld      hl,1
        ret

p129_kbd_scan_matrix:
        push    bc
        push    de
        push    hl
        ld      bc,000FEh
        ld      hl,p129_kbd_row_selectors
        ld      de,_p129_keyboard_matrix
        ld      a,8
p129_kbd_scan_loop:
        push    af
        ld      b,(hl)
        inc     hl
        in      a,(c)
        and     P129_KBD_ROW_MASK
        ld      (de),a
        inc     de
        pop     af
        dec     a
        jr      nz,p129_kbd_scan_loop
        pop     hl
        pop     de
        pop     bc
        ret

SECTION DATA
p129_kbd_row_selectors:
        db 0FEh,0FDh,0FBh,0F7h,0EFh,0DFh,0BFh,07Fh

_p129_keyboard_xt_active:
        db 0
_p129_keyboard_requested_mode:
        db 0
_p129_keyboard_lastscan:
        db 0
_p129_keyboard_r2:
        db 0
_p129_keyboard_r3:
        db 0
_p129_keyboard_r4:
        db 0
_p129_keyboard_r5:
        db 0
_p129_keyboard_prev_r3:
        db 0FFh
_p129_keyboard_prev_r4:
        db 0FFh
_p129_keyboard_prev_r5:
        db 0FFh
_p129_keyboard_snapshot_valid:
        db 0
_p129_keyboard_matrix:
        ds 8,01Fh
_p129_keyboard_previous:
        ds 8,01Fh
