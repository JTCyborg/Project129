#include <stdint.h>
#include "bank.h"
extern void p129_debug_puts(const char *text);
extern void p129_debug_hex8(uint8_t value);
extern void p129_debug_hex16(uint16_t value);
extern void p129_debug_hex32(uint32_t value);
#define P129_FAT16_PARTITION_LBA 63UL
#define P129_FAT16_SECTOR_SIZE 512u
#define P129_FAT16_MAX_FILE (P129_BANK_MAX_PAGES * P129_BANK_PAGE_SIZE)
#define P129_FAT16_EOC 0xFFF8u
extern uint8_t p129_hdd_read_sector_c(void);
extern volatile uint8_t p129_hdd_lba[4];
extern volatile uint8_t p129_hdd_sector[512];
extern volatile uint8_t p129_hdd_capacity[4];

static uint16_t p129_fat16_u16(const volatile uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}
static uint32_t p129_fat16_u32(const volatile uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static void p129_fat16_diag(uint16_t bps, uint8_t spc, uint16_t reserved,
                            uint8_t fats, uint16_t roots, uint16_t total16,
                            uint32_t total32, uint16_t fatsz,
                            uint32_t data_start, uint32_t clusters) {
    p129_debug_puts("[FAT16] BPB BPS="); p129_debug_hex16(bps);
    p129_debug_puts(" SPC="); p129_debug_hex8(spc);
    p129_debug_puts(" RESERVED="); p129_debug_hex16(reserved);
    p129_debug_puts(" FATS="); p129_debug_hex8(fats);
    p129_debug_puts(" ROOT_ENTRIES="); p129_debug_hex16(roots);
    p129_debug_puts(" TOTAL16="); p129_debug_hex16(total16);
    p129_debug_puts(" TOTAL32="); p129_debug_hex32(total32);
    p129_debug_puts(" FAT_SIZE="); p129_debug_hex16(fatsz);
    p129_debug_puts("\\r\
[FAT16] DATA_START="); p129_debug_hex32(data_start);
    p129_debug_puts(" CLUSTERS="); p129_debug_hex32(clusters);
    p129_debug_puts("\\r\
");
}

static uint8_t p129_fat16_read(uint32_t lba) {
    if (lba > 0x0FFFFFFFUL) return 1u;
    p129_hdd_lba[0]=(uint8_t)lba;
    p129_hdd_lba[1]=(uint8_t)(lba>>8);
    p129_hdd_lba[2]=(uint8_t)(lba>>16);
    p129_hdd_lba[3]=(uint8_t)(lba>>24);
    return p129_hdd_read_sector_c() ? 2u : 0u;
}

/* name83: exactly eleven uppercase/padded bytes, e.g. "IO      SYS".
 * Errors: 1=args, 2=BPB, 3=geometry/range, 4=not found,
 * 5=cluster chain, 6=sector I/O, 7=module allocation/write. */
uint8_t p129_fat16_load_root_file(const char *name83,
                                 p129_bank_module_t *module,
                                 uint32_t *size_out) {
    uint8_t spc, fats, i, found=0u;
    uint16_t reserved, root_entries, fat_size, root_sectors;
    uint16_t start_cluster=0u, cluster;
    uint32_t file_size=0UL, total_sectors, total32, fat_start, root_start;
    uint16_t bps, total16;
    uint32_t data_start, volume_end, cluster_count, cluster_bytes;
    uint32_t root_index, root_lba, file_offset=0UL, clusters_needed, step;
    volatile uint8_t *sector=p129_hdd_sector;
    if(!name83 || !module) return 1u;
    p129_bank_module_init(module);
    if(p129_fat16_read(P129_FAT16_PARTITION_LBA)) return 6u;
    bps=p129_fat16_u16(sector+11);
    spc=sector[13]; reserved=p129_fat16_u16(sector+14);
    fats=sector[16]; root_entries=p129_fat16_u16(sector+17);
    total16=p129_fat16_u16(sector+19);
    total32=p129_fat16_u32(sector+32);
    total_sectors=total16 ? total16 : total32;
    fat_size=p129_fat16_u16(sector+22);
    if(bps!=512u || !spc || spc>128u || (spc&(spc-1u)) || !reserved ||
       !fats || !root_entries || !fat_size || !total_sectors) {
        p129_fat16_diag(bps,spc,reserved,fats,root_entries,total16,total32,fat_size,0UL,0UL);
        return 2u;
    }
    root_sectors=(uint16_t)(((uint32_t)root_entries+15UL)>>4);
    fat_start=P129_FAT16_PARTITION_LBA+reserved;
    root_start=fat_start+(uint32_t)fats*fat_size;
    data_start=root_start+root_sectors;
    volume_end=P129_FAT16_PARTITION_LBA+total_sectors;
    if(data_start>=volume_end || volume_end>0x10000000UL) return 3u;
    if(volume_end>((uint32_t)p129_hdd_capacity[0] |
       ((uint32_t)p129_hdd_capacity[1]<<8) |
       ((uint32_t)p129_hdd_capacity[2]<<16) |
       ((uint32_t)p129_hdd_capacity[3]<<24))) return 3u;
    cluster_count=(volume_end-data_start)/spc;
    p129_fat16_diag(bps,spc,reserved,fats,root_entries,total16,total32,fat_size,data_start,cluster_count);
    if(cluster_count<4085UL || cluster_count>=65525UL) return 2u;
    if((cluster_count+2UL)*2UL>(uint32_t)fat_size*512UL) return 3u;
    cluster_bytes=(uint32_t)spc*512UL;

    /* Fixed root directory: sixteen 32-byte records per sector. */
    for(root_index=0UL;root_index<root_entries;root_index+=16UL) {
        root_lba=root_start+(root_index>>4);
        if(p129_fat16_read(root_lba)) return 6u;
        for(i=0u;i<16u && root_index+i<root_entries;++i) {
            uint16_t off=(uint16_t)i*32u;
            uint8_t attr=sector[off+11u],j,match=1u;
            if(sector[off]==0u) return 4u;
            if(sector[off]==0xE5u || attr==0x0Fu || (attr&0x18u)) continue;
            for(j=0u;j<11u;++j) {
                if(sector[off+j]!=(uint8_t)name83[j]) { match=0u; break; }
            }
            if(match) {
                start_cluster=p129_fat16_u16(sector+off+26u);
                file_size=p129_fat16_u32(sector+off+28u);
                found=1u; break;
            }
        }
        if(found) break;
    }
    if(!found) return 4u;
    if(!file_size || file_size>P129_FAT16_MAX_FILE ||
       start_cluster<2u || (uint32_t)start_cluster>=cluster_count+2UL) return 5u;
    if(p129_bank_module_alloc(module,file_size)) return 7u;
    if(size_out) *size_out=file_size;
    clusters_needed=(file_size+cluster_bytes-1UL)/cluster_bytes;
    cluster=start_cluster;

    for(step=0UL;step<clusters_needed;++step) {
        uint32_t first_sector,s;
        if(cluster<2u || (uint32_t)cluster>=cluster_count+2UL) goto bad_chain;
        first_sector=data_start+((uint32_t)cluster-2UL)*spc;
        if(first_sector+spc>volume_end) goto bad_chain;
        for(s=0UL;s<spc && file_offset<file_size;++s) {
            uint16_t amount=(uint16_t)(file_size-file_offset);
            if(amount>512u) amount=512u;
            if(p129_fat16_read(first_sector+s)) goto io_error;
            if(p129_bank_module_write(module,file_offset,(const uint8_t *)sector,amount))
                goto module_error;
            file_offset+=amount;
        }
        if(step+1UL<clusters_needed) {
            uint32_t fat_byte=(uint32_t)cluster*2UL;
            uint32_t fat_lba=fat_start+(fat_byte>>9);
            uint16_t fat_off=(uint16_t)(fat_byte&511UL),next;
            if((fat_byte>>9)>=fat_size) goto bad_chain;
            if(p129_fat16_read(fat_lba)) goto io_error;
            next=p129_fat16_u16(sector+fat_off);
            if(next>=P129_FAT16_EOC || next<2u || next==0xFFF7u) goto bad_chain;
            cluster=next;
        }
    }
    if(file_offset!=file_size) goto bad_chain;
    return 0u;
bad_chain:
    (void)p129_bank_module_release(module); return 5u;
io_error:
    (void)p129_bank_module_release(module); return 6u;
module_error:
    (void)p129_bank_module_release(module); return 7u;
}
