#include "map.h"
#include "memory.h"

/* Project129 software page-map layer, version 0.1.0.
 * Mirrors Project127: W0=ROM, W1=P5, W2=P2, W3=P0.
 * ATM RAM page encoding is 0x7F-page; ports are 3FF7/7FF7/BFF7/FFF7.
 * No OUT instructions: physical mapping follows after resident/UI safety.
 */
static uint8_t p129_map_shadow[P129_MAP_WINDOW_COUNT];
static uint8_t p129_map_ready;
static uint8_t p129_map_txn_active;
static uint8_t p129_map_txn_committed;
static uint8_t p129_map_txn_window;
static uint8_t p129_map_txn_new_page;
static uint8_t p129_map_txn_old_page;
static uint8_t p129_map_txn_snapshot[P129_MAP_WINDOW_COUNT];
static uint8_t p129_map_w3_lease_active;
extern uint8_t p129_ui_quiesce(void);
extern uint8_t p129_ui_handoff_begin(void);
extern uint8_t p129_ui_handoff_end(void);
extern uint8_t p129_ui_resume(void);

uint8_t p129_map_init(void)
{
    if (!p129_page_is_reserved(0u) ||
        !p129_page_is_reserved(2u) ||
        !p129_page_is_reserved(5u)) return 1u;
    if (p129_map_txn_active) return 2u;
    p129_map_shadow[0] = P129_MAP_PAGE_ROM;
    p129_map_shadow[1] = 5u;
    p129_map_shadow[2] = 2u;
    p129_map_shadow[3] = 0u;
    p129_map_txn_active = 0u;
    p129_map_txn_committed = 0u;
    p129_map_ready = 1u;
    return 0u;
}

uint8_t p129_map_get_window(uint8_t window)
{
    if (!p129_map_ready || window >= P129_MAP_WINDOW_COUNT) return P129_MAP_PAGE_ROM;
    return p129_map_shadow[window];
}

uint16_t p129_map_window_port(uint8_t window)
{
    static const uint16_t ports[P129_MAP_WINDOW_COUNT] = {0x3FF7u, 0x7FF7u, 0xBFF7u, 0xFFF7u};
    if (window >= P129_MAP_WINDOW_COUNT) return 0u;
    return ports[window];
}

uint8_t p129_map_encode_page(uint8_t page)
{
    if (page >= P129_MEMORY_PAGE_COUNT) return P129_MAP_PAGE_ROM;
    return (uint8_t)(0x7Fu - page);
}

/* W3-only transaction; W0/W1/W2 are permanently protected. */
uint8_t p129_map_txn_begin(uint8_t window, uint8_t page, uint8_t protected_mask)
{
    uint8_t i;
    if (!p129_map_ready) return 1u;
    if (p129_map_txn_active) return 2u;
    if (window != 3u) return 3u;
    if (page >= P129_MEMORY_PAGE_COUNT) return 4u;
    if ((protected_mask & P129_MAP_PROTECT_W3) != 0u) return 5u;
    if (p129_page_is_reserved(page)) return 6u;
    if (!p129_page_is_allocated(page)) return 7u;
    if (p129_page_pin(page) != 0u) return 8u;
    for (i = 0u; i < P129_MAP_WINDOW_COUNT; ++i) p129_map_txn_snapshot[i] = p129_map_shadow[i];
    p129_map_txn_window = window;
    p129_map_txn_new_page = page;
    p129_map_txn_old_page = p129_map_shadow[window];
    p129_map_txn_committed = 0u;
    p129_map_txn_active = 1u;
    return 0u;
}

uint8_t p129_map_txn_commit(void)
{
    if (!p129_map_txn_active || p129_map_txn_committed) return 1u;
    if (p129_map_txn_window != 3u || p129_map_txn_new_page >= P129_MEMORY_PAGE_COUNT) return 2u;
    p129_map_shadow[p129_map_txn_window] = p129_map_txn_new_page;
    p129_map_txn_committed = 1u;
    return 0u;
}

uint8_t p129_map_txn_rollback(void)
{
    uint8_t i;
    if (!p129_map_txn_active) return 1u;
    for (i = 0u; i < P129_MAP_WINDOW_COUNT; ++i) p129_map_shadow[i] = p129_map_txn_snapshot[i];
    if (p129_page_unpin(p129_map_txn_new_page) != 0u) return 2u;
    p129_map_txn_active = 0u;
    p129_map_txn_committed = 0u;
    return 0u;
}

uint8_t p129_map_txn_accept(void)
{
    if (!p129_map_txn_active || !p129_map_txn_committed) return 1u;
    if (p129_map_txn_old_page < P129_MEMORY_PAGE_COUNT &&
        p129_page_is_allocated(p129_map_txn_old_page)) {
        if (p129_page_unpin(p129_map_txn_old_page) != 0u) return 2u;
    }
    p129_map_txn_active = 0u;
    p129_map_txn_committed = 0u;
    return 0u;
}

