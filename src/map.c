#include "map.h"
#include "memory.h"

/* Project129 ATM page mapper, version 0.2.0.
 * Hardware contract: ATM2+ hidden page ports, W3=#FFF7, data=0x7F-page.
 * W0/W1/W2 remain fixed; W3 is switched only after UI HANDOFF.
 * The UI's #0177 / #3D2F trampoline keeps DOSEN/shadow ports accessible.
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
#define P129_MAP_BANK_DEPTH_MAX 8u
static uint8_t p129_map_bank_stack[P129_MAP_BANK_DEPTH_MAX];
static uint8_t p129_map_bank_depth;
volatile uint8_t p129_map_hw_encoded;
extern void p129_map_hw_write(void);
extern uint8_t p129_ui_quiesce(void);
extern uint8_t p129_ui_handoff_begin(void);
extern uint8_t p129_ui_handoff_end(void);
extern uint8_t p129_ui_resume(void);
static uint8_t p129_map_hw_apply(uint8_t page);

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
    p129_map_w3_lease_active = 0u;
    p129_map_bank_depth = 0u;
    /* UI initialization already leaves W3=P0 and keeps shadow ports open.
     * Do not issue a page OUT while the UI still owns W3.
     */
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

/* Physical backend. Caller must own W3 or be initializing it after UI setup. */
static uint8_t p129_map_hw_apply(uint8_t page)
{
    if (page >= P129_MEMORY_PAGE_COUNT) return 1u;
    p129_map_hw_encoded = p129_map_encode_page(page);
    p129_map_hw_write();
    return 0u;
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
    if (p129_map_hw_apply(p129_map_txn_new_page) != 0u) return 3u;
    p129_map_shadow[p129_map_txn_window] = p129_map_txn_new_page;
    p129_map_txn_committed = 1u;
    return 0u;
}

uint8_t p129_map_txn_rollback(void)
{
    uint8_t i;
    uint8_t current_page;
    if (!p129_map_txn_active) return 1u;
    current_page = p129_map_shadow[3];
    if (p129_map_txn_committed &&
        p129_map_hw_apply(p129_map_txn_snapshot[3]) != 0u) return 2u;
    if (p129_page_unpin(p129_map_txn_new_page) != 0u) {
        if (p129_map_txn_committed) (void)p129_map_hw_apply(current_page);
        return 3u;
    }
    for (i = 0u; i < P129_MAP_WINDOW_COUNT; ++i) p129_map_shadow[i] = p129_map_txn_snapshot[i];
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
    if (p129_map_hw_apply(0u) != 0u) return 2u;
    if (old_page != 0u && old_page < P129_MEMORY_PAGE_COUNT &&
        p129_page_is_allocated(old_page)) {
        if (p129_page_unpin(old_page) != 0u) {
            (void)p129_map_hw_apply(old_page);
            return 3u;
        }
    }
    p129_map_shadow[3] = 0u;
    return 0u;
}

/* W3 ownership orchestration: quiesce UI, then physically map the leased page. */
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

/* Nested bank ownership stack. Every W3 transition is a physical #FFF7 OUT. */
uint8_t p129_map_w3_bank_enter(uint8_t page)
{
    if (!p129_map_ready || page >= P129_MEMORY_PAGE_COUNT) return 1u;
    if (!p129_page_is_allocated(page) || p129_page_is_reserved(page)) return 2u;
    if (p129_map_bank_depth >= P129_MAP_BANK_DEPTH_MAX) return 3u;
    if (p129_map_bank_depth == 0u) {
        if (p129_map_w3_lease_active) return 4u;
        if (p129_map_w3_lease_begin(page) != 0u) return 5u;
        p129_map_bank_stack[0] = page;
        p129_map_bank_depth = 1u;
        return 0u;
    }
    if (p129_map_shadow[3] == page) return 6u;
    if (p129_page_pin(page) != 0u) return 7u;
    if (p129_map_hw_apply(page) != 0u) {
        (void)p129_page_unpin(page);
        return 8u;
    }
    p129_map_bank_stack[p129_map_bank_depth] = page;
    p129_map_shadow[3] = page;
    ++p129_map_bank_depth;
    return 0u;
}

uint8_t p129_map_w3_bank_leave(void)
{
    uint8_t current, previous;
    if (!p129_map_ready || p129_map_bank_depth == 0u) return 1u;
    if (p129_map_bank_depth == 1u) {
        p129_map_bank_depth = 0u;
        if (p129_map_w3_lease_end() != 0u) {
            p129_map_bank_depth = 1u;
            return 2u;
        }
        return 0u;
    }
    current = p129_map_bank_stack[p129_map_bank_depth - 1u];
    previous = p129_map_bank_stack[p129_map_bank_depth - 2u];
    if (p129_map_shadow[3] != current) return 3u;
    if (p129_map_hw_apply(previous) != 0u) return 4u;
    p129_map_shadow[3] = previous;
    if (p129_page_unpin(current) != 0u) {
        (void)p129_map_hw_apply(current);
        p129_map_shadow[3] = current;
        return 5u;
    }
    --p129_map_bank_depth;
    return 0u;
}

/* Verify #FFF7 selects independent RAM pages through W3. Original bytes are
 * saved/restored; UI remains in HANDOFF for the entire physical access test.
 */
