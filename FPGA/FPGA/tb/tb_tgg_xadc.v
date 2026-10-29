`timescale 1ns/1ps

// 【用途与运行方法】tgg_xadc.v 的单模块测试；仿真顶层选 tb_tgg_xadc。
// 100 MHz DCLK；普通 CONVST 间隔 100 us，即生产使用的 10 kHz 触发率。
// 正常流程约 1.2 ms：五次正常转换、一次读事务中途复位、恢复后再五次转换；
// 2 ms 为总超时。码值 0/512/2048/3584/4095 对应 0 至接近满量程的已知电压。
// VP/VN 数字端口本身不能承载 real 电压，所以 TB 写入本机 Vivado 2025.2
// UNISIM 的四个电压缓存；实际 CONVST、BUSY、EOC、DEN、DRDY、DO 均照常运行。
// NUL 是 Windows 的空设备，只用于让官方模型默认文件读取立即到达 EOF；
// 不需要生成或另存 design.txt。四个内部变量名依赖已验证的 2025.2 库实现，
// 升级 Vivado 后应核查名称和缓存更新行为；它们不是可综合的硬件接口。
// 这是行为模型与包装 RTL 的验证，不等于板上 ADC 精度、噪声和模拟带宽验证。
// Self-contained Verilog-2005 Vivado 2025.2/XSim XADC testbench (Windows).
// Simulation Top: tb_tgg_xadc. Add rtl/tgg_xadc.v as a design source.
// No design.txt, include file, or generated input file is required.
// NUL is the Windows empty device. Stimulus is written directly to the
// real-voltage caches of the installed AMD UNISIM XADC model.
// No EOC, DEN, DRDY, DO, sample_valid or sample_code signal is forced.
// CONVST, conversion, DRP handshake and result decoding all use real RTL.
// These hierarchical cache names were verified against Vivado 2025.2;
// recheck the installed XADC model before using another Vivado version.
// A primitive simulation is not evidence of hardware ADC accuracy.

module tb_tgg_xadc;
    // TB 驱动的数字输入：clk=100 MHz；resetn 低有效；convst 为一拍转换启动脉冲。
    // sample_valid/sample_code/busy 是 DUT 输出，仿真中不能由 TB 替代或强制。
    reg clk = 0;
    reg resetn = 0;
    reg convst = 0;
    wire sample_valid;
    wire [11:0] sample_code;
    wire busy;
    // checks/failures 汇总断言；triggers 统计 TB 启动数；eocs 统计非复位时段的 EOC。
    // issued_reads 在上升沿后的 #1 观察 DEN，reads 则在上升沿观察 DEN；
    // 两者都只在 resetn=1 时计数，因此复位跨在这两个观察点之间会产生差值。
    // drdys/samples 也只统计非复位时段；这些计数不能证明复位期间原语未接受或返回 DRP。
    integer checks = 0;
    integer failures = 0;
    integer triggers = 0;
    integer eocs = 0;
    integer reads = 0;
    integer issued_reads = 0;
    integer drdys = 0;
    integer samples = 0;
    // i 遍历两轮已知输入；samples_before_reset 保存复位前样本数以检查无旧数据泄漏。
    // expected_code 来自 TB 主动设置的输入，而不是 DUT 的实际输出。
    integer i;
    integer samples_before_reset;
    reg [11:0] expected_code = 0;
    // previous_den/previous_valid 检查相邻两拍是否重复为高；observed_drdy 保存
    // 当前上升沿进入包装器的 DRDY，供 #1 后与刚更新的 sample_valid 对齐。
    // check_interval 控制是否检查连续普通触发间隔，复位恢复时重新开始计时。
    // launch_time/prior_launch_time 使用 realtime 保存当前与上次触发的 ns 时间。
    reg previous_den = 0;
    reg previous_valid = 0;
    reg observed_drdy = 0;
    reg check_interval = 0;
    realtime launch_time;
    realtime prior_launch_time;

    always #5 clk = ~clk;
    // VP/VN 数字引脚置 0；真实模拟电压由 set_voltage 写入官方模型缓存。
    tgg_xadc dut (
        .clk(clk), .resetn(resetn), .convst(convst),
        .vp_in(1'b0), .vn_in(1'b0),
        .sample_valid(sample_valid), .sample_code(sample_code), .busy(busy)
    );
    // 仅覆盖仿真文件参数；生产 RTL、XADC 配置寄存器和数字响应路径均不改动。
    defparam dut.i_xadc.SIM_MONITOR_FILE = "NUL";

    // check：每次判断都记数；非明确的 1（包括 X/Z）判失败，打印 TB_FAIL。
    // 此测试台收集失败数后继续剩余流程，最终统一报告，不能只看最后一次 SAMPLE。
    task automatic check(input reg condition, input [8*128-1:0] description);
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                failures = failures + 1;
                $display("TB_FAIL: time=%0t %s", $time, description);
            end
        end
    endtask

    // code_for：以 index%5 生成包含零点、中间值和接近满量程的固定码序列。
    // 两轮使用相同序列，便于比较复位前后能否得到相同正确转换结果。
    function automatic [11:0] code_for(input integer index);
        begin
            case (index % 5)
                0: code_for = 12'd0;
                1: code_for = 12'd512;
                2: code_for = 12'd2048;
                3: code_for = 12'd3584;
                4: code_for = 12'd4095;
            endcase
        end
    endfunction

    // The official model normally fills these IEEE-754 real caches from its
    // monitor file. Deposit real VP/VN here instead, before asserting CONVST.
    // set_voltage：通道索引 3 对应 VP/VN；$realtobits 把 real 的 IEEE-754 位形
    // 写入模型的 64 位缓存，而非把电压数值强转整数。mn_in_diff 保存 VP-VN，
    // mn_in_uni 保存 VP，chan_val_tmp/chan_valn_tmp 分别保存正端/负端电压。
    // 同时更新四处，使单极性/差分及采样缓存一致；不 force 任一转换输出。
    task automatic set_voltage(input real vp, input real vn);
        begin
            dut.i_xadc.mn_in_diff[3] = $realtobits(vp - vn);
            dut.i_xadc.mn_in_uni[3] = $realtobits(vp);
            dut.i_xadc.chan_val_tmp[3] = $realtobits(vp);
            dut.i_xadc.chan_valn_tmp[3] = $realtobits(vn);
        end
    endtask

    // 监视器的前半段在上升沿采集旧寄存器值，统计真正 EOC、DEN、DRDY；
    // 后半段 #1 等 DUT 非阻塞赋值完成，再检查刚更新的 valid/code。
    always @(posedge clk) begin
        observed_drdy = dut.drdy;
        if (resetn) begin
            if (dut.eoc) eocs = eocs + 1;
            if (dut.den) begin
                reads = reads + 1;
                check(dut.daddr === 7'h03, "DEN must read VP/VN register 03");
            end
            if (dut.drdy) drdys = drdys + 1;
        end
        #1;
        // 复位时包装器必须清 DEN、读等待、有效标志与码值；历史脉冲状态也清零。
        if (!resetn) begin
            check(dut.den === 0 && dut.read_pending === 0 &&
                  sample_valid === 0 && sample_code === 0,
                  "reset clears DEN, read_pending, valid and code");
            previous_den = 0;
            previous_valid = 0;
        end else begin
            // DEN 上升后的完整高电平周期只允许一拍；读地址应始终为 7'h03。
            // sample_valid 同样只允许一拍，且必须来自本拍输入的真实 DRDY。
            if (dut.den) begin
                issued_reads = issued_reads + 1;
                check(!previous_den, "DEN must be a single DCLK pulse");
            end
            if (sample_valid) begin
                // 独立输入期望码同时检查真实模型的量化结果及包装器 DO[15:4] 解码。
                check(!previous_valid, "sample_valid must be a single DCLK pulse");
                check(observed_drdy, "sample_valid follows true UNISIM DRDY");
                check(sample_code === expected_code, "sample_code matches injected voltage");
                samples = samples + 1;
                $display("SAMPLE index=%0d time_ns=%0.1f code=%0d expected=%0d",
                         samples, $realtime, sample_code, expected_code);
            end
            previous_den = dut.den;
            previous_valid = sample_valid;
        end
    end

    // Exactly 100 us per completed task, so each normal phase is 10 kHz.
    // run_conversion(code)：先以 code/4096.0 设置电压，再发 10 ns CONVST。
    // initial_samples 是调用前样本计数；timeout_cycles 每 10 ns 累加，
    // 最多等 5000 次即 50 us，必须恰好增加一个样本，不能丢样也不能重复。
    // 剩余时间延迟补齐为总长 100 us，使下一次触发不受本次转换延迟影响。
    // check_interval 与两个时间变量共同验证普通阶段触发间隔恒定。
    task automatic run_conversion(input reg [11:0] code);
        integer initial_samples;
        integer timeout_cycles;
        real voltage;
        begin
            initial_samples = samples;
            expected_code = code;
            voltage = code / 4096.0;
            set_voltage(voltage, 0.0);
            launch_time = $realtime;
            if (check_interval)
                check(launch_time - prior_launch_time == 100000.0,
                      "normal trigger spacing must be exactly 100 us");
            prior_launch_time = launch_time;
            check_interval = 1;
            triggers = triggers + 1;
            convst = 1;
            #10 convst = 0;
            timeout_cycles = 0;
            while (samples == initial_samples && timeout_cycles < 5000) begin
                #10;
                timeout_cycles = timeout_cycles + 1;
            end
            check(samples == initial_samples + 1, "one conversion produces one sample before timeout");
            #(100000.0 - ($realtime - launch_time));
            check(samples == initial_samples + 1, "no duplicate sample in a trigger period");
        end
    endtask

    initial begin
        // 阶段一：先保持约 0.5 us 复位，再给原语约 99.5 us 初始化/稳定时间。
        // 连续五次已知输入覆盖零点、低/中/高电平与接近满量程。
        repeat (50) @(negedge clk);
        #1 resetn = 1;
        set_voltage(0.0, 0.0);
        #99500;
        for (i = 0; i < 5; i = i + 1) run_conversion(code_for(i));

        // 阶段二：第六次输入选 1234 以区分正常序列；等 DEN 已产生，再在
        // 下一下降沿后 1 ns 拉低复位，在随后的上升沿清包装器状态并抑制样本输出。
        // 此次 DEN 计入 issued_reads；下一个上升沿 resetn 已为 0，不再计入 reads。
        // 原语仍可能采纳旧 DEN 并在复位期间返回 DRDY；其 DRP 管线不由此 RESET 清除，
        // 本测试验证包装器不会输出陈旧样本，不把计数差值解释为原语内部事务被取消。
        samples_before_reset = samples;
        expected_code = 12'd1234;
        set_voltage(1234.0 / 4096.0, 0.0);
        triggers = triggers + 1;
        convst = 1;
        #10 convst = 0;
        wait (dut.den === 1'b1);
        @(negedge clk);
        #1 resetn = 0;
        repeat (50) @(negedge clk);
        #1;
        // 复位保持期间不能多出包装器样本；恢复后重置触发间隔参考并等待 100 us，
        // 再执行同样五种电压，确认复位后能够正常读取新转换结果。
        // 以下原有日志中的“取消”应按这个观测范围理解，不表示已经检查原语内部 DRP 撤销。
        check(samples == samples_before_reset, "reset aborts pending DRP without stale sample");
        resetn = 1;
        check_interval = 0;
        set_voltage(0.0, 0.0);
        #100000;
        for (i = 5; i < 10; i = i + 1) run_conversion(code_for(i));

        // 阶段三：核对可见事件计数。11 次触发/EOC/观察到的 DEN 中有一次跨入复位，
        // 所以非复位窗口内只统计到 10 次 DEN、DRDY 与有效样本；复位期间的原语活动不计入。
        check(triggers == 11, "10 complete triggers and one reset-aborted trigger");
        check(eocs == 11 && issued_reads == 11 && reads == 10,
              "11 issued reads; reset cancels one before the DRP acceptance edge");
        check(drdys == 10 && samples == 10, "exactly 10 complete DRDY responses and samples");
        $display("SUMMARY checks=%0d failures=%0d CONVST=%0d EOC=%0d DEN=%0d ACCEPTED_DEN=%0d DRDY=%0d SAMPLE=%0d",
                 checks, failures, triggers, eocs, issued_reads, reads, drdys, samples);
        // 只有所有累计检查均成功才打印 TB_PASS；任何失配会留下 TB_FAIL 标志。
        if (failures == 0)
            $display("TB_PASS: tgg_xadc real UNISIM conversion and DRP without design.txt.");
        else
            $display("TB_FAIL: %0d checks failed", failures);
        $finish;
    end

    initial begin
        // 全局 2 ms 看门狗也覆盖 wait(DEN) 挂起；超时必须明确失败，不能静默结束。
        #2000000;
        $display("TB_FAIL: global 2 ms timeout");
        $finish;
    end
endmodule