uint8_t p129_map_restore_boot(void)
{
    uint8_t old_page;
    if (!p129_map_ready || p129_map_txn_active) return 1u;
    old_page = p129_map_shadow[3];
    if (old_page != 0u && old_page < P129_MEMORY_PAGE_COUNT &&
        p129_page_is_allocated(old_page)) {
        if (p129_page_unpin(old_page) != 0u) return 2u;
    }
    p129_map_shadow[3] = 0u;
    return 0u;
}

/* W3 ownership orchestration over the software shadow map only. */
uint8_t p129_map_w3_lease_begin(uint8_t page)
{
    uint8_t status;
    if (!p129_map_ready || p129_map_w3_lease_active) return 1u;
    status = p129_ui_quiesce();
    if (status != 0u) return 2u;
    status = p129_ui_handoff_begin();
    if (status != 0u) {
        (void)p129_ui_resume();
        return 3u;
    }
    status = p129_map_txn_begin(3u, page, P129_MAP_PROTECT_FIXED);
    if (status == 0u) status = p129_map_txn_commit();
    if (status == 0u) status = p129_map_txn_accept();
    if (status != 0u) {
        if (p129_map_txn_active) (void)p129_map_txn_rollback();
        (void)p129_ui_handoff_end();
        (void)p129_ui_resume();
        return (uint8_t)(0x10u | status);
    }
    p129_map_w3_lease_active = 1u;
    return 0u;
}

uint8_t p129_map_w3_lease_end(void)
{
    uint8_t status;
    if (!p129_map_w3_lease_active) return 1u;
    status = p129_map_restore_boot();
    if (status != 0u) return 2u;
    status = p129_ui_handoff_end();
    if (status != 0u) return 3u;
    status = p129_ui_resume();
    if (status != 0u) return 4u;
    p129_map_w3_lease_active = 0u;
    return 0u;
}

uint8_t p129_map_w3_lease_selftest(void)
{
    uint8_t page;
    if (p129_map_w3_lease_active) return 1u;
    page = p129_page_alloc_topdown();
    if (page == P129_MEMORY_PAGE_NONE) return 2u;
    if (p129_map_w3_lease_begin(page) != 0u) {
        if (p129_page_refcount(page) == 0u) (void)p129_page_free(page);
        return 3u;
    }
    if (p129_map_get_window(3u) != page || p129_page_refcount(page) != 1u) return 4u;
    if (p129_map_w3_lease_end() != 0u) return 5u;
    if (p129_map_get_window(3u) != 0u || p129_page_refcount(page) != 0u) return 6u;
    if (p129_page_free(page) != 0u) return 7u;
    return 0u;
}

/* Allocator-backed commit/rollback/accept lifecycle; metadata only. */
uint8_t p129_map_selftest(void)
{
    uint8_t page;
    if (!p129_map_ready) return 1u;
    if (p129_map_get_window(0u) != P129_MAP_PAGE_ROM ||
        p129_map_get_window(1u) != 5u ||
        p129_map_get_window(2u) != 2u ||
        p129_map_get_window(3u) != 0u) return 2u;
    if (p129_map_window_port(0u) != 0x3FF7u ||
        p129_map_window_port(1u) != 0x7FF7u ||
        p129_map_window_port(2u) != 0xBFF7u ||
        p129_map_window_port(3u) != 0xFFF7u ||
        p129_map_window_port(4u) != 0u) return 3u;
    if (p129_map_encode_page(0u) != 0x7Fu ||
        p129_map_encode_page(1u) != 0x7Eu ||
        p129_map_encode_page(63u) != 0x40u ||
        p129_map_encode_page(64u) != P129_MAP_PAGE_ROM) return 3u;

    page = p129_page_alloc_topdown();
    if (page == P129_MEMORY_PAGE_NONE) return 4u;
    if (p129_map_txn_begin(2u, page, 0u) == 0u) return 5u;
    if (p129_map_txn_begin(3u, page, P129_MAP_PROTECT_W3) == 0u) return 6u;
    if (p129_map_txn_begin(3u, page, P129_MAP_PROTECT_FIXED) != 0u) return 7u;
    if (p129_page_refcount(page) != 1u) return 8u;
    if (p129_map_txn_commit() != 0u) return 9u;
    if (p129_map_get_window(3u) != page) return 10u;
    if (p129_map_txn_rollback() != 0u) return 11u;
    if (p129_map_get_window(3u) != 0u) return 12u;
    if (p129_page_refcount(page) != 0u) return 13u;
    if (p129_page_free(page) != 0u) return 14u;

    page = p129_page_alloc_topdown();
    if (page == P129_MEMORY_PAGE_NONE) return 15u;
    if (p129_map_txn_begin(3u, page, P129_MAP_PROTECT_FIXED) != 0u) return 16u;
    if (p129_map_txn_commit() != 0u) return 17u;
    if (p129_map_txn_accept() != 0u) return 18u;
    if (p129_map_get_window(3u) != page) return 19u;
    if (p129_page_refcount(page) != 1u) return 20u;
    if (p129_page_free(page) == 0u) return 21u;
    if (p129_map_restore_boot() != 0u) return 22u;
    if (p129_map_get_window(3u) != 0u) return 23u;
    if (p129_page_refcount(page) != 0u) return 24u;
    if (p129_page_free(page) != 0u) return 25u;
    return 0u;
}
