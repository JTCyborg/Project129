#include "bank.h"
#include "memory.h"
#include "map.h"
void p129_bank_module_init(p129_bank_module_t *m) { if(m){m->magic=0u;m->size=0u;m->page_count=0u;} }
uint8_t p129_bank_module_alloc(p129_bank_module_t *m, uint32_t size) {
 uint32_t count,i;
 if(!m||!size||size>(uint32_t)P129_BANK_MAX_PAGES*P129_BANK_PAGE_SIZE)return 1u;
 if(m->magic==P129_BANK_MAGIC)return 2u;
 count=(size+P129_BANK_PAGE_SIZE-1u)/P129_BANK_PAGE_SIZE;
 m->magic=0u;m->size=0u;m->page_count=0u;
 for(i=0u;i<count;++i){uint8_t p=p129_page_alloc_topdown();if(p==P129_MEMORY_PAGE_NONE){while(m->page_count){--m->page_count;(void)p129_page_free(m->pages[m->page_count]);}return 3u;}m->pages[m->page_count++]=p;}
 m->size=size;m->magic=P129_BANK_MAGIC;return 0u;
}
uint8_t p129_bank_module_release(p129_bank_module_t *m) {
 uint8_t i;if(!m||m->magic!=P129_BANK_MAGIC||!m->page_count||m->page_count>P129_BANK_MAX_PAGES)return 1u;
 for(i=0u;i<m->page_count;++i)if(!p129_page_is_allocated(m->pages[i])||p129_page_refcount(m->pages[i]))return 2u;
 for(i=0u;i<m->page_count;++i)if(p129_page_free(m->pages[i]))return 3u;
 m->magic=0u;m->size=0u;m->page_count=0u;return 0u;
}
static uint8_t p129_bank_module_transfer(p129_bank_module_t *m,uint32_t offset,uint8_t *buffer,uint16_t length,uint8_t wr) {
 uint32_t left=length,pos=offset;if(!m||m->magic!=P129_BANK_MAGIC||!m->page_count||m->page_count>P129_BANK_MAX_PAGES)return 1u;
 if(offset>m->size||left>m->size-offset)return 2u;if(length&&!buffer)return 3u;
 while(left){uint8_t index=(uint8_t)(pos/P129_BANK_PAGE_SIZE);uint16_t off=(uint16_t)(pos%P129_BANK_PAGE_SIZE),n=(uint16_t)(P129_BANK_PAGE_SIZE-off),i;volatile uint8_t *w=(volatile uint8_t *)0xC000u;
  if(index>=m->page_count)return 4u;if(n>left)n=(uint16_t)left;if(p129_map_w3_bank_enter(m->pages[index]))return 5u;
  if(wr){for(i=0u;i<n;++i)w[off+i]=buffer[i];}else{for(i=0u;i<n;++i)buffer[i]=w[off+i];}
  if(p129_map_w3_bank_leave())return 6u;buffer+=n;pos+=n;left-=n;
 }return 0u;
}
uint8_t p129_bank_module_write(p129_bank_module_t *m,uint32_t o,const uint8_t *s,uint16_t n){return p129_bank_module_transfer(m,o,(uint8_t *)s,n,1u);}
uint8_t p129_bank_module_read(p129_bank_module_t *m,uint32_t o,uint8_t *d,uint16_t n){return p129_bank_module_transfer(m,o,d,n,0u);}
uint8_t p129_bank_module_selftest(void) {
 p129_bank_module_t m;uint8_t s[64],d[64],i,e=0u;p129_bank_module_init(&m);
 if(p129_map_w3_bank_depth())return 1u;if(p129_bank_module_alloc(&m,65536UL+64UL))return 2u;
 if(m.page_count!=5u){e=3u;goto done;}for(i=0u;i<64u;++i){s[i]=(uint8_t)(i*13u+0x37u);d[i]=0u;}
 if(p129_bank_module_write(&m,65520UL,s,64u)){e=4u;goto done;}if(p129_bank_module_read(&m,65520UL,d,64u)){e=5u;goto done;}
 for(i=0u;i<64u;++i)if(s[i]!=d[i]){e=6u;break;}
 done:while(p129_map_w3_bank_depth()){if(p129_map_w3_bank_leave()){if(!e)e=7u;break;}}
 if(p129_bank_module_release(&m)&&!e)e=8u;return e;
}
