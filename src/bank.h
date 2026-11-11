#include <stdint.h>
#ifndef P129_BANK_H
#define P129_BANK_H
#include <stdint.h>
#define P129_BANK_MAX_PAGES 59u
#define P129_BANK_PAGE_SIZE 16384UL
#define P129_BANK_MAGIC 0x50313239UL
typedef struct { uint32_t magic; uint32_t size; uint8_t page_count; uint8_t pages[P129_BANK_MAX_PAGES]; } p129_bank_module_t;
void p129_bank_module_init(p129_bank_module_t *module);
uint8_t p129_bank_module_alloc(p129_bank_module_t *module, uint32_t size);
uint8_t p129_bank_module_release(p129_bank_module_t *module);
uint8_t p129_bank_module_write(p129_bank_module_t *module, uint32_t offset, const uint8_t *source, uint16_t length);
uint8_t p129_bank_module_read(p129_bank_module_t *module, uint32_t offset, uint8_t *destination, uint16_t length);
uint8_t p129_bank_module_selftest(void);
#endif
