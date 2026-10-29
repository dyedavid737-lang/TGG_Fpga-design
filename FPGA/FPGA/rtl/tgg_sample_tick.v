`timescale 1ns/1ps

// 精确采样触发器。
//
// clk 是 FPGA 逻辑时钟。本工程默认 clk=100 MHz，也就是每秒 1 亿个时钟。
// PERIOD=CLK_HZ/SAMPLE_HZ=100000000/10000=10000，所以每数 10000 个 clk
// 产生一个宽度为 1 个 clk 的 tick。这个 tick 连接到 XADC 的 CONVST，
// 因而每秒启动 10000 次 ADC 转换。
//
// resetn 的 n 表示“低有效”：resetn=0 时复位，resetn=1 时正常工作。
// enable=0 时计数器清零，重新 enable 后从完整的采样周期重新开始。
// 模块职责：仅按逻辑时钟计数产生转换触发，不包含 ADC 转换或数据缓冲。
// 所有时序逻辑使用 clk 上升沿；这里的复位也是同步低有效复位。
module tgg_sample_tick #(
    // CLK_HZ：clk 的实际频率，单位 Hz。该参数只计算分频值，不产生或约束物理时钟。
    parameter [31:0] CLK_HZ    = 100_000_000,
    // SAMPLE_HZ：期望触发频率，单位 Hz。必须大于 0、整除 CLK_HZ，且 CLK_HZ/SAMPLE_HZ >= 2。
    // 参数检查只有 $display 提示，并不会自动停止仿真；非法参数不能依赖本模块自恢复。
    parameter [31:0] SAMPLE_HZ = 10_000
) (
    // clk：计数和输出寄存器的唯一时钟输入，默认 100 MHz。
    input  wire clk,
    // resetn：低有效同步复位；拉低后要经过 clk 上升沿才清零 count 和 tick。
    input  wire resetn,
    // enable：同步运行使能。为 0 时清零计数、停止触发；应由同一时钟域逻辑产生。
    input  wire enable,
    // tick：寄存器输出，高电平持续恰好一个 clk 周期，供 XADC CONVST 使用。
    output reg tick
);
    // PERIOD：每次触发间隔包含的完整 clk 周期数，单位为时钟拍；整数除法不会保留小数。
    localparam [31:0] PERIOD = CLK_HZ / SAMPLE_HZ;
    // CW：存放 0 到 PERIOD-1 所需的位宽；对很小的周期至少保留 1 位，避免零宽计数器。
    localparam [31:0] CW     = (PERIOD <= 2) ? 1 : $clog2(PERIOD);
    // count：本周期已累计的时钟拍数；只在 enable=1 时推进，终值后回到 0。
    reg [CW-1:0] count;

    // 仿真开始时检查静态参数。先满足 SAMPLE_HZ>0，才能安全进行除法与取模；
    // 该 initial 不承担运行时保护，综合后的频率仍由参数和外部真实时钟共同决定。
    initial begin
        if (CLK_HZ % SAMPLE_HZ != 0)
            $display("ERROR:", "CLK_HZ must be an integer multiple of SAMPLE_HZ");
        if (PERIOD < 2)
            $display("ERROR:", "The sample period must be at least two clock cycles");
    end

    // 每个上升沿读取旧 count/enable，使用非阻塞赋值 <= 统一更新寄存器。
    // 因此判断 count==PERIOD-1 使用的是本拍更新之前的计数值。
    always @(posedge clk) begin
        // 复位优先级最高：取消当前分频进度，tick 确定为低。
        if (!resetn) begin
            count <= {CW{1'b0}};
            tick  <= 1'b0;
        end else begin
            // 正常工作每拍先安排 tick 清零；若同拍达到终值，后面的 tick<=1 覆盖此安排，形成单拍脉冲。
            tick <= 1'b0;
            // 关闭使能时不保留半个周期，重新使能后必须计满 PERIOD 拍才产生下一次 tick。
            if (!enable) begin
                count <= {CW{1'b0}};
            // 到达分频终值：计数归零且发出触发；PERIOD>=2 保证两个 tick 之间至少有一拍低电平。
            end else if (count == PERIOD-1) begin
                count <= {CW{1'b0}};
                tick  <= 1'b1;
            end else begin
                // 未到终值时只增加计数；tick 维持本拍默认的 0。
                count <= count + 1'b1;
            end
        end
    end
endmodule
