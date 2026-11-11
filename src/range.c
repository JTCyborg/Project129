#include <stdint.h>

/*
 * Project129 UINT32 physical-range API.
 *
 * Validates a half-open range [start, start + length) against the 1 MiB
 * ATM host physical address space. This module performs arithmetic only:
 * it never maps a page or reads/writes physical RAM.
 *
 * Return: 0 = valid, 1 = invalid (overflow or outside physical RAM).
 */
uint8_t p129_range_validate(uint32_t start, uint32_t length)
{
    uint32_t end;

    /* Reject uint32 addition overflow before computing the exclusive end. */
    if (length > (uint32_t)(0xFFFFFFFFUL - start)) {
        return 1;
    }

    end = start + length;
    if (end > 0x00100000UL) {
        return 1;
    }

    return 0;
}

/*
 * Boundary regression checks ported from Project127's p127_range_selftest.
 * Returns zero on success, otherwise the 1-based failed test number.
 */
uint8_t p129_range_selftest(void)
{
    if (p129_range_validate(0x00000000UL, 0x00000000UL) != 0) return 1;
    if (p129_range_validate(0x000FFFFFUL, 1UL) != 0) return 2;
    if (p129_range_validate(0x000FFFFFUL, 2UL) == 0) return 3;
    if (p129_range_validate(0x00000000UL, 0x00100000UL) != 0) return 4;
    if (p129_range_validate(0x00100000UL, 0UL) != 0) return 5;
    if (p129_range_validate(0x00100000UL, 1UL) == 0) return 6;
    if (p129_range_validate(0x00100001UL, 0UL) == 0) return 7;
    if (p129_range_validate(0xFFFFFFFFUL, 1UL) == 0) return 8;

    return 0;
}
