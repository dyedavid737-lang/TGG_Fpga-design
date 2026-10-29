`timescale 1ns/1ps
// 【用途与运行方法】tgg_system_top.v 的完整采集/寄存器集成测试台；仿真顶层
// 选 tb_tgg_system_top，设计源同时加入 tgg_sample_tick.v、tgg_xadc.v。
// 本文件自己产生电压和 AXI 事务，不依赖输入文件、include 或其他 TB。
// 时钟为 100 MHz；为缩短验证，DUT 参数 FS_HZ=100000、N=8，
// 每 10 us 一次转换、每帧八点；生产默认则为 10 kHz、每帧 4096 点。
// 正常流程约 344.270 us 完成三帧共 24 点和全部 AXI 检查；总超时为 500 us。
// 电压刺激进入本机 Vivado 2025.2 的真实 UNISIM XADC 内部缓存，
// 真实转换、DRP 握手、包装器解码、缓存写入、AXI 读回均参与验证。
// 这些内部缓存名称只对已核查的模型实现有效；升级 Vivado 后需重新核查。
// NUL 仅是 Windows 空设备，用来取消默认 design.txt 的输入文件依赖。
// 本行为仿真不代表实物 ADC 精度、系统磁场精度或布局布线后的时序结果。
// Self-contained Vivado/XSim integration test. No design.txt, $readmemh,
// $fopen stimulus, or external model is needed. Select this module as Top.
// Requires the production tgg_system_top, tgg_sample_tick and tgg_xadc RTL.
//
// Test acceleration: 100 MHz clock, FS_HZ=100 kHz and N=8. These values only
// shorten frame capture; they are not the production 10 kHz/4096 settings.
// The real Vivado 2025.2 UNISIM XADC performs conversion and DRP response.
// TB voltage is deposited into its internal VP/VN real-value cache, using
// library-specific names. EOC, DEN, DRDY, DO and wrapper outputs are real.
// This validates model/RTL behavior, not physical analog accuracy.
module tb_tgg_system_top;
    // N 规定本 TB 的每 bank 样本数；期望数组长度、读回循环和 DUT 使用同一值。
    // clk 每 5 ns 翻转、上升沿周期 10 ns；resetn 在下降沿后释放，避开采样竞争。
    localparam integer N = 8;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    // AXI 写地址通道：awaddr/awvalid 由 TB 驱动，awready 是 DUT 接受条件。
    // araddr 是读地址；与写地址独立，二者均为 16 位字节地址而非字索引。
    reg [15:0] awaddr = 0, araddr = 0;
    reg awvalid = 0;
    wire awready;
    // AXI 写数据通道：wdata 为 32 位数据，wstrb 每位选择一个有效字节；
    // wvalid/wready 握手与 AW 可以在不同周期发生，不能假设地址与数据同时到。
    // rdata 为只读的 32 位返回数据，与 wdata 不共用驱动。
    reg [31:0] wdata = 0;
    wire [31:0] rdata;
    reg [3:0] wstrb = 0;
    // wvalid、bready 由 TB 驱动；wready、bvalid 为 DUT 输出。
    // B 通道表示写响应，bready=0 用于制造写响应背压；bresp=00 代表 OKAY。
    // rresp=00 同样表示读响应 OKAY，不应把有数据返回等同于响应正确。
    reg wvalid = 0, bready = 0;
    wire wready, bvalid;
    wire [1:0] bresp, rresp;
    // AXI 读地址/数据通道：arvalid/arready 接受读请求；rvalid/rready 接受返回。
    // TB 故意保持 rready=0，要求 DUT 保持数据、响应码和 rvalid，并阻挡新读请求。
    reg arvalid = 0, rready = 0;
    wire arready, rvalid;
    // irq_frame 是任一完整 bank ready 的电平中断；convst_dbg 是实际转换触发。
    // conversions/eoc_count/den_count/drdy_count/samples 分别统计触发、转换完成、
    // DRP 读请求、DRP 返回和包装器样本，用一一对应关系检测丢样/重复握手。
    // accepted 仅统计 active 时真正被缓存接受的样本；checks 统计显式检查项。
    wire irq_frame, convst_dbg;
    integer conversions = 0, eoc_count = 0, drdy_count = 0;
    integer den_count = 0, samples = 0, accepted = 0, checks = 0;
    // 两层独立参考：expected_adc 按转换先后保存 TB 输入所对应的 12 位期望码；
    // expected 按缓存地址保存应写入的 16 位字，accepted 对 2*N 取模以覆盖复用区。
    // 它们都不以 DUT 的实际 sample_code 或 RAM 内容构造正确答案。
    reg [15:0] expected [0:2*N-1];
    reg [11:0] expected_adc [0:63];
    // stimulus_ordinal 决定下一个已知输入码，在样本被消费后才加一，
    // 因而一次转换期间输入保持稳定；previous_den 检查 DEN 不连续高两拍。
    // status_word 接收每笔 AXI 返回；check_description 为 $sformat 的定长字符缓冲。
    integer stimulus_ordinal = 0;
    reg previous_den = 0;
    reg [31:0] status_word;
    reg [2047:0] check_description;

    // 被测顶层包含真实分频器、XADC 包装器、双 bank RAM 和 AXI-Lite 从接口。
    // VP/VN 的数字端口置 0，真实模拟值通过下面 deposit_voltage 写入模型缓存。
    tgg_system_top #(.CLK_HZ(100_000_000), .FS_HZ(100_000), .N(N)) dut (
        .clk100(clk), .resetn(resetn), .vp_in(1'b0), .vn_in(1'b0),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .irq_frame(irq_frame), .convst_dbg(convst_dbg)
    );

    // Windows' built-in NUL device is empty. This suppresses the UNISIM
    // primitive's default design.txt lookup, without creating or loading an
    // input data file. The inline voltage cache deposits below supply all stimulus.
    // 只覆盖原语的仿真输入文件参数；不更改生产 RTL，也不替代任何 EOC/DRDY/DO。
    defparam dut.i_adc.i_xadc.SIM_MONITOR_FILE = "NUL";
    // code_for(ordinal)：已知输入序列从 128 起，每次递增 37；不同样本数值不同，
    // 可检测缓存字顺序颠倒、重复地址、旧帧残留，避免固定电平掩盖寻址错误。
    function automatic [11:0] code_for(input integer ordinal);
        begin
            code_for = 12'd128 + ordinal * 37;
        end
    endfunction

    // XADC digital VP/VN ports cannot represent real voltages. Deposit the
    // encoded voltage into the actual AMD 2025.2 analog input caches. This
    // does not force or replace conversion/handshake/data outputs. The low
    // nibble of DO is nonzero (quarter of a 12-bit LSB) to test DO[15:4].
    // deposit_voltage(volts)：通道 3 为 VP/VN；$realtobits 保存 IEEE-754 位形。
    // mn_in_diff 为差分电压，mn_in_uni 为单极性输入；chan_val_tmp 和
    // chan_valn_tmp 分别保存正、负端采样缓存，这里 VN 恒为 0 V。
    // 四处同步写入的是模拟刺激，不是 ADC 结果或握手；依赖 Vivado 2025.2 内部名称。
    task automatic deposit_voltage(input real volts);
        begin
            dut.i_adc.i_xadc.mn_in_diff[3] = $realtobits(volts);
            dut.i_adc.i_xadc.mn_in_uni[3] = $realtobits(volts);
            dut.i_adc.i_xadc.chan_val_tmp[3] = $realtobits(volts);
            dut.i_adc.i_xadc.chan_valn_tmp[3] = $realtobits(0.0);
        end
    endtask
    // 每个下降沿刷新稳定电压。加 0.25 个 12 位 LSB 后再除 4096，
    // 使期望 12 位整数码不变、16 位 DO 的低四位非零，强化 DO[15:4] 截取检查。
    // 输入序号只在完成样本后变化，距下一次 10 us 触发仍有充分稳定时间。
    always @(negedge clk) begin
        if (resetn) deposit_voltage((code_for(stimulus_ordinal) + 0.25) / 4096.0);
    end
    // 在真实 CONVST 上升沿登记本次输入期望码，形成按启动顺序排列的静态队列。
    // 64 个槽远大于正常 24 次转换；意外持续触发至越界时应立即失败而非读写越界。
    always @(posedge convst_dbg) begin
        if (resetn) begin
            if (conversions >= 64) begin $display("TB_FAIL: Stimulus reference array exhausted"); $finish; end
            expected_adc[conversions] = code_for(stimulus_ordinal);
            conversions = conversions + 1;
        end
    end

    // Independent ordered sample scoreboard, sampled where top capture_logic
    // consumes wrapper output. The expected value comes from the stimulus
    // ordinal, not from DUT RAM or sample_code.
    // 此监视器在 DUT 接受 sample_valid 的同一上升沿读取上一拍寄存输出，
    // 和 capture_logic 的消费时刻一致。先检查样本值，再把独立期望写入参考 RAM；
    // 暂停时不增加 accepted，从而区分“ADC 产生样本”与“缓存接收样本”。
    always @(posedge clk) begin
        if (resetn) begin
            if (dut.i_adc.eoc) eoc_count = eoc_count + 1;
            if (dut.i_adc.drdy) drdy_count = drdy_count + 1;
            // DEN 只能高一拍且 DADDR 固定为 VP/VN 状态寄存器 03。
            // 实际请求计数最后还要与 EOC、DRDY、样本数一致，检查整条通路无丢失。
            if (dut.i_adc.den) begin
                if (previous_den || dut.i_adc.daddr !== 7'h03)
                    begin $display("TB_FAIL: DEN must be one DCLK and DADDR must be 03"); $finish; end
                den_count = den_count + 1;
            end
            previous_den = dut.i_adc.den;
            if (dut.sample_valid) begin
                if (dut.sample_code !== expected_adc[samples])
                    begin $display("TB_FAIL: Sample %0d code=%h expected=%h", samples, dut.sample_code, expected_adc[samples]); $finish; end
                if (dut.active) begin
                    expected[accepted % (2*N)] = {4'd0, expected_adc[samples]};
                    accepted = accepted + 1;
                end
                samples = samples + 1;
                stimulus_ordinal = stimulus_ordinal + 1;
            end
        end
    end

    // Check wrapper registered result immediately after nonblocking updates.
    // 第二个监视器专门检查寄存器时序：incoming_drdy/incoming_code 保存
    // 上升沿输入值，#1 后对应包装器新输出；不把更新前与更新后的值直接混比。
    // 即使最终 RAM 数值偶然正确，valid 错拍或 DO 位段截取错误也会在此失败。
    always @(posedge clk) begin : wrapper_monitor
        reg incoming_drdy;
        reg [11:0] incoming_code;
        incoming_drdy = dut.i_adc.drdy;
        incoming_code = dut.i_adc.do_bus[15:4];
        #1;
        if (resetn) begin
            if (dut.sample_valid !== incoming_drdy)
                begin $display("TB_FAIL: sample_valid must track DRDY with exactly one registered update"); $finish; end
            if (incoming_drdy && dut.sample_code !== incoming_code)
                begin $display("TB_FAIL: sample_code does not equal DRP DO[15:4]"); $finish; end
        end
    end

    // check(condition, description)：只有明确的 1 才通过，X/Z 也判失败。
    // 失败立即输出 TB_FAIL 并停止；通过逐项计数和打印，最终汇总为 141 项。
    task automatic check(input condition, input [2047:0] description);
        begin
        checks = checks + 1;
        if (condition !== 1'b1) begin $display("TB_FAIL: CHECK FAIL %0d t=%0t: %s", checks, $time, description); $finish; end
        $display("CHECK PASS %0d t=%0t: %0s", checks, $time, description);
        end
    endtask

    // Positive skew sends AW first; negative skew sends W first.
    // BREADY is held low to exercise response and request backpressure.
    // axi_write(address,data,strobes,skew,stall_cycles)：以字节地址发起一笔写。
    // fork 分别管理 AW 和 W，正 skew 延后 W、负 skew 延后 AW，0 为同时发送。
    // 两路均在下降沿给稳定输入、上升沿等待 READY，接受后下降沿撤回 VALID。
    // 等 BVALID 后检查 OKAY，再保持 BREADY 低 stall_cycles 拍，验证响应保持、
    // AWREADY/WREADY 禁止新请求；最后只给一次接受边沿，要求 BVALID 清除。
    task automatic axi_write(input [15:0] address,
                             input [31:0] data,
                             input [3:0] strobes,
                             input integer skew,
                             input integer stall_cycles);
        begin
        fork
            begin
                repeat (skew < 0 ? -skew : 0) @(negedge clk);
                @(negedge clk); awaddr = address; awvalid = 1;
                @(posedge clk); while (!awready) @(posedge clk);
                @(negedge clk); awvalid = 0;
            end
            begin
                repeat (skew > 0 ? skew : 0) @(negedge clk);
                @(negedge clk); wdata = data; wstrb = strobes; wvalid = 1;
                @(posedge clk); while (!wready) @(posedge clk);
                @(negedge clk); wvalid = 0;
            end
        join
        @(posedge clk); while (!bvalid) @(posedge clk);
        check(bresp === 2'b00, "AXI write response is OKAY");
        repeat (stall_cycles) begin
            @(posedge clk);
            check(bvalid && bresp === 2'b00 && !awready && !wready,
                  "BVALID/response hold and AW/W are blocked during BREADY stall");
        end
        @(negedge clk); bready = 1;
        @(posedge clk);
        @(negedge clk); bready = 0;
        check(!bvalid, "Write response consumed exactly once");
        end
    endtask

    // axi_read(address,data,stall_cycles)：AR 握手后等待返回，保存 rdata 为 data。
    // 在 RREADY 为低的指定拍数内，RVALID/RDATA/RRESP 必须保持且 ARREADY 为低；
    // 最后拉高 RREADY 一拍消费返回，再核对响应确实清除，避免同一结果被重复消费。
    task automatic axi_read(input [15:0] address,
                            output [31:0] data,
                            input integer stall_cycles);
        begin
        @(negedge clk); araddr = address; arvalid = 1;
        @(posedge clk); while (!arready) @(posedge clk);
        @(negedge clk); arvalid = 0;
        @(posedge clk); while (!rvalid) @(posedge clk);
        data = rdata;
        check(rresp === 2'b00, "AXI read response is OKAY");
        repeat (stall_cycles) begin
            @(posedge clk);
            check(rvalid && rdata === data && rresp === 2'b00 && !arready,
                  "RVALID/data/response hold and AR is blocked during RREADY stall");
        end
        @(negedge clk); rready = 1;
        @(posedge clk);
        @(negedge clk); rready = 0;
        check(!rvalid, "Read response consumed exactly once");
        end
    endtask

    initial begin : test_sequence
        // k 为 RAM 逐字检查索引；paused_conversions 保存暂停起点的转换计数。
        integer k, paused_conversions;
        // 阶段一：参考 RAM 清零，保持 10000 拍即 100 us 复位，使模型初始化完成。
        // 释放后读取 0x8000：低四位按 {overflow,active,ready[1:0]} 编码，
        // 所以初始值为 0x4；同时测试两拍 RREADY 背压和初始 IRQ=0。
        for (k = 0; k < 2*N; k = k + 1) expected[k] = 0;
        repeat (10000) @(negedge clk);
        #1; resetn = 1;
        axi_read(16'h8000, status_word, 2);
        check(status_word === 32'h4 && !irq_frame,
              "Reset state: active=1, ready=00, overflow=0, IRQ=0");

        // 阶段二：首帧填 bank0 后 ready=01、IRQ=1，仍应继续向 bank1 采集。
        // 第二帧完成后 ready=11，要求暂停、overflow 置位且中断保持。
        wait (dut.bank_ready == 2'b01);
        @(negedge clk);
        check(irq_frame && dut.active && !dut.overflow,
              "First frame fills bank0, asserts IRQ and continues bank1");
        wait (dut.bank_ready == 2'b11);
        repeat (3) @(negedge clk);
        check(dut.paused && dut.overflow && irq_frame,
              "Two full banks pause capture, latch overflow and assert IRQ");
        // 再读状态并施加五拍读背压：双满时低四位应为 0xB，即溢出且 inactive。
        axi_read(16'h8000, status_word, 5);
        check(status_word === 32'hb, "STATUS encodes overflow=1 active=0 ready=11");
        // 阶段三：0x0000 起的每个 32 位 AXI 字节地址增加 4；
        // 前八个地址映射 bank0、后八个映射 bank1。逐字与独立参考 RAM 比较，
        // 同时要求返回高 16 位为 0；首字额外施加三拍读背压。
        for (k = 0; k < 2*N; k = k + 1) begin
            axi_read(4*k, status_word, k == 0 ? 3 : 0);
            $sformat(check_description, "RAM word %0d matches ordered changing sample", k);
            check(status_word === {16'd0, expected[k]}, check_description);
        end
        // 未映射地址 0x9000 应正常返回 0，不能泄漏其他 RAM/状态内容。
        axi_read(16'h9000, status_word, 0);
        check(status_word === 0, "Unmapped read returns zero");
        // 连等 20 个时钟后，转换计数和写索引都不能前进，验证暂停真正阻止新触发。
        paused_conversions = conversions;
        repeat (20) @(negedge clk);
        check(conversions == paused_conversions && dut.wr_index == 0,
              "Pause suppresses conversion triggers and memory progress");

        // Address/data alone do not make a write: both VALID handshakes matter.
        // 阶段四：把 ACK 地址和数据放上总线，但 AWVALID/WVALID 仍为 0；
        // 等五拍要求双 bank 状态不变，且不能凭总线电平凭空出现写响应。
        awaddr = 16'h8004; wdata = 32'h3; wstrb = 4'hf;
        repeat (5) @(negedge clk);
        check(dut.bank_ready == 2'b11 && !bvalid,
              "ACK address/data with AWVALID=WVALID=0 causes no transaction");
        // 阶段五：0x8004 为 ACK，bit0/bit1 分别释放 bank0/bank1。
        // 先用 WSTRB=0，再用仅高三字节有效的 0xE；两种写都不得释放低字节控制位。
        // 这两笔分别覆盖 AW 先到三拍和 W 先到四拍，以及 BREADY 背压。
        axi_write(16'h8004, 32'h3, 4'h0, 3, 3);
        check(dut.bank_ready == 2'b11 && dut.paused,
              "ACK WSTRB=0 cannot release either bank");
        axi_write(16'h8004, 32'h3, 4'he, -4, 2);
        check(dut.bank_ready == 2'b11 && dut.paused,
              "ACK with low byte unselected cannot release either bank");
        // 0x8008 为 CONTROL。无字节有效或低字节未选中时均不能清 overflow；
        // 即使低字节有效，写 bit0=0 也应保持历史溢出，只有有效写 1 才清除。
        axi_write(16'h8008, 32'h1, 4'h0, 0, 2);
        check(dut.overflow, "CONTROL WSTRB=0 cannot clear overflow");
        axi_write(16'h8008, 32'h1, 4'he, -3, 1);
        check(dut.overflow, "CONTROL with low byte unselected cannot clear overflow");
        axi_write(16'h8008, 32'h0, 4'h1, 0, 0);
        check(dut.overflow, "CONTROL bit0=0 leaves sticky overflow asserted");
        // 有效 CONTROL 写 1 只清 overflow；两个满帧及暂停不能因此被顺带释放。
        axi_write(16'h8008, 32'h1, 4'h1, 2, 3);
        check(!dut.overflow && dut.paused && dut.bank_ready == 2'b11,
              "Valid CONTROL clears only overflow while banks remain full");

        // 阶段六：有效 ACK bank0，AW 比 W 先四拍；应解除暂停并继续采集，
        // bank1 仍 ready，因此 IRQ 不能清。再以 W 比 AW 先四拍 ACK bank1，
        // 两 bank 都未 ready 时中断才解除。这些操作均在下一帧填满前完成。
        axi_write(16'h8004, 32'h1, 4'h1, 4, 3);
        repeat (2) @(negedge clk);
        check(dut.active && dut.bank_ready == 2'b10 && irq_frame,
              "AW-before-W ACK releases bank0, resumes and keeps bank1 IRQ");
        axi_write(16'h8004, 32'h2, 4'h1, -4, 3);
        check(dut.active && dut.bank_ready == 2'b00 && !irq_frame,
              "W-before-AW ACK releases bank1 and deasserts IRQ");
        // 阶段七：等释放后的 bank0 被第三帧重新填满，要求继续 active、IRQ 再起，
        // 且先前清除的 overflow 不应无故重现。回读 bank0，必须是第 17..24 个
        // 输入对应的新值；首字再加两拍背压，不能读到第一帧残留或破坏顺序。
        wait (dut.bank_ready == 2'b01);
        @(negedge clk);
        check(dut.active && irq_frame && !dut.overflow,
              "Capture refills released bank0 without losing other-bank state");
        for (k = 0; k < N; k = k + 1) begin
            axi_read(4*k, status_word, k == 0 ? 2 : 0);
            $sformat(check_description, "Refilled RAM word %0d matches next ordered sample", k);
            check(status_word === {16'd0, expected[k]}, check_description);
        end
        // 阶段八：总共只应产生并接受三帧 24 点；触发、EOC、DEN、DRDY、sample
        // 全部一一对应，既不能重复样本也不能只靠 RAM 内容正确来掩盖漏握手。
        check(samples == 3*N && accepted == 3*N,
              "Exactly three frames accepted through real XADC wrapper");
        check(conversions == samples && eoc_count == samples &&
              drdy_count == samples && den_count == samples,
              "Each conversion has exactly one EOC, DEN, DRDY and sample");
        $display("SUMMARY checks=%0d failures=0 CONV=%0d EOC=%0d DEN=%0d DRDY=%0d SAMPLE=%0d",
                 checks, conversions, eoc_count, den_count, drdy_count, samples);
        // 只有前面每项均通过才到达 TB_PASS；任何监视器或 check 失配会先停止仿真。
        $display("TB_PASS: tb_tgg_system_top - self-contained real UNISIM XADC + capture + AXI");
        $finish;
    end

    initial begin
        // 全局 500 us 看门狗覆盖 bank_ready、AXI READY/VALID 等所有等待点。
        // 超时输出整条采样链计数、ready 和 paused，便于区分 ADC 未返回与总线阻塞。
        #500000;
        begin $display("TB_FAIL: TIMEOUT: CONV=%0d EOC=%0d DEN=%0d DRDY=%0d SAMPLE=%0d ready=%b paused=%b",
               conversions, eoc_count, den_count, drdy_count, samples, dut.bank_ready, dut.paused); $finish; end
    end
endmodule
