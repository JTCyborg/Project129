; Project129 TR-DOS packaging.
; BASIC boot handoff follows the proven Project127 startup sequence.
; The resident image itself is compiled by Z88DK at #6000.

        DEVICE ZXSPECTRUM128
        EMPTYTRD "disk_A.trd"

        ORG     #B000
CLEAR       EQU #FD
RANDOMIZE   EQU #F9
USR         EQU #C0
REM         EQU #EA
VAL         EQU #B0
OUT_CMD     EQU #DF

basic_loader:
; Line 10: initialize debug output and reserve memory below #6000.
        DB      0,10
        DW      l10_end-l10
l10:
        DB      OUT_CMD,"239",#0E,#00,#00,#EF,#00,#00
        DB      ",","1",#0E,#00,#00,#01,#00,#00,":"
        DB      CLEAR,"24000",#0E,#00,#00,#5D,#C0,#00,#0D
l10_end:

; BASIC-side progress marker before the TR-DOS interception.
        DB      0,11
        DW      l11_end-l11
l11:
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"80",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"49",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"50",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"57",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"93",34
        DB      #0D
l11_end:

; Exact Project127 TR-DOS interception sequence; only filename is adapted.
        DB      0,20
        DW      l20_end-l20
l20:
        DB      RANDOMIZE,USR,"15619",#0E,#00,#00
        DW      15619
        DB      0,#3A,REM,#3A
        DB      "LOAD ",34,"p129boot",34," CODE 24576",#0D
l20_end:

; Reached only after TR-DOS returns from the CODE load.
        DB      0,21
        DW      l21_end-l21
l21:
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"76",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"79",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"65",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"68",34
        DB      #0D
l21_end:

; Match Project127: restore debug channel 2, then enter the loaded image.
        DB      0,30
        DW      l30_end-l30
l30:
        DB      OUT_CMD,"239",#0E,#00,#00,#EF,#00,#00,","
        DB      "2",#0E,#00,#00,#02,#00,#00,":"
        DB      RANDOMIZE,USR,VAL,34,"24576",34,#0D
l30_end:
        DB      #80
basic_loader_end:

        SAVETRD "disk_A.trd","boot.B",basic_loader,basic_loader_end-basic_loader,10

        ORG     #6000
p129_boot_image:
        INCBIN  "build/P129BOOT.bin"
p129_boot_image_end:
        ASSERT  p129_boot_image_end > p129_boot_image
        SAVETRD "disk_A.trd","p129boot.C",p129_boot_image,p129_boot_image_end-p129_boot_image
