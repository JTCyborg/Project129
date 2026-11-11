; ============================================================================
; Project129 Nemo IDE / SMUC ATA PIO driver
; Version 0.1.0 - read-only bring-up.
; Port map and LBA28 transfer sequence follow Project127 p127_hdd.asm.
; Host Z80 owns the physical IDE controller. No DMA, IRQ or paging changes.
;
; Public C API: p129_hdd_probe()
; Public state: p129_hdd_present, p129_hdd_error, p129_hdd_last_status
; Capacity: p129_hdd_capacity[4], ATA IDENTIFY words 60-61 little-endian.
;
; Select Master -> READY -> IDENTIFY DEVICE (ECh) -> 256 words
; -> READ SECTORS (20h), LBA 63 -> validate BPB and 55AA.
; This version never issues WRITE SECTORS or FLUSH.
; ============================================================================

SECTION CODE
PUBLIC _p129_hdd_probe
PUBLIC _p129_hdd_present
PUBLIC _p129_hdd_sector_valid
PUBLIC _p129_hdd_error
PUBLIC _p129_hdd_last_status
PUBLIC _p129_hdd_capacity

P129_HDD_PORT_DATA_LO  EQU 00010h
P129_HDD_PORT_DATA_HI  EQU 00011h
P129_HDD_PORT_COUNT    EQU 00050h
P129_HDD_PORT_LBA_LOW  EQU 00070h
P129_HDD_PORT_LBA_MID  EQU 00090h
P129_HDD_PORT_LBA_HIGH EQU 000B0h
P129_HDD_PORT_DRIVE    EQU 000D0h
P129_HDD_PORT_STATUS   EQU 000F0h
P129_HDD_PORT_COMMAND  EQU 000F0h
P129_HDD_PARTITION_LBA EQU 63

_p129_hdd_probe:
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        xor     a
        ld      (_p129_hdd_present),a
        ld      (_p129_hdd_sector_valid),a
        ld      (_p129_hdd_error),a
        ld      (_p129_hdd_last_status),a

        ; Floating IDE bus reads FFh.
        ld      bc,P129_HDD_PORT_STATUS
        in      a,(c)
        ld      (_p129_hdd_last_status),a
        cp      0FFh
        jr      z,p129_hdd_no_device

        ; Select Master and wait for BSY=0, ERR=0, DRDY=1.
        ld      a,0E0h
        ld      bc,P129_HDD_PORT_DRIVE
        out     (c),a
        call    p129_hdd_wait_ready
        jr      c,p129_hdd_not_ready

        ; ATA IDENTIFY DEVICE.
        xor     a
        ld      bc,P129_HDD_PORT_COUNT
        out     (c),a
        ld      bc,P129_HDD_PORT_LBA_LOW
        out     (c),a
        ld      bc,P129_HDD_PORT_LBA_MID
        out     (c),a
        ld      bc,P129_HDD_PORT_LBA_HIGH
        out     (c),a
        ld      a,0E0h
        ld      bc,P129_HDD_PORT_DRIVE
        out     (c),a
        ld      a,0ECh
        ld      bc,P129_HDD_PORT_COMMAND
        out     (c),a
        call    p129_hdd_wait_drq
        jr      c,p129_hdd_identify_failed

        ; Non-zero LBA mid/high signatures indicate ATAPI, not ATA HDD.
        ld      bc,P129_HDD_PORT_LBA_MID
        in      a,(c)
        or      a
        jr      nz,p129_hdd_not_ata
        ld      bc,P129_HDD_PORT_LBA_HIGH
        in      a,(c)
        or      a
        jr      nz,p129_hdd_not_ata

        ; Read 256 IDENTIFY words using the split low/high data ports.
        ld      ix,p129_hdd_identify
        ld      de,256
p129_hdd_identify_loop:
        ld      bc,P129_HDD_PORT_DATA_LO
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        ld      bc,P129_HDD_PORT_DATA_HI
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        dec     de
        ld      a,d
        or      e
        jr      nz,p129_hdd_identify_loop
        call    p129_hdd_wait_complete
        jr      c,p129_hdd_identify_failed

        ; LBA28 sector count = IDENTIFY words 60-61 (byte offsets 120..123).
        ld      hl,p129_hdd_identify+120
        ld      de,_p129_hdd_capacity
        ld      bc,4
        ldir

        ; IDENTIFY succeeded: the ATA device is present even if no BPB exists.
        ld      a,1
        ld      (_p129_hdd_present),a

        ; Read the first legacy partition boot sector (absolute LBA 63).
        call    p129_hdd_read_lba63
        jr      nc,p129_hdd_sector_read_ok
        ld      a,7
        ld      (_p129_hdd_error),a
        jr      p129_hdd_probe_done
p129_hdd_sector_read_ok:
        ld      a,(p129_hdd_sector+11)
        or      a
        jr      nz,p129_hdd_bad_bpb
        ld      a,(p129_hdd_sector+12)
        cp      2
        jr      nz,p129_hdd_bad_bpb
        ld      a,(p129_hdd_sector+510)
        cp      055h
        jr      nz,p129_hdd_bad_signature
        ld      a,(p129_hdd_sector+511)
        cp      0AAh
        jr      nz,p129_hdd_bad_signature
        ld      a,1
        ld      (_p129_hdd_sector_valid),a
        xor     a
        ld      (_p129_hdd_error),a
        jr      p129_hdd_probe_done

