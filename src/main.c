#include <stdint.h>

/* Project129 bootstrap: ATM UI is brought up before storage/services. */
volatile uint8_t p129_debug_value;
volatile uint8_t p129_ui_ready;
static volatile uint8_t * const p129_catalogue = (volatile uint8_t *)0xC800;

extern volatile uint8_t p129_trdos_result;
extern void p129_ui_init(void);
extern void p129_ui_putc(uint8_t value);
extern void p129_ui_clock_update(void);
extern void p129_rtc_probe(void);
extern void p129_rtc_read_current(void);
extern volatile uint8_t p129_rtc_available;
extern volatile uint8_t p129_rtc_backend;
extern volatile char p129_rtc_hour[2];
extern volatile char p129_rtc_minute[2];
extern volatile char p129_rtc_second[2];
extern void p129_hdd_probe(void);
extern void p129_hdd_list_root(void);
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

    p129_ui_ready = 0; /* --no-crt: explicitly initialize BSS state. */
    debug_puts("[P129] C IMAGE EXECUTED\r\n");
    debug_puts("[P129] Z88DK C ENTRY\r\n");
    debug_puts("[P129] BUILD: BOOTSTRAP-0.3.10-FAT16-ROOT\r\n");
    debug_puts("[P129] DEBUG PORT EF READY\r\n");

    /* The resident ASM entry completed the legacy TR-DOS call before C. */
    debug_puts("[TRDOS] PRELOAD RETURNED TO RESIDENT ENTRY\r\n");

    /* Initialize the visible ATM console after the ROM disk operation. */
    p129_ui_init();
    p129_ui_ready = 1;
    debug_puts("[P129] ATM RG6 80X25 UI READY\r\n");
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
    debug_puts("[P129] BOOTSTRAP IDLE\r\n");

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
