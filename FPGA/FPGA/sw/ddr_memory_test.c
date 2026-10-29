/* Cortex-A9 standalone DDR diagnostic. Link this program into LOW OCM.
 * DESTRUCTIVE within [TGG_DDR_TEST_BASE, BASE+BYTES). CPU1 must remain stopped;
 * no OS, DMA or other program may use the reserved scratch area concurrently.
 * This tests the reserved 16 MiB, not the entire installed 1 GiB DDR.
 */
#include <stdint.h>
#include <stddef.h>
#include "xil_cache.h"
#include "xil_cache_l.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters_ps.h"
#include "xl2cc.h"
#include "xpseudo_asm.h"

#ifndef TGG_DDR_TEST_BASE
#define TGG_DDR_TEST_BASE  0x10000000u
#endif
#ifndef TGG_DDR_TEST_BYTES
#define TGG_DDR_TEST_BYTES 0x01000000u
#endif
#define TEST_RESERVED_BASE 0x10000000u
#define TEST_RESERVED_END  0x11000000u

/* Debugger-readable result: status 0=not started, 1=running, 2=pass,
 * 3=data failure, 4=invalid range. On failure retain the first bad access. */
volatile struct {
    uint32_t magic, status, stage, address, expected, actual, words;
} tgg_ddr_test_result;

static void barrier(void) { dsb(); }
static uint32_t read_word(uintptr_t a) { return Xil_In32(a); }
static void write_word(uintptr_t a, uint32_t v) { Xil_Out32(a, v); }

static int mismatch(unsigned stage, uintptr_t address, uint32_t expected,
                    uint32_t actual)
{
    if (actual == expected) return 0;
    tgg_ddr_test_result.stage=stage;
    tgg_ddr_test_result.address=(uint32_t)address;
    tgg_ddr_test_result.expected=expected;
    tgg_ddr_test_result.actual=actual;
    tgg_ddr_test_result.status=3u;
    xil_printf("DDR FAIL stage=%u address=0x%08x expected=0x%08x actual=0x%08x\r\n",
               stage,(unsigned)address,(unsigned)expected,(unsigned)actual);
    return 1;
}

static int data_bus_test(uintptr_t base)
{
    unsigned bit;
    for (bit=0; bit<32u; ++bit) {
        uint32_t value=1u<<bit;
        write_word(base,value); barrier();
        if (mismatch(1u,base,value,read_word(base))) return 1;
        value=~value;
        write_word(base,value); barrier();
        if (mismatch(1u,base,value,read_word(base))) return 1;
    }
    return 0;
}

/* Power-of-two word offsets exercise address bits within this region. */
static int address_bus_test(uintptr_t base, size_t words)
{
    size_t offset,other;
    const uint32_t pattern=0xAAAAAAAAu,anti=0x55555555u;
    write_word(base,pattern);
    for (offset=1u; offset<words; offset<<=1u)
        write_word(base+4u*offset,pattern);
    write_word(base+4u*(words-1u),pattern);
    barrier();
    write_word(base,anti); barrier();
    for (offset=1u; offset<words; offset<<=1u)
        if (mismatch(2u,base+4u*offset,pattern,read_word(base+4u*offset))) return 1;
    if (mismatch(2u,base+4u*(words-1u),pattern,read_word(base+4u*(words-1u)))) return 1;
    write_word(base,pattern);
    for (offset=1u; offset<words; offset<<=1u) {
        write_word(base+4u*offset,anti); barrier();
        if (mismatch(2u,base,pattern,read_word(base))) return 1;
        for (other=1u; other<words; other<<=1u) {
            if (other!=offset && mismatch(2u,base+4u*other,pattern,
                                          read_word(base+4u*other))) return 1;
        }
        write_word(base+4u*offset,pattern);
    }
    barrier();
    return 0;
}

static int full_pattern_test(uintptr_t base, size_t words, uint32_t pattern)
{
    size_t i;
    for (i=0; i<words; ++i) write_word(base+4u*i,pattern);
    barrier();
    for (i=0; i<words; ++i)
        if (mismatch(3u,base+4u*i,pattern,read_word(base+4u*i))) return 1;
    return 0;
}

static int address_data_test(uintptr_t base, size_t words)
{
    size_t i;
    for (i=0; i<words; ++i) write_word(base+4u*i,(uint32_t)(base+4u*i));
    barrier();
    for (i=words; i!=0u; --i) {
        uintptr_t a=base+4u*(i-1u);
        if (mismatch(4u,a,(uint32_t)a,read_word(a))) return 1;
        write_word(a,~(uint32_t)a);
    }
    barrier();
    for (i=0; i<words; ++i) {
        uintptr_t a=base+4u*i;
        if (mismatch(4u,a,~(uint32_t)a,read_word(a))) return 1;
    }
    return 0;
}

int main(void)
{
    const uintptr_t base=(uintptr_t)TGG_DDR_TEST_BASE;
    const size_t bytes=(size_t)TGG_DDR_TEST_BYTES;
    const uint32_t patterns[]={0u,0xFFFFFFFFu,0x55555555u,0xAAAAAAAAu,
                               0x00FF00FFu,0xFF00FF00u};
    uint32_t l1_was_enabled,l2_was_enabled;
    unsigned i;
    int failed=0;
    tgg_ddr_test_result.magic=0x54474744u;
    tgg_ddr_test_result.status=1u;
    /* Overrides may shrink the test, but cannot reach application RAM.
     * Subtraction avoids overflowing base+bytes in the validation itself. */
    if ((base&3u)!=0u || (bytes&3u)!=0u || bytes<16u ||
        base<TEST_RESERVED_BASE || base>=TEST_RESERVED_END ||
        bytes>TEST_RESERVED_END-base) {
        tgg_ddr_test_result.status=4u;
        xil_printf("DDR FAIL: test range must stay inside 0x10000000..0x10FFFFFF\r\n");
        return 1;
    }
    tgg_ddr_test_result.words=(uint32_t)(bytes/4u);
    xil_printf("DDR destructive test: 0x%08x..0x%08x, %u bytes; code in OCM\r\n",
               (unsigned)base,(unsigned)(base+bytes-1u),(unsigned)bytes);
    /* Save L1D and L2 separately; I-cache can use L2 while L1D is off. */
    l1_was_enabled=mfcp(XREG_CP15_SYS_CONTROL)&0x4u;
    l2_was_enabled=Xil_In32(XPS_L2CC_BASEADDR+XPS_L2CC_CNTRL_OFFSET)&1u;
    Xil_DCacheFlush();
    Xil_DCacheDisable();
    barrier();
    if (data_bus_test(base) || address_bus_test(base,bytes/4u)) failed=1;
    for (i=0; !failed && i<sizeof(patterns)/sizeof(patterns[0]); ++i) {
        xil_printf("DDR pattern 0x%08x\r\n",(unsigned)patterns[i]);
        failed=full_pattern_test(base,bytes/4u,patterns[i]);
    }
    if (!failed) failed=address_data_test(base,bytes/4u);
    barrier();
    Xil_DCacheInvalidate();
    if (l2_was_enabled) Xil_L2CacheEnable();
    if (l1_was_enabled) Xil_L1DCacheEnable();
    barrier();
    if (!failed) {
        tgg_ddr_test_result.status=2u;
        xil_printf("DDR PASS: reserved %u-byte region; full DDR capacity not tested\r\n",
                   (unsigned)bytes);
    }
    /* The reserved scratch data is not restored. Both original cache-enable
     * states are restored before returning, on success and on data failure. */
    return failed ? 1 : 0;
}
