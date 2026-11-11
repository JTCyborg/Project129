#ifndef P129_MEMORY_H
#define P129_MEMORY_H

#include <stdint.h>

#define P129_MEMORY_PAGE_COUNT 64u
#define P129_MEMORY_PAGE_SIZE  16384UL
#define P129_MEMORY_LIMIT      0x00100000UL
#define P129_MEMORY_PAGE_NONE  0xFFu

/*
 * Fixed physical-page owners from the Project129 memory layout:
 * P2 = W2 resident stack/control; P5 = W1 resident code/data;
 * P3 = ATM video attributes; P7 = ATM video characters.
 * W0 is ROM and W3 remains the remappable window.
 */

uint8_t p129_memory_init(void);
uint8_t p129_memory_selftest(void);
uint8_t p129_page_reserve(uint8_t page);
uint8_t p129_page_alloc_topdown(void);
uint8_t p129_page_free(uint8_t page);
uint8_t p129_page_pin(uint8_t page);
uint8_t p129_page_unpin(uint8_t page);
uint8_t p129_page_refcount(uint8_t page);
uint8_t p129_page_is_reserved(uint8_t page);
uint8_t p129_memory_free_count(void);

#endif
