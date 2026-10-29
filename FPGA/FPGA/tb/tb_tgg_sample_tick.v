`timescale 1ns/1ps
// 【用途与运行方法】本文件是 tgg_sample_tick.v 的独立分频器测试台；
// 在 Vivado 的 Simulation Sources 中将 tb_tgg_sample_tick 设为顶层后 Run All。
// 时间单位 1 ns、精度 1 ps；#5 翻转一次时钟，完整周期 10 ns，即 100 MHz。
// DUT 不覆盖参数，直接验证生产默认的 100 MHz / 10 kHz：10000 个时钟出一拍，
// 周期 100 us、脉宽 10 ns。与顶层集成 TB 的 100 kHz 加速参数不同。
// 全部激励在本文件生成，不需要 XADC、UNISIM 电压缓存或任何外部输入文件。
// 正常流程在约 612.4 us 完成六个脉冲；1 ms 是防止挂起的总超时上限。
// Self-contained 100 MHz / 10 kHz test. Set this TB as Simulation Top.
module tb_tgg_sample_tick;
    // clk 为逻辑时钟；resetn 为低有效同步复位；enable 控制分频器运行。
    // tick 为被测输出，预期只在完整计数周期末端保持一个时钟为高。
    reg clk=0, resetn=0, enable=0;
    wire tick;
    // cycles 统计监视器经过的总时钟数；pulses 记录实际看到的有效 tick 数；
    // reference_count 是 TB 自己计算的 0..9999 参考计数器，不读取 DUT 内部计数。
    // previous_tick 保留上一拍输出，用于检测连续两拍为高的脉宽错误。
    integer cycles=0, pulses=0, reference_count=0;
    reg previous_tick=0;
    always #5 clk=~clk;
    tgg_sample_tick dut(.clk(clk),.resetn(resetn),.enable(enable),.tick(tick));
    // fail：接收定长字符消息，打印统一 TB_FAIL 标志及时间并立即结束仿真。
    // 正常流程的 TB_PASS 与任何失败路径互斥，不能把单纯仿真结束当作通过。
    task fail;
        input [2047:0] message;
        begin $display("TB_FAIL: %0s at %0t",message,$time); $finish; end
    endtask
    // 独立逐拍监视器：先按当前 resetn/enable 更新参考计数，再等待 1 ns，
    // 让 DUT 的非阻塞赋值完成后检查 tick，避免在同一上升沿读到上一拍结果。
    always @(posedge clk) begin
        if(!resetn || !enable) reference_count=0;
        else if(reference_count==9999) reference_count=0;
        else reference_count=reference_count+1;
        #1;
        cycles=cycles+1;
        // 禁用和复位均要求 tick 为 0；启用时参考计数回到 0 的那一拍必须有 tick。
        // !== 使用四态比较，因此 tick 的 X/Z 也会触发失败，而非被当作普通 0。
        if(!resetn || !enable) begin
            if(tick!==1'b0) fail("tick must be zero during reset/disable");
        end else begin
            if(tick !== (reference_count==0)) fail("tick does not match independent divide-by-10000 reference");
            if(previous_tick && tick) fail("tick is wider than one 10 ns clock");
            if(tick) begin
                pulses=pulses+1;
                $display("PULSE %0d time_ns=%0.1f",pulses,$realtime);
            end
        end
        previous_tick=tick;
    end
    initial begin
        // 阶段一：先保持五个时钟复位，在下降沿释放复位并启用。
        // 等到三个完整脉冲，验证连续运行下的周期和单拍宽度。
        repeat(5) @(negedge clk); resetn=1; enable=1;
        wait(pulses==3);
        // 阶段二：禁用 1234 个时钟；这个长度刻意不是 10000 的整数倍。
        // 参考计数归零，重新启用后应从完整的 100 us 开始，而不是接着旧余数计数。
        @(negedge clk); enable=0;
        repeat(1234) @(negedge clk);
        enable=1;
        wait(pulses==5);
        // 阶段三：运行中再次复位五拍，检查复位清 tick/计数与恢复运行。
        // 第六个脉冲后再留三个下降沿，给监视器完成末尾检查的机会。
        @(negedge clk); resetn=0;
        repeat(5) @(negedge clk); resetn=1;
        wait(pulses==6);
        repeat(3) @(negedge clk);
        // 只有全部逐拍检查和六个目标脉冲均完成，才输出成功标志。
        $display("TB_PASS: sample_tick; 6 pulses, 10000 clocks per enabled period, one-clock width, reset/disable/restart");
        $finish;
    end
    // 独立看门狗：如果 wait 没有等到预期脉冲，1 ms 后明确报告失败并结束。
    initial begin #1000000; fail("timeout"); end
endmodule