p129_hdd_no_device:
        ld      a,1
        ld      (_p129_hdd_error),a
        jr      p129_hdd_probe_done
p129_hdd_not_ready:
        ld      a,2
        ld      (_p129_hdd_error),a
        jr      p129_hdd_probe_done
p129_hdd_identify_failed:
        ld      a,3
        ld      (_p129_hdd_error),a
        jr      p129_hdd_probe_done
p129_hdd_not_ata:
        ld      a,4
        ld      (_p129_hdd_error),a
        jr      p129_hdd_probe_done
p129_hdd_bad_bpb:
        ld      a,5
        ld      (_p129_hdd_error),a
        jr      p129_hdd_probe_done
p129_hdd_bad_signature:
        ld      a,6
        ld      (_p129_hdd_error),a

p129_hdd_probe_done:
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Read one 512-byte sector at LBA 63 using ATA READ SECTORS (20h).
p129_hdd_read_lba63:
        call    p129_hdd_wait_ready
        ret     c
        ld      a,1
        ld      bc,P129_HDD_PORT_COUNT
        out     (c),a
        ld      a,P129_HDD_PARTITION_LBA
        ld      bc,P129_HDD_PORT_LBA_LOW
        out     (c),a
        xor     a
        ld      bc,P129_HDD_PORT_LBA_MID
        out     (c),a
        ld      bc,P129_HDD_PORT_LBA_HIGH
        out     (c),a
        ld      a,0E0h
        ld      bc,P129_HDD_PORT_DRIVE
        out     (c),a
        ld      a,020h
        ld      bc,P129_HDD_PORT_COMMAND
        out     (c),a
        call    p129_hdd_wait_drq
        ret     c

        ld      ix,p129_hdd_sector
        ld      de,256
p129_hdd_sector_loop:
        ld      bc,P129_HDD_PORT_DATA_LO
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        ld      bc,P129_HDD_PORT_DATA_HI
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        dec     de
        ld      a,d
        or      e
        jr      nz,p129_hdd_sector_loop
        jp      p129_hdd_wait_complete

; Bounded wait for DRDY=1, BSY=0, ERR=0.
p129_hdd_wait_ready:
        push    de
        ld      de,0FFFFh
p129_hdd_ready_loop:
        ld      bc,P129_HDD_PORT_STATUS
        in      a,(c)
        ld      (_p129_hdd_last_status),a
        cp      0FFh
        jr      z,p129_hdd_ready_fail
        or      a
        jr      z,p129_hdd_ready_tick
        bit     7,a
        jr      nz,p129_hdd_ready_tick
        bit     0,a
        jr      nz,p129_hdd_ready_fail
        bit     6,a
        jr      nz,p129_hdd_ready_ok
p129_hdd_ready_tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,p129_hdd_ready_loop
p129_hdd_ready_fail:
        pop     de
        scf
        ret
p129_hdd_ready_ok:
        pop     de
        or      a
        ret

; Bounded wait for BSY=0, ERR=0, DRQ=1.
p129_hdd_wait_drq:
        push    de
        ld      de,0FFFFh
p129_hdd_drq_loop:
        ld      bc,P129_HDD_PORT_STATUS
        in      a,(c)
        ld      (_p129_hdd_last_status),a
        cp      0FFh
        jr      z,p129_hdd_drq_fail
        or      a
        jr      z,p129_hdd_drq_tick
        bit     7,a
        jr      nz,p129_hdd_drq_tick
        bit     0,a
        jr      nz,p129_hdd_drq_fail
        bit     3,a
        jr      nz,p129_hdd_drq_ok
p129_hdd_drq_tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,p129_hdd_drq_loop
p129_hdd_drq_fail:
        pop     de
        scf
        ret
p129_hdd_drq_ok:
        pop     de
        or      a
        ret

; Bounded wait for BSY=0, ERR=0, DRQ=0 after data transfer.
p129_hdd_wait_complete:
        push    de
        ld      de,0FFFFh
p129_hdd_complete_loop:
        ld      bc,P129_HDD_PORT_STATUS
        in      a,(c)
        ld      (_p129_hdd_last_status),a
        cp      0FFh
        jr      z,p129_hdd_complete_fail
        or      a
        jr      z,p129_hdd_complete_tick
        bit     7,a
        jr      nz,p129_hdd_complete_tick
        bit     0,a
        jr      nz,p129_hdd_complete_fail
        bit     3,a
        jr      z,p129_hdd_complete_ok
p129_hdd_complete_tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,p129_hdd_complete_loop
p129_hdd_complete_fail:
        pop     de
        scf
        ret
p129_hdd_complete_ok:
        pop     de
        or      a
        ret

_p129_hdd_present:     db 0
_p129_hdd_sector_valid: db 0
_p129_hdd_error:       db 0
_p129_hdd_last_status: db 0
_p129_hdd_capacity:    db 0,0,0,0
p129_hdd_identify:     ds 512,0
p129_hdd_sector:       ds 512,0