uint8_t p129_map_w3_hw_selftest(void)
{
    uint8_t p1 = P129_MEMORY_PAGE_NONE;
    uint8_t p2 = P129_MEMORY_PAGE_NONE;
    uint8_t p1a = 0u, p1b = 0u, p2a = 0u, p2b = 0u;
    uint8_t p1_saved = 0u, p2_saved = 0u, p2_pinned = 0u, lease = 0u;
    uint8_t result = 0u;
    volatile uint8_t *window = (volatile uint8_t *)0xC000u;

    if (!p129_map_ready || p129_map_bank_depth != 0u || p129_map_w3_lease_active) return 1u;
    p1 = p129_page_alloc_topdown();
    if (p1 == P129_MEMORY_PAGE_NONE) return 2u;
    p2 = p129_page_alloc_topdown();
    if (p2 == P129_MEMORY_PAGE_NONE) {
        (void)p129_page_free(p1);
        return 3u;
    }
    if (p129_map_w3_lease_begin(p1) != 0u) {
        result = 4u;
        goto cleanup;
    }
    lease = 1u;
    p1a = window[0x0100u];
    p1b = window[0x3F00u];
    p1_saved = 1u;
    window[0x0100u] = 0xA5u;
    window[0x3F00u] = 0x5Au;

    if (p129_page_pin(p2) != 0u) {
        result = 5u;
        goto cleanup;
    }
    p2_pinned = 1u;
    if (p129_map_hw_apply(p2) != 0u) {
        result = 6u;
        goto cleanup;
    }
    p129_map_shadow[3] = p2;
    p2a = window[0x0100u];
    p2b = window[0x3F00u];
    p2_saved = 1u;
    window[0x0100u] = 0x3Cu;
    window[0x3F00u] = 0xC3u;

    if (p129_map_hw_apply(p1) != 0u) {
        result = 7u;
        goto cleanup;
    }
    p129_map_shadow[3] = p1;
    if (window[0x0100u] != 0xA5u || window[0x3F00u] != 0x5Au) {
        result = 8u;
        goto cleanup;
    }
    if (p129_map_hw_apply(p2) != 0u) {
        result = 9u;
        goto cleanup;
    }
    p129_map_shadow[3] = p2;
    if (window[0x0100u] != 0x3Cu || window[0x3F00u] != 0xC3u) {
        result = 10u;
        goto cleanup;
    }

cleanup:
    if (lease) {
        if (p2_saved) {
            (void)p129_map_hw_apply(p2);
            p129_map_shadow[3] = p2;
            window[0x0100u] = p2a;
            window[0x3F00u] = p2b;
        }
        if (p1_saved) {
            (void)p129_map_hw_apply(p1);
            p129_map_shadow[3] = p1;
            window[0x0100u] = p1a;
            window[0x3F00u] = p1b;
        }
        if (p2_pinned) {
            if (p129_page_unpin(p2) != 0u && result == 0u) result = 11u;
        }
        if (p129_map_w3_lease_end() != 0u && result == 0u) result = 12u;
    } else if (p2_pinned) {
        if (p129_page_unpin(p2) != 0u && result == 0u) result = 13u;
    }
    if (p1 != P129_MEMORY_PAGE_NONE && p129_page_refcount(p1) == 0u) {
        if (p129_page_free(p1) != 0u && result == 0u) result = 14u;
    }
    if (p2 != P129_MEMORY_PAGE_NONE && p129_page_refcount(p2) == 0u) {
        if (p129_page_free(p2) != 0u && result == 0u) result = 15u;
    }
    return result;
}

uint8_t p129_map_w3_bank_depth(void)
{
    return p129_map_bank_depth;
}

uint8_t p129_map_w3_bank_selftest(void)
{
    uint8_t p1, p2, p3;
    if (p129_map_bank_depth != 0u || p129_map_w3_lease_active) return 1u;
    p1 = p129_page_alloc_topdown();
    p2 = p129_page_alloc_topdown();
    p3 = p129_page_alloc_topdown();
    if (p1 == P129_MEMORY_PAGE_NONE || p2 == P129_MEMORY_PAGE_NONE ||
        p3 == P129_MEMORY_PAGE_NONE) return 2u;
    if (p129_map_w3_bank_enter(p1) != 0u) return 3u;
    if (p129_map_w3_bank_enter(p2) != 0u) return 4u;
    if (p129_map_w3_bank_enter(p3) != 0u) return 5u;
    if (p129_map_w3_bank_depth() != 3u || p129_map_get_window(3u) != p3) return 6u;
    if (p129_page_refcount(p1) != 1u || p129_page_refcount(p2) != 1u ||
        p129_page_refcount(p3) != 1u) return 7u;
    if (p129_map_w3_bank_leave() != 0u) return 8u;
    if (p129_map_get_window(3u) != p2 || p129_map_w3_bank_depth() != 2u ||
        p129_page_refcount(p3) != 0u || p129_page_refcount(p2) != 1u) return 9u;
    if (p129_map_w3_bank_leave() != 0u) return 10u;
    if (p129_map_get_window(3u) != p1 || p129_map_w3_bank_depth() != 1u ||
        p129_page_refcount(p2) != 0u || p129_page_refcount(p1) != 1u) return 11u;
    if (p129_map_w3_bank_leave() != 0u) return 12u;
    if (p129_map_get_window(3u) != 0u || p129_map_w3_bank_depth() != 0u ||
        p129_page_refcount(p1) != 0u) return 13u;
    if (p129_page_free(p1) != 0u || p129_page_free(p2) != 0u ||
        p129_page_free(p3) != 0u) return 14u;
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
