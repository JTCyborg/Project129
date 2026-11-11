#include <stdint.h>
#include "bank.h"

/* Project129 bootstrap: ATM UI is brought up before storage/services. */
volatile uint8_t p129_debug_value;
volatile uint8_t p129_ui_ready;
static volatile uint8_t * const p129_catalogue = (volatile uint8_t *)0xC800;
static p129_bank_module_t p129_loaded_module;
static uint32_t p129_loaded_module_size;
static uint8_t p129_bank_storage_ready;

extern volatile uint8_t p129_trdos_result;
extern void p129_ui_init(void);
extern void p129_ui_putc(uint8_t value);
extern void p129_ui_clock_update(void);
extern uint8_t p129_ui_lease_selftest(void);
extern void p129_rtc_probe(void);
extern void p129_rtc_read_current(void);
extern volatile uint8_t p129_rtc_available;
extern volatile uint8_t p129_rtc_backend;
extern volatile char p129_rtc_hour[2];
extern volatile char p129_rtc_minute[2];
extern volatile char p129_rtc_second[2];
extern void p129_hdd_probe(void);
extern void p129_hdd_list_root(void);
extern uint8_t p129_fat16_load_root_file(const char *name83, p129_bank_module_t *module, uint32_t *size_out);
extern uint8_t p129_range_selftest(void);
extern uint8_t p129_keyboard_init(void);
extern uint8_t p129_keyboard_poll(void);
extern void p129_keyboard_delay_window(void);
extern void p129_speaker_test_tone(void);
extern uint8_t p129_memory_init(void);
extern uint8_t p129_memory_selftest(void);
extern uint8_t p129_memory_free_count(void);
extern uint8_t p129_map_init(void);
extern uint8_t p129_map_selftest(void);
extern uint8_t p129_map_w3_lease_selftest(void);
extern uint8_t p129_map_w3_bank_selftest(void);
extern uint8_t p129_map_w3_hw_selftest(void);
extern uint8_t p129_map_page_copy_selftest(void);
extern uint8_t p129_bank_module_selftest(void);
extern volatile uint8_t p129_keyboard_xt_active;
extern volatile uint8_t p129_keyboard_lastscan;
extern volatile uint8_t p129_keyboard_r2;
extern volatile uint8_t p129_keyboard_r3;
extern volatile uint8_t p129_keyboard_r4;
extern volatile uint8_t p129_keyboard_r5;
extern volatile uint8_t p129_keyboard_matrix[8];
extern volatile uint8_t p129_hdd_present;
extern volatile uint8_t p129_hdd_sector_valid;
extern volatile uint8_t p129_hdd_error;
extern volatile uint8_t p129_hdd_last_status;
extern volatile uint8_t p129_hdd_capacity[4];

static void debug_putc(uint8_t value)
{
    p129_debug_value = value;
    __asm
        ld a,(_p129_debug_value)
        ld bc,00EFh
        out (c),a
    __endasm;

    if (p129_ui_ready) {
        p129_ui_putc(value);
    }
}

static void debug_puts(const char *text)
{
    while (*text) debug_putc((uint8_t)*text++);
}

static void debug_hex8(uint8_t value)
{
    uint8_t digit;
    digit = (uint8_t)(value >> 4);
    debug_putc((uint8_t)(digit < 10 ? '0' + digit : 'A' + digit - 10));
    digit = (uint8_t)(value & 0x0f);
    debug_putc((uint8_t)(digit < 10 ? '0' + digit : 'A' + digit - 10));
}


static void trdos_print_catalogue(void)
{
    uint16_t offset;
    uint8_t i;
    uint8_t end;
    uint8_t type;
    uint8_t first;
    uint8_t ch;

    debug_puts("[TR-DOS] CATALOGUE FILES\r\n");
    for (offset = 0; offset < 2048; offset += 16) {
        first = p129_catalogue[offset];
        type = p129_catalogue[offset + 8];
        if (first == 0 || first == 1) continue;
        if (type != 'B' && type != 'C' && type != 'D' && type != '#') continue;

        end = 8;
        while (end && p129_catalogue[offset + end - 1] == ' ') --end;
        debug_puts("  ");
        for (i = 0; i < end; ++i) {
            ch = p129_catalogue[offset + i];
            if (ch < 32 || ch > 126) ch = '?';
            debug_putc(ch);
        }
        if (end) {
            debug_putc('.');
            debug_putc(type);
        }
        debug_puts("\r\n");
    }
}

