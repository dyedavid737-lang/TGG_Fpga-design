`timescale 1ns/1ps

// Zynq-7000 XADC 前端。
//
// VP/VN 是芯片内部 XADC 的模拟差分输入端，最终连接到领航者底板的 XADC
// 接口。vp_in/vn_in 只是 RTL 端口名，实际封装管脚必须在 XDC 中填写。
//
// XADC 的几个缩写：
//   - DCLK：XADC 的数字配置/数据读取时钟，本工程使用 100 MHz clk。
//   - CONVST：Convert Start，上升沿启动一次事件采样。
//   - EOC：End Of Conversion，一次转换结束。
//   - DRDY：DRP Data Ready，DRP 读出的数据有效。
//   - DO[15:4]：XADC 将 12 位结果左对齐放在 16 位总线的高 12 位。
//
// INIT_40 选择 VP/VN（通道 3）、扩展采集时间并打开事件采样；INIT_41
// 选择单通道模式并打开校准；INIT_42=0400 选择 DCLK/4。100 MHz/4=25 MHz，
// 小于 XADC 推荐的 26 MHz ADC 时钟上限，同时远高于本工程 10 kHz 的需求。
// 模块职责：实例化 7 系列 XADC，事件触发采样 VP/VN，并用 DRP 读取转换结果。
// 本模块没有幅值标定或磁场反演；输出只是 ADC 的原始 12 位无符号码。
// 触发频率必须留足转换与 DRP 读取时间；新 EOC 在 read_pending=1 时不会排队。
module tgg_xadc (
    // clk：wrapper 逻辑与原语 DCLK 共用的数字时钟，当前配置按 100 MHz 设计。
    input  wire clk,
    // resetn：低有效复位；wrapper 寄存器在 clk 上升沿同步清零，同时取反送原语 RESET。
    input  wire resetn,
    // convst：XADC 事件采样启动脉冲，来自同一时钟域采样分频器；上升沿启动转换。
    input  wire convst,
    // vp_in：专用 VP 模拟输入封装端，Verilog 端口是 wire，但物理意义是模拟电压正端。
    input  wire vp_in,
    // vn_in：专用 VN 模拟输入负端；数字仿真中的 0/1 端口值不能等价表示实际模拟输入电压。
    input  wire vn_in,
    // sample_valid：成功收到 DRDY 后寄存输出的单拍有效标志，与 sample_code 同步更新。
    output reg sample_valid,
    // sample_code：提取 DO[15:4] 的 12 位 ADC 码；没有新 DRDY 时保持上一次结果。
    output reg [11:0] sample_code,
    // busy：直接导出原语 BUSY，反映 ADC 转换忙状态；当前 wrapper 不用它拒绝 convst。
    output wire busy
);
    // daddr：7 位 DRP 寄存器地址，固定为 VP/VN 状态寄存器 0x03。
    wire [6:0]  daddr;
    // den：DRP 读使能寄存器，只能拉高一个 DCLK 周期，不能用它持续表示“等待数据”。
    reg den;
    // drdy：原语返回的 DRP 数据就绪；高电平对应 do_bus 中本次读出的有效结果。
    wire drdy;
    // do_bus：原语 16 位 DRP 读数据；12 位转换码左对齐，wrapper 忽略低 4 位。
    wire [15:0] do_bus;
    // eoc：一次 ADC 转换完成指示；wrapper 在无未完成读事务时据此发出 DEN。
    wire eoc;
    // eos：序列转换结束输出，本单通道采集逻辑未使用。
    wire eos;
    // channel：原语当前转换通道号，连接出来便于观察，未参与地址选择。
    wire [4:0]  channel;
    // alm：原语报警总线，当前仅接线，没有上报到顶层寄存器。
    wire [7:0]  alm;
    // ot：原语过温报警输出，当前采集逻辑不使用。
    wire ot;
    // jtagbusy/jtaglocked/jtagmodified：JTAG 对 XADC 的访问状态，本 wrapper 不参与 JTAG 仲裁。
    wire jtagbusy, jtaglocked, jtagmodified;
    // read_pending：一次 DRP 读取尚未返回的状态；DEN 拉低后仍保持，直到 DRDY 才解除。
    reg read_pending;

    assign daddr = 7'h03; // VP/VN status register
    // 当前主工程使用单拍 DEN 发起读取，再由 read_pending 独立等待 DRDY。
    // 读事务尚未返回时不能把 DEN 持续拉高，也不能重复发出读取请求。

    // The XADC DRP read is issued immediately after EOC; DRDY returns the
    // left-justified 12-bit conversion in DO[15:4].
    // 时序流程：看到旧 eoc 时寄存一个 DEN 脉冲，原语在后续 DCLK 边沿接收请求；
    // 随后等待 DRDY，并在对应边沿锁存 DO[15:4]。所有 <= 都是非阻塞赋值，
    // 因此 sample_valid/code 在本边沿之后更新，下游时序块在下一边沿才消费它们。
    always @(posedge clk) begin
        // 复位清空读事务和已输出样本；不在复位释放瞬间自动发起读取。
        if (!resetn) begin
            den          <= 1'b0;
            read_pending <= 1'b0;
            sample_valid <= 1'b0;
            sample_code  <= 12'd0;
        end else begin
            // 每个正常工作拍先默认清零 DEN 和 sample_valid；满足后续条件才各自再置 1。
            den <= 1'b0;
            sample_valid <= 1'b0;
            // 只有未在等待 DRDY 时才接受 EOC；读请求发出后置 pending，防止同一次读取重复请求。
            if (eoc && !read_pending) begin
                den <= 1'b1;
                read_pending <= 1'b1;
            // DRDY 返回时结束 pending。若 EOC 与 DRDY 同拍且旧 pending=1，走此分支，
            // 该拍 EOC 不会另外排队；系统采样周期应足够长，避免这种重叠。
            end else if (drdy)
                read_pending <= 1'b0;

            // 数据锁存独立于上面的事务状态分支；任何 DRDY 都会输出一个 sample_valid。
            // 真正的单拍输出依赖原语 DRDY 也为单拍，本模块没有额外边沿检测。
            if (drdy) begin
                sample_code  <= do_bus[15:4];
                sample_valid <= 1'b1;
            end
        end
    end

    // 原语静态配置分组：0x40 配置输入通道/采集与事件模式，0x41 配置单通道序列及校准/报警，
    // 0x42 设置 ADC 时钟分频。若修改 clk 频率，应同时核查 DCLK 与 ADCCLK 的器件限制。
    XADC #(
        .INIT_40(16'h0303), // CH=3 (VP/VN), ACQ=1, EC=1
        .INIT_41(16'h31F0), // SEQ=0011 single channel, calibration on,
                            // unused alarms disabled
        .INIT_42(16'h0400), // DCLK divider = 4
        // INIT_43..INIT_4F：其余配置/序列相关寄存器保持本工程给定的零初值；
        // 本设计不在运行时通过 DRP 改写这些配置。
        .INIT_43(16'h0000), .INIT_44(16'h0000), .INIT_45(16'h0000),
        .INIT_46(16'h0000), .INIT_47(16'h0000),
        .INIT_48(16'h0000), .INIT_49(16'h0000), .INIT_4A(16'h0000),
        .INIT_4B(16'h0000), .INIT_4C(16'h0000), .INIT_4D(16'h0000),
        .INIT_4E(16'h0000), .INIT_4F(16'h0000),
        // SIM_DEVICE：选择 7 系列行为模型。原语模拟电压激励由仿真模型提供，不能由 wire 逻辑电平替代。
        .SIM_DEVICE("7SERIES")
    ) i_xadc (
        // DRP 端口组：DCLK 为数字访问时钟；DADDR 选地址；DEN 请求一次访问；
        // DWE 固定为 0 表示只读，DI 固定为零且不会写入配置寄存器。
        .DCLK(clk), .DADDR(daddr), .DEN(den), .DWE(1'b0), .DI(16'd0),
        // 原语复位为高有效，故连接外部低有效复位的反相。
        .RESET(~resetn),
        // 事件触发端口组：使用 CONVST 启动；不使用独立 CONVSTCLK 路径。
        .CONVST(convst), .CONVSTCLK(1'b0),
        // 模拟输入端口组：只测专用 VP/VN，16 路辅助模拟输入均不参与本设计。
        .VP(vp_in), .VN(vn_in), .VAUXP(16'd0), .VAUXN(16'd0),
        // 转换/读取状态端口组：EOC 表示转换完成，DRDY 表示 DRP 数据已返回，两者不是同一个握手。
        .DO(do_bus), .DRDY(drdy), .EOC(eoc), .EOS(eos), .BUSY(busy),
        // 诊断端口组：通道、报警与过温仅连接到内部线网，未加入采样结果或错误标志。
        .CHANNEL(channel), .ALM(alm), .OT(ot),
        // JTAG 诊断端口组：这些输出未驱动采集状态机；使用 JTAG 调试时仍需避免外部竞争访问。
        .JTAGBUSY(jtagbusy), .JTAGLOCKED(jtaglocked),
        .JTAGMODIFIED(jtagmodified)
    );
endmodule
