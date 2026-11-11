#include <stdint.h>

/*
 * Project129 Z88DK bootstrap.
 * The resident entry is supplied by entry.asm; this C routine is called only
 * after the assembly stub has disabled interrupts and established the stack.
 */

volatile uint8_t p129_debug_value;

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
    while (*text) {
        debug_putc((uint8_t)*text++);
    }
}

void main(void)
{
    debug_puts("[P129] Z88DK C ENTRY\r\n");
    debug_puts("[P129] BUILD: BOOTSTRAP-0.1.0\r\n");
    debug_puts("[P129] DEBUG PORT EF READY\r\n");
    debug_puts("[P129] OPTIONAL DRIVERS NOT STARTED\r\n");
    debug_puts("[P129] BOOTSTRAP IDLE\r\n");

    for (;;) {
        /* Keep the bootstrap deterministic; no IRQ or peripheral activity. */
    }
}
