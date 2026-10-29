#include "tgg_analysis.h"
#include "tgg_display.h"
#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"
#include <stdint.h>
#include <stdio.h>

// 这个地址必须与 Vivado Address Editor 给 tgg_system_top 分配的基地址一致。
// 不能盲目使用下面的示例值；如果 Vivado 分配了别的地址，就改这里。
#ifndef TGG_BASEADDR
#if defined(XPAR_TGG_CAPTURE_0_S_AXI_BASEADDR)
#define TGG_BASEADDR XPAR_TGG_CAPTURE_0_S_AXI_BASEADDR
#elif defined(XPAR_TGG_CAPTURE_0_BASEADDR)
#define TGG_BASEADDR XPAR_TGG_CAPTURE_0_BASEADDR
#else
#define TGG_BASEADDR 0x43C00000u
#endif
#endif
#define TGG_STATUS   0x8000u
#define TGG_ACK      0x8004u
#define TGG_CONTROL  0x8008u
#define TGG_BANK_BYTES (TGG_N*4u)
#define TGG_VMAX     1.0       // 公式中的实验 Vmax，按实验实际最大电压修改
#define TGG_FMIN     1.0       // 允许搜索的最低频率（Hz）
#define TGG_FMAX     4000.0    // 允许搜索的最高频率（Hz），不能超过 5000 Hz
#ifndef TGG_STREAM_CSV
#define TGG_STREAM_CSV 0       // set to 1 for a clean CSV frame on UART
#endif

static uint16_t frame[TGG_N];

static unsigned wait_bank(void)
{
    unsigned s;
    // 状态寄存器 bit0/bit1 分别表示 bank0/bank1 是否已经填满。
    // 这里先轮询，初学调试简单；后续可以改成 irq_frame 中断。
    do { s = Xil_In32(TGG_BASEADDR+TGG_STATUS); } while (!(s & 3u));
    return (s & 1u) ? 0u : 1u;
}

static void read_frame(unsigned bank)
{
    unsigned i;
    const uint32_t base=TGG_BASEADDR+bank*TGG_BANK_BYTES;
    // 每个采样点占一个 32 位 AXI 读字，但只有低 12 位是 ADC code。
    for(i=0;i<TGG_N;++i) frame[i]=(uint16_t)(Xil_In32(base+4u*i)&0x0FFFu);
}

static void print_csv(unsigned bank)
{
    unsigned i;
    // A clean two-column CSV is emitted so it can be fed back to
    // tgg_final2.py: select column 2 and enter Rate=10000 when prompted.
    printf("index,voltage_V\n");
    for(i=0;i<TGG_N;++i) {
        const unsigned uv=(unsigned)frame[i]*1000000u/4095u;
        printf("%u,%u.%06u\n",i,uv/1000000u,uv%1000000u);
    }
}

int main(void)
{
    unsigned bank, frame_id=0, gap_events=0, status, lcd_ok;
    tgg_result_t result;
    xil_printf("TGG real-time XADC analyzer, Fs=10 kHz\r\n");
    lcd_ok=tgg_display_init();
    if(!lcd_ok) xil_printf("LCD unavailable: check screen ID and display AXI base.\r\n");
    for (;;) {
        bank=wait_bank();
        read_frame(bank);
        status=Xil_In32(TGG_BASEADDR+TGG_STATUS);
        if(status&8u) {
            ++gap_events;
            Xil_Out32(TGG_BASEADDR+TGG_CONTROL,1u);
        }
        // 必须等 4096 个采样点全部复制到 ARM 内存后再释放 bank；否则 PL
        // 可能一边写、ARM 一边读，导致一帧数据前后不属于同一次采集。
        Xil_Out32(TGG_BASEADDR+TGG_ACK,1u<<bank);
        tgg_process_frame(frame,TGG_VMAX,TGG_FMIN,TGG_FMAX,&result);
        tgg_print_result(&result);
        ++frame_id;
        if(lcd_ok && !tgg_display_update(frame,&result,frame_id,bank,
                                       (status>>3)&1u,gap_events,TGG_VMAX))
            xil_printf("LCD update timed out; acquisition continues.\r\n");
        // Optional CSV stream for a PC terminal/logger.  Comment out when
        // only the numerical result is needed.
#if TGG_STREAM_CSV
        print_csv(bank);
#endif
    }
    return 0;
}