static uint8_t trdos_count_entries(void)
{
    uint16_t offset;
    uint8_t count = 0;

    for (offset = 0; offset < 2048; offset += 16) {
        uint8_t first = p129_catalogue[offset];
        uint8_t type = p129_catalogue[offset + 8];

        if (first == 0 || first == 1) continue;
        if (type == 'B' || type == 'C' || type == 'D' || type == '#') {
            ++count;
        }
    }
    return count;
}

void p129_c_entry(void)
{
    uint16_t result;
    uint8_t files;
    volatile uint16_t rtc_poll_divider;
    uint8_t rtc_poll_phase;
    char last_second_tens;
    char last_second_ones;
    uint8_t keyboard_idle_windows;

    p129_ui_ready = 0; /* --no-crt: explicitly initialize BSS state. */
    debug_puts("[P129] C IMAGE EXECUTED\r\n");
    debug_puts("[P129] Z88DK C ENTRY\r\n");
    debug_puts("[P129] BUILD: BOOTSTRAP-0.3.24-MULTIPAGE-MODULE-IO\r\n");
    debug_puts("[P129] DEBUG PORT EF READY\r\n");

    /* The resident ASM entry completed the legacy TR-DOS call before C. */
    debug_puts("[TRDOS] PRELOAD RETURNED TO RESIDENT ENTRY\r\n");

    /* Initialize the visible ATM console after the ROM disk operation. */
    p129_ui_init();
    p129_ui_ready = 1;
    debug_puts("[P129] ATM RG6 80X25 UI READY\r\n");
    debug_puts("[UI] W3 LEASE TRANSITIONS BEGIN\r\n");
    if (p129_ui_lease_selftest() == 0u) {
        debug_puts("[UI] ACTIVE/QUIESCED/HANDOFF/RESUME PASS\r\n");
    } else {
        debug_puts("[UI] W3 LEASE FAILED\r\n");
    }
    result = p129_trdos_result;
    if (result != 0) {
        debug_puts("[TRDOS] DIRECTORY READ FAILED\r\n");
        debug_puts("[TRDOS] ROM ERROR #5D0F=");
        debug_hex8(*(volatile uint8_t *)0x5D0F);
        debug_puts(" STATUS #5D10=");
        debug_hex8(*(volatile uint8_t *)0x5D10);
        debug_puts("\r\n[P129] SAFE IDLE\r\n");
        for (;;) {}
    }

    files = trdos_count_entries();
    debug_puts("[TRDOS] DIRECTORY READ OK; 8 SECTORS / 2048 BYTES\r\n");
    debug_puts("[TRDOS] FILE COUNT=");
    debug_hex8(files);
    debug_puts("\r\n");
    debug_puts("[P129] TR-DOS CATALOGUE PRELOADED\r\n");
    trdos_print_catalogue();

    debug_puts("[RTC] DS12887 PROBE BEGIN (GLUK/SMUC)\r\n");
    p129_rtc_probe();
    if (p129_rtc_available) {
        p129_rtc_read_current();
        p129_ui_clock_update();
        if (p129_rtc_hour[0] == '?') {
            debug_puts("[RTC] DS12887 ONLINE; TIME READ FAILED\r\n");
        } else {
            debug_puts("[RTC] DS12887 ONLINE; BACKEND=");
            debug_puts(p129_rtc_backend ? "SMUC" : "GLUK");
            debug_puts("; TIME=");
            debug_putc((uint8_t)p129_rtc_hour[0]);
            debug_putc((uint8_t)p129_rtc_hour[1]);
            debug_putc(':');
            debug_putc((uint8_t)p129_rtc_minute[0]);
            debug_putc((uint8_t)p129_rtc_minute[1]);
            debug_putc(':');
            debug_putc((uint8_t)p129_rtc_second[0]);
            debug_putc((uint8_t)p129_rtc_second[1]);
            debug_puts("\r\n");
        }
    } else {
        p129_ui_clock_update();
        debug_puts("[RTC] DS12887 NOT DETECTED / INVALID STATUS\r\n");
    }
    debug_puts("[HDD] NEMO IDE MASTER PROBE BEGIN\r\n");
    p129_hdd_probe();
    if (p129_hdd_present) {
        debug_puts("[HDD] IDENTIFY DEVICE OK; LBA28 SECTORS=");
        debug_hex8(p129_hdd_capacity[3]);
        debug_hex8(p129_hdd_capacity[2]);
        debug_hex8(p129_hdd_capacity[1]);
        debug_hex8(p129_hdd_capacity[0]);
        if (p129_hdd_sector_valid) {
            debug_puts("\r\n[HDD] LBA 63 READ OK; BPB 512B; SIGNATURE 55AA\r\n");
            p129_hdd_list_root();
        } else {
            debug_puts("\r\n[HDD] LBA 63 READ/BPB VALIDATION FAILED; ERROR=");
            debug_hex8(p129_hdd_error);
            debug_puts(" STATUS=");
            debug_hex8(p129_hdd_last_status);
            debug_puts("\r\n");
        }
    } else {
        debug_puts("[HDD] PROBE FAILED; ERROR=");
        debug_hex8(p129_hdd_error);
        debug_puts(" STATUS=");
        debug_hex8(p129_hdd_last_status);
        debug_puts("\r\n");
    }
    debug_puts("[RANGE] UINT32 API SELFTEST BEGIN\r\n");
    {
        uint8_t range_error = p129_range_selftest();
        if (range_error == 0) {
            debug_puts("[RANGE] UINT32 API SELFTEST PASS; LIMIT=00100000\r\n");
        } else {
            debug_puts("[RANGE] UINT32 API SELFTEST FAILED; TEST=");
            debug_hex8(range_error);
            debug_puts("\r\n");
        }
    }
    debug_puts("[KBD] INIT\r\n");
    if (p129_keyboard_init()) {
        debug_puts("[KBD] ATM XT ACTIVE\r\n");
    } else {
        debug_puts("[KBD] ZX FALLBACK\r\n");
    }

    debug_puts("[P129] KEYBOARD MONITOR\r\n");
    keyboard_idle_windows = 20; /* Project127: 41 windows ~= 10 s; 20 ~= 5 s. */

    /* Restart the inactivity window on every observed key transition. */
    for (;;) {
        if (p129_keyboard_poll()) {
            keyboard_idle_windows = 20;
            if (p129_keyboard_xt_active) {
                debug_puts("[KBD] LAST=");
                debug_hex8(p129_keyboard_lastscan);
                debug_puts(" R2=");
                debug_hex8(p129_keyboard_r2);
                debug_puts(" R3=");
                debug_hex8(p129_keyboard_r3);
                debug_puts(" R4=");
                debug_hex8(p129_keyboard_r4);
                debug_puts(" R5=");
                debug_hex8(p129_keyboard_r5);
                debug_puts("\r\n");
            } else {
                uint8_t k;
                debug_puts("[KBD] ZX MATRIX=");
                for (k = 0; k < 8; ++k) {
                    debug_hex8(p129_keyboard_matrix[k]);
                    debug_putc(' ');
                }
                debug_puts("\r\n");
            }
        }
        p129_keyboard_delay_window();
        --keyboard_idle_windows;
        if (keyboard_idle_windows == 0) break;
    }
    debug_puts("[KBD] DONE\r\n");
    debug_puts("[P129] KEYBOARD COMPLETE\r\n");

    debug_puts("[SPEAKER] ATM #FE D4 TONE BEGIN; BORDER/TAPE STATE=0\r\n");
    p129_speaker_test_tone();
    debug_puts("[SPEAKER] TONE END\r\n");
    debug_puts("[P129] SPEAKER SMOKE TEST COMPLETE\r\n");

    debug_puts("[MEM] PHYSICAL PAGE MANAGER INIT BEGIN\r\n");
    if (p129_memory_init() != 0u) {
        debug_puts("[MEM] INIT FAILED\r\n");
    } else {
        debug_puts("[MEM] MODEL=1M PAGES=64 PAGE_SIZE=16K\r\n");
        debug_puts("[MEM] RESERVED=P0:BOOT-W3 P2:STACK P3:ATTR P5:RESIDENT P7:CHAR\r\n");
        debug_puts("[MEM] TOP-DOWN ALLOCATOR/PIN SELFTEST BEGIN\r\n");
        result = p129_memory_selftest();
        if (result == 0u) {
            debug_puts("[MEM] TOP-DOWN ALLOCATOR/PIN SELFTEST PASS; FREE=");
            debug_hex8(p129_memory_free_count());
            debug_puts("\r\n");
        } else {
            debug_puts("[MEM] TOP-DOWN ALLOCATOR/PIN SELFTEST FAILED; TEST=");
            debug_hex8((uint8_t)result);
            debug_puts("\r\n");
        }
        debug_puts("[MAP] ATM2+ PHYSICAL W3 PAGE MAP INIT BEGIN\r\n");
        if (p129_map_init() != 0u) {
            debug_puts("[MAP] INIT FAILED\r\n");
        } else {
            debug_puts("[MAP] W0=ROM W1=P5 W2=P2 W3=P0; PHYSICAL W3 #FFF7\r\n");
            result = p129_map_selftest();
            if (result == 0u) {
                debug_puts("[MAP] W3 TRANSACTION COMMIT/ROLLBACK/PIN PASS\r\n");
                result = p129_map_w3_lease_selftest();
                if (result == 0u) {
                    debug_puts("[MAP] W3 UI LEASE / PAGE PIN / RESTORE PASS\r\n");
                    result = p129_map_w3_hw_selftest();
                    if (result == 0u) {
                        debug_puts("[MAP] PHYSICAL W3 PAGE SWITCH / ISOLATION PASS\r\n");
                        result = p129_map_w3_bank_selftest();
                        if (result == 0u) {
                            debug_puts("[BANK] NESTED W3 ENTER/LEAVE / PAGE PIN / RESTORE PASS\r\n");
                            result = p129_map_page_copy_selftest();
                            if (result == 0u) {
                                debug_puts("[MEM] PHYSICAL PAGE COPY / OVERLAP PASS\r\n");
                                result = p129_bank_module_selftest();
                                if (result == 0u) debug_puts("[BANK] MULTIPAGE MODULE IO / 64K BOUNDARY PASS\r\n");
                                else { debug_puts("[BANK] MULTIPAGE MODULE IO FAILED; TEST="); debug_hex8(result); debug_puts("\r\n"); }
                            } else {
                                debug_puts("[MEM] PHYSICAL PAGE COPY FAILED; TEST=");
                                debug_hex8(result);
                                debug_puts("\r\n");
                            }
                        } else {
                            debug_puts("[BANK] NESTED W3 SELFTEST FAILED; TEST=");
                            debug_hex8((uint8_t)result);
                            debug_puts("\r\n");
                        }
                    } else {
                        debug_puts("[MAP] PHYSICAL W3 PAGE SWITCH / ISOLATION FAILED; TEST=");
                        debug_hex8((uint8_t)result);
                        debug_puts("\r\n");
                    }
                } else {
                    debug_puts("[MAP] W3 UI LEASE FAILED; TEST=");
                    debug_hex8((uint8_t)result);
                    debug_puts("\r\n");
                }
            } else {
                debug_puts("[MAP] TRANSACTION SELFTEST FAILED; TEST=");
                debug_hex8((uint8_t)result);
                debug_puts("\r\n");
            }
        }
    }

    /* Load a real DOS file into the banked physical-page module store. */
    if (p129_bank_storage_ready && p129_hdd_present && p129_hdd_sector_valid &&
        p129_memory_free_count() != 0u) {
        static const char io_sys_name[11] = {'I','O',' ',' ',' ',' ',' ',' ','S','Y','S'};
        uint8_t load_status;
        debug_puts("[HDD] FAT16 LOAD IO.SYS BEGIN\r\n");
        load_status = p129_fat16_load_root_file(io_sys_name,
                                                &p129_loaded_module,
                                                &p129_loaded_module_size);
        if (load_status == 0u) {
            debug_puts("[HDD] FAT16 FILE LOAD PASS; SIZE=");
            debug_hex8((uint8_t)(p129_loaded_module_size >> 24));
            debug_hex8((uint8_t)(p129_loaded_module_size >> 16));
            debug_hex8((uint8_t)(p129_loaded_module_size >> 8));
            debug_hex8((uint8_t)p129_loaded_module_size);
            debug_puts("; PAGES=");
            debug_hex8(p129_loaded_module.page_count);
            debug_puts("\r\n");
        } else {
            debug_puts("[HDD] FAT16 FILE LOAD FAILED; ERROR=");
            debug_hex8(load_status);
            debug_puts("\r\n");
        }
    }

    rtc_poll_divider = 0;
    rtc_poll_phase = 0;
    last_second_tens = p129_rtc_second[0];
    last_second_ones = p129_rtc_second[1];
    for (;;) {
        if (!p129_rtc_available) continue;
        ++rtc_poll_divider;
        if (rtc_poll_divider == 0) {
            ++rtc_poll_phase;
            if (rtc_poll_phase >= 10) {
                rtc_poll_phase = 0;
                p129_rtc_read_current();
                if (p129_rtc_second[0] != last_second_tens ||
                    p129_rtc_second[1] != last_second_ones) {
                    last_second_tens = p129_rtc_second[0];
                    last_second_ones = p129_rtc_second[1];
                    p129_ui_clock_update();
                }
            }
        }
    }
}
