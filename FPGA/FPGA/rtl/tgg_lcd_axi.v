`timescale 1ns/1ps
// AXI text/plot display, RGB888 DE mode. See README_LCD.md for memory map.
module tgg_lcd_axi #(
    parameter AUTO_PANEL=1,
    parameter LCD_RESET_CYCLES=20_000_000, LCD_READY_CYCLES=32_000_000,
    parameter H_SYNC=128, H_BACK=88, H_DISP=800, H_FRONT=40,
    parameter V_SYNC=2, V_BACK=33, V_DISP=480, V_FRONT=10
) (
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 clk100 CLK", X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET resetn, FREQ_HZ 100000000" *)
    input wire clk100,
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 resetn RST", X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *)
    input wire resetn,
    input wire pix_clk, pix_resetn,
    input wire [15:0] s_axi_awaddr,
    input wire s_axi_awvalid, output wire s_axi_awready,
    input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid, output wire s_axi_wready,
    output wire [1:0] s_axi_bresp, output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [15:0] s_axi_araddr, input wire s_axi_arvalid,
    output wire s_axi_arready, output reg [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp, output reg s_axi_rvalid,
    input wire s_axi_rready,
    output reg [2:0] panel_id, output reg panel_ready,
    output wire lcd_hs, lcd_vs, lcd_de, lcd_bl, lcd_rst, lcd_clk,
    inout wire [23:0] lcd_rgb
);
    wire [23:0] rgb_input;
    (* ASYNC_REG="TRUE" *) reg [2:0] id_meta, id_sync;
    reg [12:0] id_count;
    reg [25:0] lcd_init_count;
    wire lcd_init_ready=lcd_init_count>=LCD_READY_CYCLES;
    // Hold panel reset low for 200 ms, then allow 120 ms to settle.
    // Acquisition and the AXI interface operate independently during this time.
    always @(posedge clk100) begin
        if(!resetn)lcd_init_count<=0;
        else if(!lcd_init_ready)lcd_init_count<=lcd_init_count+1'b1;
    end
    wire known = panel_id==0 || panel_id==1 || panel_id==2 || panel_id==4 || panel_id==5;
    always @(posedge clk100) begin
        if (!resetn) begin
            id_count<=0; panel_ready<=0; panel_id<=0; id_meta<=0; id_sync<=0;
        end else begin
            id_meta <= {rgb_input[7],rgb_input[15],rgb_input[23]}; id_sync <= id_meta;
            if (!panel_ready) begin
                if (id_count==4095) begin panel_id<=id_sync; panel_ready<=1; end
                else id_count<=id_count+1'b1;
            end
        end
    end
    // CPU writes only the inactive page. Hardware also rejects front/pending
    // writes; this makes accidental software use unable to tear a visible page.
    (* ram_style="block" *) reg [6:0] chars [0:4095];
    (* ram_style="block" *) reg [7:0] trace0 [0:511];
    (* ram_style="block" *) reg [7:0] trace1 [0:511];
    (* ram_style="block" *) reg [7:0] spectrum [0:511];
    reg aw_hold,w_hold;
    reg [15:0] aw;
    reg [31:0] wd;
    reg [3:0] ws;
    reg front_cpu, req_page, req_toggle, enable_cpu, write_error;
    reg ack_pix, front_pix;
    (* ASYNC_REG="TRUE" *) reg req_page_meta,req_page_sync;
    reg req_settled;
    (* ASYNC_REG="TRUE" *) reg ack_meta,ack_sync;
    (* ASYNC_REG="TRUE" *) reg req_meta,req_sync;
    (* ASYNC_REG="TRUE" *) reg en_meta,en_sync;
    // The ID is stable before pixel reset release. Register it locally so the
    // profile decoder is driven entirely by the pixel domain.
    (* ASYNC_REG="TRUE" *) reg [2:0] panel_meta,panel_sync;
    always @(posedge pix_clk or negedge pix_resetn) begin
        if(!pix_resetn)begin panel_meta<=0;panel_sync<=0;end
        else begin panel_meta<=panel_id;panel_sync<=panel_meta;end
    end
    wire pending=req_toggle!=ack_sync;
    wire execute=aw_hold && w_hold && !s_axi_bvalid;
    wire [11:0] word_index=aw[13:2];
    assign s_axi_awready=!aw_hold && !s_axi_bvalid;
    assign s_axi_wready=!w_hold && !s_axi_bvalid;
    assign s_axi_arready=!s_axi_rvalid;
    assign s_axi_bresp=0;
    assign s_axi_rresp=0;
    always @(posedge clk100) begin
        if (!resetn) begin
            aw_hold<=0; w_hold<=0; s_axi_bvalid<=0; s_axi_rvalid<=0; s_axi_rdata<=0;
            front_cpu<=0; req_page<=0; req_toggle<=0; enable_cpu<=0; write_error<=0;
            ack_meta<=0; ack_sync<=0;
        end else begin
            ack_meta<=ack_pix; ack_sync<=ack_meta;
            if (!pending) front_cpu<=req_page;
            if (s_axi_awvalid && s_axi_awready) begin aw<=s_axi_awaddr;aw_hold<=1;end
            if (s_axi_wvalid && s_axi_wready) begin wd<=s_axi_wdata;ws<=s_axi_wstrb;w_hold<=1;end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            if (execute) begin
                aw_hold<=0;w_hold<=0;s_axi_bvalid<=1;
                if (aw==16'h8004 && ws[0] && wd[1]) begin
                    if (!pending) begin req_page<=wd[0];req_toggle<=~req_toggle;end
                    else write_error<=1;
                end
                if (aw==16'h8008 && ws[0]) begin
                    enable_cpu<=wd[0]; if (wd[1]) write_error<=0;
                end
                if (!aw[15] && ws[0]) begin
                    // Until enabled both pages may be initialized safely.
                    if (!pending && (!enable_cpu || aw[14]!=req_page)) begin
                        if (word_index<2048) chars[{aw[14],word_index[10:0]}]<=wd[6:0];
                        if (word_index>=2048 && word_index<2304) trace0[{aw[14],word_index[7:0]}]<=wd[7:0];
                        if (word_index>=2304 && word_index<2560) trace1[{aw[14],word_index[7:0]}]<=wd[7:0];
                        if (word_index>=2560 && word_index<2816) spectrum[{aw[14],word_index[7:0]}]<=wd[7:0];
                    end else write_error<=1;
                end
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid<=1;
                case(s_axi_araddr)
                    16'h8000:s_axi_rdata<={29'd0,write_error,pending, (pending?front_cpu:req_page)};
                    16'h8008:s_axi_rdata<={31'd0,enable_cpu};
                    16'h800c:s_axi_rdata<={21'd0,lcd_init_ready,panel_ready,known,5'd0,panel_id};
                    default:s_axi_rdata<=0;
                endcase
            end
        end
    end
    reg [11:0] ht,hstart,hw,vt,vstart,vh;
    always @* begin
        ht=H_SYNC+H_BACK+H_DISP+H_FRONT; hstart=H_SYNC+H_BACK; hw=H_DISP;
        vt=V_SYNC+V_BACK+V_DISP+V_FRONT; vstart=V_SYNC+V_BACK; vh=V_DISP;
        if (AUTO_PANEL) case(panel_sync)
            0:begin ht=525;hstart=43;hw=480;vt=286;vstart=12;vh=272;end
            // MD0700R-800480: manufacturer RGBLCD example, 32 MHz.
            // H=2/46/800/210, V=2/23/480/22; ID strap 001 -> 0x7084.
            1:begin ht=1058;hstart=48;hw=800;vt=527;vstart=25;vh=480;end
            4:begin ht=1056;hstart=216;hw=800;vt=525;vstart=35;vh=480;end
            2:begin ht=1344;hstart=160;hw=1024;vt=635;vstart=23;vh=600;end
            5:begin ht=1440;hstart=90;hw=1280;vt=823;vstart=13;vh=800;end
            default:begin end
        endcase
    end
    reg [11:0] hcount,vcount;
    wire frame_start=hcount==0 && vcount==0;
    wire active=hcount>=hstart && hcount<hstart+hw && vcount>=vstart && vcount<vstart+vh;
    wire [11:0] x=hcount-hstart, y=vcount-vstart;
    reg [11:0] ui_x,ui_y;
    always @* begin
        ui_x=x;ui_y=y;
        if(AUTO_PANEL)case(panel_sync)
            1,4:begin ui_x=x*2/3;ui_y=y*2/3;end
            2,5:begin ui_x=x>>1;ui_y=y>>1;end
            default:begin end
        endcase
    end
    wire right_half=x>=(hw>>1);
    wire [11:0] local_x=right_half?x-(hw>>1):x;
    reg [7:0] plot_index;
    always @* begin
        if (!AUTO_PANEL) plot_index=local_x*256/(H_DISP/2);
        else case(panel_sync)
            0:plot_index=local_x*256/240;
            1,4:plot_index=local_x*256/400;
            2:plot_index=local_x[8:1];
            5:plot_index=local_x*256/640;
            default:plot_index=0;
        endcase
    end
    reg [6:0] char_q;
    reg [7:0] t0_q,t1_q,sp_q;
    reg [11:0] x_q,y_q;
    reg de_q,right_q,divider_q;
    reg [23:0] colour;
    reg de_out;
    wire [7:0] font_row;
    tgg_lcd_font font(.ascii(char_q),.row(y_q[2:0]),.bits(font_row));
    // The RAM outputs and position/DE enter the same pipeline stage.
    always @(posedge pix_clk) begin
        char_q<=chars[{front_pix,ui_y[7:3],ui_x[8:3]}];
        t0_q<=trace0[{front_pix,plot_index}];
        t1_q<=trace1[{front_pix,plot_index}];
        sp_q<=spectrum[{front_pix,plot_index}];
        x_q<=ui_x;y_q<=ui_y;de_q<=active;right_q<=right_half;divider_q<=x==(hw>>1);
    end
    always @(posedge pix_clk or negedge pix_resetn) begin
        if (!pix_resetn) begin
            hcount<=0;vcount<=0;req_meta<=0;req_sync<=0;ack_pix<=0;
            req_page_meta<=0;req_page_sync<=0;req_settled<=0;
            front_pix<=0;en_meta<=0;en_sync<=0;colour<=0;de_out<=0;
        end else begin
            req_meta<=req_toggle;req_sync<=req_meta; en_meta<=enable_cpu;en_sync<=en_meta;
            req_page_meta<=req_page;req_page_sync<=req_page_meta;req_settled<=req_sync;
            // The page data gets one extra pixel cycle to settle before the
            // synchronized request can be consumed at a frame boundary.
            if (frame_start && req_settled!=ack_pix) begin
                front_pix<=req_page_sync;ack_pix<=req_settled;
            end
            if (hcount==ht-1) begin
                hcount<=0;
                if (vcount==vt-1) vcount<=0;else vcount<=vcount+1'b1;
            end else hcount<=hcount+1'b1;
            de_out<=de_q && en_sync;
            colour<=24'h081426;
            if (y_q<160 && x_q<512 && font_row[7-x_q[2:0]]) colour<=24'hf0f5ff;
            if (y_q>=160 && y_q<256) begin
                if (y_q==160 || y_q==255 || y_q==208 || x_q==0 || divider_q) colour<=24'h30445a;
                if (!right_q) begin
                    if (y_q-160==t1_q) colour<=24'hffdf40;
                    if (y_q-160==t0_q) colour<=24'h40ff80;
                end else if (y_q-160>=sp_q) colour<=24'h40dfff;
            end
        end
    end
    // ODDR forwards the pixel clock without routing a fabric net as a clock.
    // Data/DE change on the external falling edge, as in the manufacturer
    // MD0700R example, leaving half a cycle before the external rising edge.
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) pclk_out(.C(pix_clk),.CE(1'b1),
        .D1(1'b0),.D2(1'b1),.R(1'b0),.S(1'b0),.Q(lcd_clk));
    assign lcd_hs=1'b1;
    assign lcd_vs=1'b1;
    assign lcd_rst=resetn && lcd_init_count>=LCD_RESET_CYCLES;
    assign lcd_de=de_out && pix_resetn && panel_ready && known && lcd_init_ready;
    assign lcd_bl=enable_cpu && panel_ready && known && pix_resetn && lcd_init_ready;
    // Explicit IOBUFs preserve the input path in module-reference OOC
    // synthesis. A nested inferred tristate can otherwise become plain logic.
    genvar b;
    generate for(b=0;b<24;b=b+1)begin:rgb_io
        IOBUF #(.DRIVE(8),.SLEW("SLOW"),.IOSTANDARD("LVCMOS33")) io (
            .I(colour[b]),.T(!lcd_de),.O(rgb_input[b]),.IO(lcd_rgb[b]));
    end endgenerate
endmodule
