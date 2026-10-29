`timescale 1ns/1ps
// 【用途与运行方法】双 bank 采样缓存 tgg_capture.v 的独立功能测试台。
// Vivado 仿真顶层选 tb_tgg_capture；输入采样码、VALID、ACK、读地址均由本 TB 产生。
// clk=100 MHz；N=8 是加速验证参数，每个 bank 八字、两 bank 共十六字。
// 生产默认 N=4096，因此本测试不代表真实 4096 点帧长或系统采样频率。
// 本 TB 直接提供数字采样，没有 XADC 转换或 UNISIM 模型，也无需 design.txt。
// 正常流程在 1 us 左右结束；10 us 看门狗用于阻止握手/时序错误造成挂起。
// 验证重点：逐字读回、满帧状态、双满暂停、不覆盖未读数据、ACK 恢复、
// bank 复用与另一 bank 数据保留、overflow 粘滞属性，以及复位清状态。
module tb_tgg_capture;
    // i 为各阶段逐字发送/回读的循环索引；N 与 DUT 参数和预期帧长保持一致。
    integer i;
    localparam N=8;
    // 驱动输入：resetn 低有效；sample_valid=1 的上升沿接收 sample_code[11:0]。
    // bank_ack[0]/[1] 分别表示消费者已经处理完 bank0/bank1，可以释放它。
    reg clk=0, resetn=0, sample_valid=0;
    reg [11:0] sample_code=0;
    reg [1:0] bank_ack=0;
    // 状态输出：bank_ready 指示可读取的完整帧；active=0 表示暂停接受采样；
    // overflow 一旦因双满置位会保持，ACK 不负责清除此标志，复位才清除。
    wire [1:0] bank_ready;
    wire overflow, active;
    // 读接口地址 0..7 对应 bank0，8..15 对应 bank1。
    // 数据为 16 位容器，预期高四位补零、低十二位是 ADC 码。
    reg [3:0] mem_rd_addr=0;
    wire [15:0] mem_rd_data;
    always #5 clk=~clk;
    tgg_capture #(.N(N)) dut(.clk(clk),.resetn(resetn),.sample_valid(sample_valid),.sample_code(sample_code),.bank_ack(bank_ack),.bank_ready(bank_ready),.overflow(overflow),.active(active),.mem_rd_addr(mem_rd_addr),.mem_rd_data(mem_rd_data));
    // push(value)：在下降沿先放稳定采样码并拉高 VALID，下一下降沿拉低。
    // 因而只有中间一个上升沿接受该值；下降沿驱动避免与 DUT 上升沿逻辑争用。
    task automatic push(input integer value);
        begin
        @(negedge clk); sample_code=value; sample_valid=1;
        @(negedge clk); sample_valid=0;
        end
    endtask
    // read_word(addr, expected)：下降沿换读地址，等一个上升沿和 1 ns 后核对。
    // 参考值来自调用者提供的常量序列，不能用 DUT 自己读出的数据作参考。
    // 四态逐字比较也会检测未初始化数据、寻址错误及高位补零错误。
    task automatic read_word(input integer addr, input integer expected);
        begin
        @(negedge clk); mem_rd_addr=addr;
        @(posedge clk); #1;
        if (mem_rd_data !== expected[15:0])
            begin $display("TB_FAIL: capture"); $display("RAM[%0d]=%0d, expected %0d",addr,mem_rd_data,expected); $finish; end
        end
    endtask
    // acknowledge(mask)：保持 ACK 一个完整时钟，再等待一个上升沿和 1 ns。
    // 返回时 ready 和暂停/恢复状态已经完成寄存更新，调用者可立即检查。
    task automatic acknowledge(input reg [1:0] mask);
        begin
        @(negedge clk); bank_ack=mask;
        @(negedge clk); bank_ack=0;
        @(posedge clk); #1;
        end
    endtask
    initial begin
        // 阶段一：复位三拍后向 bank0 送入 100..107，要求仅 bank0 ready，
        // 采集继续 active=1 且没有 overflow，然后逐字验证 bank0。
        repeat(3) @(negedge clk); resetn=1;
        for(i=0;i<N;i=i+1) push(100+i);
        @(posedge clk); #1;
        if(bank_ready!==2'b01 || !active || overflow)
            begin $display("TB_FAIL: capture"); $display("bad first bank status"); $finish; end
        for(i=0;i<N;i=i+1) read_word(i,100+i);
        $display("CHECK: bank0 captured 100..107 and read back correctly at %0t",$time);
        // 阶段二：继续向 bank1 送 200..207；此时两个 bank 都满，
        // 应暂停并置 overflow。独立检查 bank1 八个字的寻址和内容。
        for(i=0;i<N;i=i+1) push(200+i);
        @(posedge clk); #1;
        if(bank_ready!==2'b11 || active || !overflow)
            begin $display("TB_FAIL: capture"); $display("full banks did not pause with overflow"); $finish; end
        for(i=0;i<N;i=i+1) read_word(N+i,200+i);
        $display("CHECK: both banks full, active=0 and overflow=1 at %0t",$time);
        // 阶段三：暂停时故意再送 999，随后重读 bank0[0]，必须仍是 100。
        // 这验证满缓存保护，不能只凭 active 状态位就认为未读数据受保护。
        push(999);
        read_word(0,100);
        $display("CHECK: paused write did not overwrite unread data");
        // 阶段四：ACK 仅释放 bank0，bank1 保留 ready；恢复后填 300..307。
        // bank0 再满时应再次暂停；回读两 bank，证明复用 bank0 未破坏 bank1。
        acknowledge(2'b01);
        if(bank_ready!==2'b10 || !active)
            begin $display("TB_FAIL: capture"); $display("acknowledge did not release bank0 and resume"); $finish; end
        for(i=0;i<N;i=i+1) push(300+i);
        @(posedge clk); #1;
        if(bank_ready!==2'b11 || active || !overflow)
            begin $display("TB_FAIL: capture"); $display("reused bank0 completion status incorrect"); $finish; end
        for(i=0;i<N;i=i+1) read_word(i,300+i);
        for(i=0;i<N;i=i+1) read_word(N+i,200+i);
        $display("CHECK: bank0 reused for 300..307; bank1 data retained");
        // 阶段五：同时释放两个 bank 后 ready=00、active=1，
        // 但历史 overflow 应继续为 1，验证它与 bank 就绪状态分开保持。
        acknowledge(2'b11);
        if(bank_ready!==2'b00 || !active || !overflow)
            begin $display("TB_FAIL: capture"); $display("release-both or sticky-overflow status incorrect"); $finish; end
        // 阶段六：再次低电平复位两拍，要求 ready 和 overflow 清零且 active 恢复。
        // 本段检查控制状态，不要求复位擦除缓存 RAM 中的历史内容。
        @(negedge clk); resetn=0;
        repeat(2) @(negedge clk); resetn=1;
        @(posedge clk); #1;
        if(bank_ready!==2'b00 || !active || overflow)
            begin $display("TB_FAIL: capture"); $display("reset did not clear ready/overflow"); $finish; end
        // 任一阶段失配即输出 TB_FAIL 并结束；只有全部阶段完成才输出 TB_PASS。
        $display("TB_PASS: capture RAM, full-bank pause, no overwrite, ACK resume, reuse, sticky overflow and reset");
        $finish;
    end
    // 独立 10 us 看门狗：即使主测试没有走到最终判断，也会明确报告超时失败。
    initial begin #10000; begin $display("TB_FAIL: capture"); $display("test timeout"); $finish; end end
endmodule
