; Project129 ATM2+ physical W3 page mapper backend.
; The C layer validates page IDs and ownership before calling this routine.
; ATM2+ page dispatcher: W3=#FFF7, data byte=#7F-page (RAM, no #7FFD mux).
; DOSEN/shadow ports must already be enabled by the resident UI bootstrap.

SECTION CODE
PUBLIC _p129_map_hw_write
EXTERN _p129_map_hw_encoded

_p129_map_hw_write:
        push    af
        push    bc
        ld      a,(_p129_map_hw_encoded)
        ld      bc,0FFF7h
        out     (c),a
        pop     bc
        pop     af
        ret
