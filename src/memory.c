#include "memory.h"

/*
 * Project129 physical-page accounting, version 0.1.0.
 *
 * This module does not probe, map, read or write physical RAM. The 1 MiB /
 * 64-page capacity is the Project129 ATM Turbo 2+ contract. Physical page
 * discovery and the hardware mapper are separate implementation stages.
 *
 * Return conventions:
 *   reserve/free/unpin: 0 success, nonzero rejected operation
 *   pin:               0 success, 1 invalid page, 2 page not allocated,
 *                      3 reference counter overflow
 *   alloc:             physical page number, or P129_MEMORY_PAGE_NONE
 *
 * Calls are serialized by the resident startup path (DI). Add interrupt-safe
 * locking only when the allocator is callable from IRQ/concurrent contexts.
 */

#define P129_PAGE_FREE      0u
#define P129_PAGE_RESERVED  1u
#define P129_PAGE_ALLOCATED 2u

static uint8_t p129_page_state[P129_MEMORY_PAGE_COUNT];
static uint8_t p129_page_refs[P129_MEMORY_PAGE_COUNT];
static uint8_t p129_memory_ready;

static uint8_t p129_page_valid(uint8_t page)
{
    return (uint8_t)(page < P129_MEMORY_PAGE_COUNT);
}

uint8_t p129_page_reserve(uint8_t page)
{
    if (!p129_page_valid(page)) return 1u;
    if (p129_page_state[page] == P129_PAGE_ALLOCATED) return 2u;

    p129_page_state[page] = P129_PAGE_RESERVED;
    p129_page_refs[page] = 0u;
    return 0u;
}

uint8_t p129_memory_init(void)
{
    uint16_t page;

    p129_memory_ready = 0u;
    for (page = 0u; page < P129_MEMORY_PAGE_COUNT; ++page) {
        p129_page_state[page] = P129_PAGE_FREE;
        p129_page_refs[page] = 0u;
    }

    if (p129_page_reserve(2u) != 0u) return 1u; /* W2 stack/control */
    if (p129_page_reserve(3u) != 0u) return 2u; /* video attributes */
    if (p129_page_reserve(5u) != 0u) return 3u; /* W1 resident code/data */
    if (p129_page_reserve(7u) != 0u) return 4u; /* video characters */

    p129_memory_ready = 1u;
    return 0u;
}

uint8_t p129_page_alloc_topdown(void)
{
    uint16_t page;

    if (!p129_memory_ready) return P129_MEMORY_PAGE_NONE;

    page = P129_MEMORY_PAGE_COUNT;
    while (page != 0u) {
        --page;
        if (p129_page_state[page] == P129_PAGE_FREE) {
            p129_page_state[page] = P129_PAGE_ALLOCATED;
            p129_page_refs[page] = 0u;
            return (uint8_t)page;
        }
    }
    return P129_MEMORY_PAGE_NONE;
}

uint8_t p129_page_free(uint8_t page)
{
    if (!p129_memory_ready || !p129_page_valid(page)) return 1u;
    if (p129_page_state[page] != P129_PAGE_ALLOCATED) return 2u;
    if (p129_page_refs[page] != 0u) return 3u;

    p129_page_state[page] = P129_PAGE_FREE;
    return 0u;
}

uint8_t p129_page_pin(uint8_t page)
{
    if (!p129_memory_ready || !p129_page_valid(page)) return 1u;
    if (p129_page_state[page] != P129_PAGE_ALLOCATED) return 2u;
    if (p129_page_refs[page] == 0xFFu) return 3u;

    ++p129_page_refs[page];
    return 0u;
}

uint8_t p129_page_unpin(uint8_t page)
{
    if (!p129_memory_ready || !p129_page_valid(page)) return 1u;
    if (p129_page_state[page] != P129_PAGE_ALLOCATED) return 2u;
    if (p129_page_refs[page] == 0u) return 3u;

    --p129_page_refs[page];
    return 0u;
}

uint8_t p129_page_refcount(uint8_t page)
{
    if (!p129_memory_ready || !p129_page_valid(page)) return 0xFFu;
    return p129_page_refs[page];
}

uint8_t p129_page_is_reserved(uint8_t page)
{
    if (!p129_memory_ready || !p129_page_valid(page)) return 0u;
    return (uint8_t)(p129_page_state[page] == P129_PAGE_RESERVED);
}

uint8_t p129_memory_free_count(void)
{
    uint16_t page;
    uint8_t count = 0u;

    if (!p129_memory_ready) return 0u;
    for (page = 0u; page < P129_MEMORY_PAGE_COUNT; ++page) {
        if (p129_page_state[page] == P129_PAGE_FREE) ++count;
    }
    return count;
}

/*
 * Exercises the actual allocator API:
 * fixed pages remain unavailable; top-down allocation exhausts all 60 free
 * pages; exhaustion is reported; pin references block release; the highest
 * freed page is reused; all pages are released back to the initial pool.
 * These checks operate on manager metadata and do not touch physical RAM.
 */
uint8_t p129_memory_selftest(void)
{
    static uint8_t allocated[P129_MEMORY_PAGE_COUNT];
    uint8_t count = 0u;
    uint8_t page;
    uint16_t i;

    if (!p129_memory_ready) return 1u;
    if (!p129_page_is_reserved(2u) ||
        !p129_page_is_reserved(3u) ||
        !p129_page_is_reserved(5u) ||
        !p129_page_is_reserved(7u)) return 2u;
    if (p129_page_free(2u) == 0u) return 3u;
    if (p129_page_pin(2u) == 0u) return 4u;

    while ((page = p129_page_alloc_topdown()) != P129_MEMORY_PAGE_NONE) {
        if (count >= P129_MEMORY_PAGE_COUNT) return 5u;
        allocated[count++] = page;
    }

    if (count != 60u) return 6u;
    if (allocated[0] != 63u || allocated[59] != 0u) return 7u;
    if (p129_memory_free_count() != 0u) return 8u;
    if (p129_page_alloc_topdown() != P129_MEMORY_PAGE_NONE) return 9u;

    page = allocated[0];
    if (p129_page_pin(page) != 0u) return 10u;
    if (p129_page_pin(page) != 0u) return 11u;
    if (p129_page_refcount(page) != 2u) return 12u;
    if (p129_page_free(page) == 0u) return 13u;
    if (p129_page_unpin(page) != 0u) return 14u;
    if (p129_page_refcount(page) != 1u) return 15u;
    if (p129_page_unpin(page) != 0u) return 16u;
    if (p129_page_unpin(page) == 0u) return 17u;
    if (p129_page_free(page) != 0u) return 18u;
    if (p129_page_alloc_topdown() != page) return 19u;

    for (i = 0u; i < count; ++i) {
        if (p129_page_free(allocated[i]) != 0u) return 20u;
    }
    if (p129_memory_free_count() != 60u) return 21u;
    if (p129_page_refcount(63u) != 0u) return 22u;

    return 0u;
}
