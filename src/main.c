#include <stdint.h>

/*
 * Project129 Z88DK bootstrap.
 * Hardware-facing TR-DOS ROM call is isolated in trdos.asm; C owns the
 * catalogue validation and startup-stage reporting.
 */

volatile uint8_t p129_debug_value;
static volatile uint8_t * const p129_catalogue = (volatile uint8_t *)0xC800;

extern uint16_t p129_trdos_preload(void);\nextern void p129_ui_init(void);\nstatic uint8_t p129_ui_ready;

static void debug_putc(uint8_t value)
{
    p129_debug_value = value;
    __asm
        ld a,(_p129_debug_value)
        ld bc,00EFh
        out (c),a
    __endasm;
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

    debug_puts("[P129] C IMAGE EXECUTED\r\n");
    debug_puts("[P129] Z88DK C ENTRY\r\n");
    debug_puts("[P129] BUILD: BOOTSTRAP-0.2.0\r\n");
    debug_puts("[P129] DEBUG PORT EF READY\r\n");

    debug_puts("[TRDOS] DIRECTORY READ BEGIN\r\n");
    result = p129_trdos_preload();
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

    /* UI/W3 handoff is the next stage; no video or live IRQ is enabled here. */
    debug_puts("[P129] TR-DOS CATALOGUE PRELOADED\r\n");
    debug_puts("[P129] W3/UI INITIALIZATION PENDING\r\n");
    debug_puts("[P129] BOOTSTRAP IDLE\r\n");

    for (;;) {}
}
