`timescale 1ns/1ps

// 领航者 Zynq-7010/7020 的 PL 顶层。
//
// clk100 来自 PS 的 FCLK_CLK0，不是外部晶振。resetn 来自 PS 的
// FCLK_RESET0_N，低电平复位。vp_in/vn_in 是 XADC 模拟输入，必须在 XDC
// 中约束到当前核心板真实的 VP/VN 封装管脚。
//
// s_axi_* 是 AXI4-Lite 从设备接口：ARM 通过这组信号读采样 RAM、读状态，
// 并向 ACK/CONTROL 地址写命令。把它连接到 PS 的 M_AXI_GP0 时，通常要
// 经过 Vivado 的 AXI SmartConnect。
//
// N=4096 表示一帧 4096 个采样点。10 kHz 采样时，一帧约 409.6 ms；
// FFT 的原始频率间隔为 10000/4096=2.44140625 Hz。
// 模块职责：连接定时触发、XADC、两 bank 采集 RAM 和简化 AXI4-Lite 寄存器接口。
// 本顶层直接实现 RAM/bank 管理，没有实例化独立的 tgg_capture；全部接口共用 clk100，无跨时钟处理。
module tgg_system_top #(
    // CLK_HZ：clk100 的实际频率，单位 Hz，只用于分频计算，不会改变物理时钟。
    // XADC 静态分频仍按 100 MHz 设计，改此参数前应同时核查 XADC 时钟限制。
    parameter [31:0] CLK_HZ = 100_000_000,
    // FS_HZ：触发频率，单位 Hz；必须为正数且整除 CLK_HZ，分频周期至少 2 拍。
    // 还需留足真实转换与 DRP 时间，当前没有用 busy 限制新触发。
    parameter [31:0] FS_HZ  = 10_000,
    // N：每 bank 点数，需 N>=2 且为 2 的整数次幂，以匹配 bank/index 拼接地址。
    // 控制寄存器固定从 0x8000 起，为保持 RAM 窗口不与其重叠，应 N<=4096。
    parameter [31:0] N      = 4096,
    // AXI_AW：字节地址位宽，至少应为 16，才可访问 0x8000 控制区。
    // 这里是外设内部偏移；ARM 系统基地址在 Vivado Address Editor 另外分配。
    parameter [31:0] AXI_AW = 16
) (
    // clk100：PS 提供的 AXI、采样和 RAM 共用时钟，默认 100 MHz。
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 clk100 CLK", X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET resetn, FREQ_HZ 100000000" *)
    input  wire clk100,
    // resetn：低有效同步复位；顶层在 clk100 上升沿检查，XADC 原语另接其反相。
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 resetn RST", X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *)
    input  wire resetn,
    // vp_in：专用 XADC 模拟正输入，需按原理图约束实际封装管脚。
    input  wire vp_in,
    // vn_in：专用 XADC 模拟负输入，连接原语 VN，不是普通数字采样数据。
    input  wire vn_in,
    // AW 写地址通道：awaddr 是外设内字节偏移，命令地址完整比较，不忽略低两位。
    input  wire [AXI_AW-1:0]    s_axi_awaddr,
    // AWVALID：主机声明地址有效，与 AWREADY 同拍为 1 时才接收 AWADDR。
    input  wire s_axi_awvalid,
    // AWREADY：地址暂存器空闲且无待收 B 响应时为 1，AW/W 可按任意先后顺序到达。
    output wire s_axi_awready,
    // W 写数据通道：32 位数据，ACK/CONTROL 只使用最低字节中定义的命令位。
    input  wire [31:0]          s_axi_wdata,
    // WSTRB：各位表示对应字节有效；命令均在字节 0，仅检查 WSTRB[0]。
    // WSTRB[0]=0 时命令无副作用，仍正常返回 OKAY，其他三个字节不触发命令。
    input  wire [3:0]           s_axi_wstrb,
    // WVALID：主机声明 WDATA/WSTRB 有效，必须保持到与 WREADY 完成握手。
    input  wire s_axi_wvalid,
    // WREADY：数据暂存器空闲且无待收 B 响应时为 1，与 AWREADY 独立。
    output wire s_axi_wready,
    // B 写响应通道：BRESP 恒为 00/OKAY，写未定义地址也不会返回地址错误。
    output wire [1:0]           s_axi_bresp,
    // BVALID：配对写事务执行后置位，并保持到 BREADY 收取；期间阻止下一笔写入。
    output reg s_axi_bvalid,
    // BREADY：主机准备接收写响应；BVALID&&BREADY 的上升沿结束响应。
    input  wire s_axi_bready,
    // AR 读地址通道：araddr 为字节地址；RAM 使用其右移 2 位结果，每样本占一个 32 位槽。
    input  wire [AXI_AW-1:0]    s_axi_araddr,
    // ARVALID：主机声明读地址有效，与 ARREADY 在同一上升沿为 1 才接受。
    input  wire s_axi_arvalid,
    // ARREADY：没有待收 R 响应时为 1，只容纳一笔读事务，不支持多笔读流水。
    output wire s_axi_arready,
    // R 读响应通道：RDATA 在 AR 握手边沿寄存，RAM 16 位样本放低 16 位。
    // RVALID=1 且 RREADY=0 时数据保持不变，不跟随当前 ARADDR 变化。
    output reg [31:0]          s_axi_rdata,
    // RRESP：固定为 00/OKAY；未定义读地址返回零，不产生 SLVERR/DECERR。
    output wire [1:0]           s_axi_rresp,
    // RVALID：与寄存 RDATA 同拍置位，直到主机 RREADY 接受才清零。
    output reg s_axi_rvalid,
    // RREADY：主机准备接收读数据；与 RVALID 同拍为 1 表示读响应完成。
    input  wire s_axi_rready,
    // irq_frame：任一 bank_ready 为 1 即持续为高的电平中断；需 ACK 释放所有就绪帧才拉低。
    output wire irq_frame,
    // convst_dbg：直接引出内部单拍转换触发，便于仿真或示波器检查采样频率。
    output wire convst_dbg
);
    // MEM_WORDS：两 bank 总样本字数；每个 16 位样本在 AXI 占 4 字节槽，总窗口跨度 8*N 字节。
    localparam [31:0] MEM_WORDS = 2*N;
    // IW：bank 内采样位置位宽，N 为 2 幂时 {wr_bank,wr_index} 完整覆盖两个 bank。
    localparam [31:0] IW = $clog2(N);
    // MW：完整 RAM 字地址位宽；此常量目前未直接使用，读索引来自 AXI 地址切片。
    localparam [31:0] MW = $clog2(MEM_WORDS);
    // mem：2*N 个 16 位采样字；ram_style 是综合映射到块 RAM 的提示。
    // RAM 不复位，未完成新帧之前内容不保证有效；完整性由 bank_ready 表示。
    (* ram_style = "block" *) reg [15:0] mem [0:MEM_WORDS-1];
    // wr_index：当前 bank 内下一次写入的位置，范围 0..N-1。
    reg [IW-1:0] wr_index;
    // wr_bank：当前或暂停后待写的 bank，帧完成时翻转。
    reg wr_bank;
    // paused：两个 bank 均被未读数据占用时暂停；禁止新定时触发并忽略迟到 sample_valid。
    reg paused;
    // bank_ready：bit0/bit1 分别表示 bank0/bank1 已写满且等待软件确认释放。
    reg [1:0]    bank_ready;
    // overflow：粘滞溢出标志，暂停时置位；ACK 恢复后仍保留，只有复位或 CONTROL 写 1 才清除。
    reg overflow;
    // active：!paused 的组合状态，作为 STATUS bit2 供软件读取。
    wire active;
    // sample_valid：wrapper 返回的单拍结果有效指示，本顶层在后续上升沿消费该结果。
    wire sample_valid;
    // sample_code：wrapper 从 DO[15:4] 提取的原始 12 位码，与 sample_valid 配对。
    wire [11:0]   sample_code;
    // xadc_busy：原语转换忙输出，当前仅接到内部线网，没有用于限流或状态寄存器。
    wire xadc_busy;
    // convst：定时分频器的单拍输出，连接 XADC CONVST 和调试输出。
    wire convst;
    // aw_hold/w_hold：地址/数据已经各自接收的有效标志，允许 AW 先到、W 先到或同拍到达。
    reg aw_hold, w_hold;
    // awaddr_hold：AW 握手时寄存地址，是否有效由 aw_hold 决定，无需复位清载荷。
    reg [AXI_AW-1:0] awaddr_hold;
    // wdata_hold：W 握手时寄存数据，是否有效由 w_hold 决定。
    reg [31:0]   wdata_hold;
    // wstrb_hold：与 WDATA 同拍保存的字节使能，执行时不能改用主机当前 WSTRB。
    reg [3:0]    wstrb_hold;
    // wr_en：地址/数据均已暂存且无待收 B 响应时，执行一笔配对写。
    // hold 用非阻塞赋值更新，新收的 AW/W 最早在下一上升沿提交，不能在同边沿立即执行。
    wire           wr_en = aw_hold && w_hold && !s_axi_bvalid;
    // ACK：偏移 0x8004，低两位写 1 分别释放 bank0/bank1，写 0 不操作。
    // 只有配对事务且 WSTRB[0]=1 时才产生内部 ACK；不把被字节屏蔽的数据当成命令。
    wire [1:0]     ack_bits = (wr_en && wstrb_hold[0] && awaddr_hold == 16'h8004)
                              ? wdata_hold[1:0] : 2'b00;
    // CONTROL：偏移 0x8008，bit0 写 1 清 overflow；写 0 不操作，其余位不使用。
    wire           clear_overflow = wr_en && wstrb_hold[0] && awaddr_hold == 16'h8008
                                    && wdata_hold[0];

    // 组合状态与中断输出：IRQ 随 bank_ready 变化，表示仍有至少一帧待取。
    assign active          = !paused;
    assign convst_dbg      = convst;
    assign irq_frame       = bank_ready[0] | bank_ready[1];
    // 每个写通道只暂存一份载荷，等待 BREADY 的背压期间不再接收新的 AW/W。
    assign s_axi_awready   = !aw_hold && !s_axi_bvalid;
    assign s_axi_wready    = !w_hold  && !s_axi_bvalid;
    // 已有 RVALID 时不接新 AR，即使该拍 RREADY=1，也需等响应清除后再接下一笔。
    assign s_axi_arready   = !s_axi_rvalid;
    // 所有读写响应恒为 OKAY，软件不能仅凭响应码判断地址是否受支持。
    assign s_axi_bresp     = 2'b00;
    assign s_axi_rresp     = 2'b00;

    // 暂停时分频 enable=0 并清计数；恢复后重新计满完整采样周期才产生下一次 CONVST。
    tgg_sample_tick #(.CLK_HZ(CLK_HZ), .SAMPLE_HZ(FS_HZ)) i_tick (
        .clk(clk100), .resetn(resetn), .enable(!paused), .tick(convst)
    );
    // XADC wrapper 处理转换结束与 DRP 读取；其输出没有零点、增益、温度或磁光校准。
    tgg_xadc i_adc (
        .clk(clk100), .resetn(resetn), .convst(convst),
        .vp_in(vp_in), .vn_in(vn_in), .sample_valid(sample_valid),
        .sample_code(sample_code), .busy(xadc_busy)
    );

    // AXI 时序块：分开捕获 AW/W、配对执行并返回 B；AR 握手时同步取数并寄存 RDATA/RVALID。
    // 所有 <= 均在边沿后更新，条件读取旧 hold/VALID，读取状态和 RAM 也得到更新前快照。
    always @(posedge clk100) begin
        // 复位清有效标志和 RDATA；载荷寄存器虽不复位，但有效标志为零时不会被执行。
        if (!resetn) begin
            aw_hold       <= 1'b0;
            w_hold        <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
        end else begin
            // AW 成功握手才锁存地址，随后 aw_hold 使 AWREADY 拉低等待数据配对。
            if (s_axi_awvalid && s_axi_awready) begin
                aw_hold    <= 1'b1;
                awaddr_hold <= s_axi_awaddr;
            end
            // W 成功握手同时保存数据与字节使能，不依赖 AW 到达顺序。
            if (s_axi_wvalid && s_axi_wready) begin
                w_hold     <= 1'b1;
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
            end
            // 配对事务提交：清两个 hold、置 BVALID；同拍另一时序块消费 ack_bits/clear_overflow。
            // 写未定义地址仍有响应但无副作用，本接口也不提供通过 AXI 改写采样 RAM 的路径。
            if (wr_en) begin
                aw_hold      <= 1'b0;
                w_hold       <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end
            // 旧 BVALID 与 BREADY 握手后清响应；wr_en 要求旧 BVALID=0，因此不会同拍吞掉新生成的响应。
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
            // AR 握手边沿寄存读数据，边沿后 RVALID=1；这是同步读，不是 ARADDR 的组合读。
            // 背压时没有新 AR 握手，RDATA/RVALID 保持到 RREADY 接受。
            if (s_axi_arvalid && s_axi_arready) begin
                // STATUS：偏移 0x8000，bit3=overflow、bit2=active、bit[1:0]=bank_ready，其余为 0。
                // 若同拍 bank 状态也在变化，本次读回的是变化前的状态快照。
                if (s_axi_araddr == 16'h8000)
                    s_axi_rdata <= {28'd0, overflow, active, bank_ready};
                // RAM 窗口用地址 [AXI_AW-1:2] 作为字索引，即字节地址除以 4；忽略低两位，未做非对齐报错。
                // bank0 偏移 0、bank1 偏移 4*N；默认分别为 0x0000/0x4000。
                // 不检查 ready；读未写区无效，同拍同址读写在 RTL 仿真中读旧值，实际模式需核对综合 RAM 映射。
                else if (s_axi_araddr[AXI_AW-1:2] < MEM_WORDS)
                    s_axi_rdata <= {16'd0, mem[s_axi_araddr[AXI_AW-1:2]]};
                // 其余读地址返回 0，包括未定义读回行为的 ACK/CONTROL，响应码仍为 OKAY。
                else
                    s_axi_rdata <= 32'd0;
                // 数据与有效标志一起寄存，旧 RVALID=0 时后面的响应清除条件不会成立。
                s_axi_rvalid <= 1'b1;
            end
            // 已有读响应被主机接收后清 RVALID，之后才能再次拉高 ARREADY。
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end

    // 采集 RAM 和 bank 状态。
    // XADC 已在 tgg_xadc 中把左对齐的 DO[15:4] 提取为 12 位 code；这里
    // 前面补 4 个 0 存成 16 位。AXI 读端再把它放到 32 位数据的低 16 位。
    // bank_ready=1 表示该 bank 已经填满，ARM 读完后必须写 ACK 释放它。
    // 采集/bank 时序块与 AXI 块并行：命令来自已锁存的写载荷，采样来自旧 sample_valid/code。
    // ready_next 用阻塞赋值 = 汇总本拍 ACK/帧完成，持久状态与 RAM 写用非阻塞 <= 同步提交。
    always @(posedge clk100) begin : capture_logic
        // ready_next：本拍临时下一状态，每拍先复制 bank_ready，再依次应用 ACK 与帧完成。
        reg [1:0] ready_next;
        // 复位从 bank0 第 0 点重启，清 ready/paused/overflow，不清 RAM。
        if (!resetn) begin
            wr_index   <= {IW{1'b0}};
            wr_bank    <= 1'b0;
            bank_ready <= 2'b00;
            overflow   <= 1'b0;
            paused     <= 1'b0;
        end else begin
            // 先处理 ACK，表示软件已取走对应帧；若同拍又完成该 bank，新帧分支随后重新置 ready，
            // 最终保留新完成帧而不会让旧 ACK 将它误清除。
            ready_next = bank_ready;
            if (ack_bits[0]) ready_next[0] = 1'b0;
            if (ack_bits[1]) ready_next[1] = 1'b0;
            bank_ready <= ready_next;
            // 清溢出只清状态，不释放 bank、不解除 paused，也不恢复已经错过的样本。
            // 若同拍稍后又执行 overflow<=1，后面的非阻塞赋值优先，最终仍为 1。
            if (clear_overflow)
                overflow <= 1'b0;

            // 暂停分支优先于采样，本拍迟到的 sample_valid 也不写 RAM；目标 bank 被释放后才可恢复。
            if (paused) begin
                // ACK 释放目标后清 paused、索引归零；这一拍仍走暂停分支，不会同时写样本。
                // 分频器在下一拍看到恢复使能，再从完整周期开始计数。
                if (!ready_next[wr_bank]) begin
                    paused   <= 1'b0;
                    wr_index <= {IW{1'b0}};
                end
            // 未暂停且结果有效：使用本拍旧 wr_bank/wr_index 确定写地址。
            end else if (sample_valid) begin
                // 12 位码在 RAM 中高 4 位补零存成 16 位字，AXI 读出再补高 16 位组成 32 位数据。
                mem[{wr_bank, wr_index}] <= {4'd0, sample_code};
                // 写完最后一点则置当前 bank ready，并切到另一个 bank 的第 0 点。
                // 后面的 bank_ready<=ready_next 覆盖本块前面的安排，提交含本拍完成事件的最终状态。
                if (wr_index == N-1) begin
                    ready_next[wr_bank] = 1'b1;
                    bank_ready          <= ready_next;
                    wr_bank             <= ~wr_bank;
                    wr_index            <= {IW{1'b0}};
                    // ~wr_bank 仍使用更新前值，即下一目标 bank；若它尚未释放，则暂停而不覆盖未读帧。
                    // 置 sticky overflow 记录已经发生的暂停，之后 ACK 恢复也不会自动清除。
                    if (ready_next[~wr_bank] && !ack_bits[~wr_bank]) begin
                        paused   <= 1'b1;
                        overflow <= 1'b1;
                    end
                end else begin
                    // 帧未填满时只推进 bank 内索引，当前 bank 仍不能作为完整帧读取。
                    wr_index <= wr_index + 1'b1;
                end
            end
        end
    end
endmodule
