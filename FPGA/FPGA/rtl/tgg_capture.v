`timescale 1ns/1ps

// 双缓冲采集 RAM。
//
// 每个 bank 默认保存 4096 个 16 位采样字。PL（FPGA 逻辑）写当前 bank，
// PS（ARM）读取另一个已经写满的 bank。ARM 读完整个 bank 后，通过 bank_ack
// 写回一个脉冲，告诉 PL“这个 bank 可以重新使用”。
//
// 如果两个 bank 都已经写满而 ARM 还没有释放任何一个 bank，paused 会变成
// 1，后续采样暂时停止，并置 overflow=1。这样宁可明确报告丢帧，也不会
// 静默覆盖 ARM 尚未读完的数据。
// 模块职责：独立双 bank 数据缓冲，提供同步 RAM 读口，不包含 AXI 总线协议。
// 所有接口均属于 clk 时钟域；跨时钟域的读者或 ACK 必须在外部完成同步。
module tgg_capture #(
    // N：每个 bank 的采样字数，默认 4096。要求 N>=2 且为 2 的整数次幂；
    // 因为内部用 {wr_bank,wr_index} 拼地址，非 2 幂时会出现空洞或越界。
    parameter [31:0] N = 4096,
    // ADDR_W：整块 2*N 字 RAM 的字地址位宽；应保持为 $clog2(2*N)，不包含字节偏移。
    parameter [31:0] ADDR_W = $clog2(2*N)
) (
    // clk：采样写入、状态维护与 RAM 同步读取共用的时钟。
    input  wire clk,
    // resetn：低有效同步复位，清状态和读输出；不会遍历清零 RAM 内容。
    input  wire resetn,
    // sample_valid：高电平表示本拍 sample_code 有效；未暂停时每个有效拍写入一个采样字。
    input  wire sample_valid,
    // sample_code：原始 12 位无符号 ADC 码，存储时在高 4 位补零形成 16 位字。
    input  wire [11:0]          sample_code,
    // bank_ack[0]/[1]：读者释放 bank0/bank1 的同步请求，通常为单拍脉冲；
    // 只能在读取完成之后确认，持续拉高可能使未来新帧被立即释放。
    input  wire [1:0]           bank_ack,
    // bank_ready[0]/[1]：对应 bank 已写满且尚未被 ACK 释放；读者应只读取 ready 的完整帧。
    output reg [1:0]           bank_ready,
    // overflow：粘滞溢出标志；因两个 bank 均未释放而暂停时置 1，本模块中只能通过复位清零。
    output reg overflow,
    // active：等于 !paused，表示可以接收新采样；本模块不直接关闭外部 ADC，应由上层据此停止触发。
    output wire active,
    // mem_rd_addr：0 至 2*N-1 的 RAM 字地址；bank0 为 0..N-1，bank1 为 N..2*N-1。
    input  wire [ADDR_W-1:0]    mem_rd_addr,
    // mem_rd_data：在时钟上升沿读取该拍 mem_rd_addr 后更新的 16 位数据；
    // 不是组合读口，地址改变后需等下一个 clk 上升沿，复位期间输出为 0。
    output reg [15:0]          mem_rd_data
);
    // IW：bank 内采样索引位宽；在 N 为 2 幂时与地址中的低位索引严格对应。
    localparam [31:0] IW = $clog2(N);
    // mem：共 2*N 个 16 位采样字，ram_style 为综合映射到块 RAM 的提示。
    // RAM 不复位，未被有效采样写过的地址内容不保证为零；复位后必须等待完整新帧。
    (* ram_style = "block" *) reg [15:0] mem [0:(2*N)-1];
    // wr_index：当前写 bank 内的采样位置，从 0 数到 N-1。
    reg [IW-1:0] wr_index;
    // wr_bank：当前/下一次准备写入的 bank 编号；一帧完成后立即切到另一个 bank。
    reg wr_bank;
    // paused：写入暂停状态；目标 bank 尚未释放时置 1，不接收新的 sample_valid。
    reg paused;

    // ack0/ack1：ACK 仅对已经 ready 的 bank 生效；对空闲 bank 的请求不改变 ready 状态。
    wire ack0 = bank_ack[0] && bank_ready[0];
    wire ack1 = bank_ack[1] && bank_ready[1];

    // active 是 paused 的组合反相，不代表每拍都有样本；sample_valid 仍决定实际写入。
    assign active = !paused;

    // AXI 侧读口是同步读。mem_rd_addr 是“字地址”而不是字节地址：
    // 最高的 bank 位选择 bank0/bank1，低 IW 位选择该 bank 内的采样点。
    // 同步读时序：此拍读取地址与旧 mem 内容，经非阻塞赋值在本拍稍后更新 mem_rd_data。
    // 若同拍同址发生写入，本 RTL 仿真读到旧值；实际块 RAM 的同址读写模式应以综合映射为准。
    // 正常软件流程只读 ready bank，可避免读写冲突；硬件读口本身不检查 bank_ready。
    always @(posedge clk) begin
        if (!resetn) begin
            mem_rd_data <= 16'd0;
        end else begin
            mem_rd_data <= mem[mem_rd_addr];
        end
    end

    // 写入与 bank 管理时序块。ready_next 是本拍组合临时量，用阻塞赋值 = 汇总 ACK 与帧完成；
    // bank_ready/wr_index 等状态用 <= 在边沿结束后统一提交，所有条件默认读取旧寄存器值。
    always @(posedge clk) begin : writer
        // ready_next：临时的下一状态，不是额外的握手寄存器；每个非复位拍先从 bank_ready 重新赋值。
        reg [1:0] ready_next;
        if (!resetn) begin
            // 复位把两帧均标为未就绪，并从 bank0 第 0 点开始；RAM 数据本身不清除。
            bank_ready <= 2'b00;
            overflow   <= 1'b0;
            wr_index   <= {IW{1'b0}};
            wr_bank    <= 1'b0;
            paused     <= 1'b0;
        end else begin
            // 先处理释放请求，再处理本拍采样/帧结束；同拍事件统一反映到 ready_next。
            ready_next = bank_ready;
            if (ack0) ready_next[0] = 1'b0;
            if (ack1) ready_next[1] = 1'b0;
            bank_ready <= ready_next;

            // 暂停分支优先于 sample_valid：本拍即使有迟到样本也不写入。
            // 只要目标 wr_bank 已被 ACK 释放，就退出暂停；实际恢复写入从后续时钟拍开始。
            if (paused) begin
                // The producer waits instead of silently overwriting unread
                // data.  At 10 kHz this is only reached if the PS misses both
                // 409.6 ms processing deadlines.
                // 恢复时仍保持原定目标 bank，把索引归零；overflow 不在这里清除，保留发生过暂停的证据。
                if (!ready_next[wr_bank]) begin
                    paused   <= 1'b0;
                    wr_index <= {IW{1'b0}};
                end
            // 未暂停且有有效样本时，使用本拍旧 wr_bank/wr_index 确定写入地址。
            end else if (sample_valid) begin
                // 高 4 位补零保持 12 位码值；非阻塞 RAM 写入不会立即改变同拍读口看到的旧数据。
                mem[{wr_bank, wr_index}] <= {4'd0, sample_code};
                // 写完最后一点即将当前 bank 标为 ready，再切到另一个 bank 的第 0 点。
                // 同一时序块后面的 bank_ready<=ready_next 覆盖前面的赋值，提交包含“帧完成”的最终状态。
                if (wr_index == N-1) begin
                    ready_next[wr_bank] = 1'b1;
                    bank_ready          <= ready_next;
                    wr_bank             <= ~wr_bank;
                    wr_index            <= {IW{1'b0}};
                    // 此处 ~wr_bank 仍是旧 bank 的反相，即下一目标 bank；若其仍被占用，则暂停，绝不覆盖未读帧。
                    // overflow 一旦置位即保持，即使随后 ACK 恢复采集也不会自动清零。
                    if (ready_next[~wr_bank] && !bank_ack[~wr_bank]) begin
                        paused   <= 1'b1;
                        overflow <= 1'b1;
                    end
                end else begin
                    // 帧尚未填满时只推进 bank 内索引，不改变当前写 bank。
                    wr_index <= wr_index + 1'b1;
                end
            end
        end
    end

    // `mem_rd_addr` is driven by the AXI wrapper.  It is kept as an explicit
    // port so the capture block can also be used with an AXI BRAM Controller.
endmodule
