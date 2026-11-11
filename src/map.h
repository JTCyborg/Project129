#ifndef P129_MAP_H
#define P129_MAP_H

#include <stdint.h>

#define P129_MAP_WINDOW_COUNT 4u
#define P129_MAP_PAGE_ROM 0xFFu
#define P129_MAP_PROTECT_W0 0x01u
#define P129_MAP_PROTECT_W1 0x02u
#define P129_MAP_PROTECT_W2 0x04u
#define P129_MAP_PROTECT_W3 0x08u
#define P129_MAP_PROTECT_FIXED 0x07u

/* ATM2+ physical W3 mapper; W0/W1/W2 are fixed and protected. */
uint8_t p129_map_init(void);
uint8_t p129_map_get_window(uint8_t window);
uint16_t p129_map_window_port(uint8_t window);
uint8_t p129_map_encode_page(uint8_t page);
uint8_t p129_map_txn_begin(uint8_t window, uint8_t page, uint8_t protected_mask);
uint8_t p129_map_txn_commit(void);
uint8_t p129_map_txn_rollback(void);
uint8_t p129_map_txn_accept(void);
uint8_t p129_map_restore_boot(void);
uint8_t p129_map_selftest(void);
uint8_t p129_map_w3_lease_begin(uint8_t page);
uint8_t p129_map_w3_lease_end(void);
uint8_t p129_map_w3_lease_selftest(void);
uint8_t p129_map_w3_bank_enter(uint8_t page);
uint8_t p129_map_w3_bank_leave(void);
uint8_t p129_map_w3_bank_depth(void);
uint8_t p129_map_w3_bank_selftest(void);
uint8_t p129_map_w3_hw_selftest(void);

#endif
