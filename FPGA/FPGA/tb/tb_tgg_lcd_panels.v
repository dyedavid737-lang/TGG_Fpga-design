`timescale 1ns/1ps
// End-to-end synthetic display page produced by the real C analysis/display
// code; checks all five ID/timing profiles and writes one RTL-rendered frame.
module tb_tgg_lcd_panels;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [2:0] strap=4;
    wire [23:0] rgb;
    assign (weak1,weak0) rgb[7]=strap[2];
    assign (weak1,weak0) rgb[15]=strap[1];
    assign (weak1,weak0) rgb[23]=strap[0];
    wire [2:0] id;wire ready,pr,de;
    // Long raster tests use ideal pixel clocks. The separate clock test checks
    // the actual UNISIM MMCM/mux; simulating its 1 GHz VCO for every raster
    // frame needlessly dominates runtime.
    reg pix=0;
    always begin
        if(strap==0) #40 pix=~pix;
        else if(strap==1) #15.625 pix=~pix;
        else if(strap==4) #20 pix=~pix;
        else #10 pix=~pix;
    end
    assign pr=rst&&ready;
    tgg_lcd_axi #(.LCD_RESET_CYCLES(32),.LCD_READY_CYCLES(64)) d(.clk100(clk),.resetn(rst),.pix_clk(pix),.pix_resetn(pr),
        .s_axi_awaddr(16'd0),.s_axi_awvalid(1'b0),.s_axi_awready(),
        .s_axi_wdata(32'd0),.s_axi_wstrb(4'd0),.s_axi_wvalid(1'b0),.s_axi_wready(),
        .s_axi_bresp(),.s_axi_bvalid(),.s_axi_bready(1'b1),
        .s_axi_araddr(16'd0),.s_axi_arvalid(1'b0),.s_axi_arready(),
        .s_axi_rdata(),.s_axi_rresp(),.s_axi_rvalid(),.s_axi_rready(1'b1),
        .panel_id(id),.panel_ready(ready),.lcd_hs(),.lcd_vs(),.lcd_de(de),
        .lcd_bl(),.lcd_rst(),.lcd_clk(),.lcd_rgb(rgb));
    reg [7:0] data[0:2815];
    integer i,fd,npix,lines,expectedw,expectedh,n;
    real t1,t2,period;
    reg [11:0] oldh,oldv;
    task panel(input [2:0] code,input integer w,input integer h,input real expected_period,input integer capture);
        begin
            @(negedge clk);rst=0;strap=code;
            repeat(30)@(posedge clk);
            @(negedge clk);rst=1;
            wait(ready);if(id!==code)$fatal(1,"ID %d != %d",id,code);
            wait(pr);
            @(posedge pix);t1=$realtime;@(posedge pix);t2=$realtime;period=t2-t1;
            if(period<expected_period-0.1||period>expected_period+0.1)$fatal(1,"Pixel period %f",period);
            force d.enable_cpu=1'b1;
            wait(d.hcount==0 && d.vcount==0);@(negedge pix);
            npix=0;lines=0;
            if(capture)begin fd=$fopen("screen_800x480.ppm","w");$fdisplay(fd,"P3\n800 480\n255");end
            begin : one_frame
                forever begin
                    @(posedge pix);oldh=d.hcount;oldv=d.vcount;#1;
                    if(oldh==0&&oldv==0)begin
                        if(npix>0)disable one_frame;
                    end
                    if(de)begin
                        if((^rgb)===1'bx)$fatal(1,"Unknown RGB on panel %d",code);
                        npix=npix+1;
                        if(capture)$fdisplay(fd,"%d %d %d",rgb[23:16],rgb[15:8],rgb[7:0]);
                    end
                end
            end
            if(capture)$fclose(fd);
            if(npix!=w*h)$fatal(1,"ID %d visible count %d expected %d",code,npix,w*h);
            $display("PANEL PASS: ID=%d %dx%d pixel_period=%f ns pixels=%d",code,w,h,period,npix);
            release d.enable_cpu;
        end
    endtask
    initial begin
        $readmemh("../host/display_page.hex",data);
        for(i=0;i<2048;i=i+1)begin d.chars[i]=data[i][6:0];d.chars[2048+i]=data[i][6:0];end
        for(i=0;i<256;i=i+1)begin
            d.trace0[i]=data[2048+i];d.trace0[256+i]=data[2048+i];
            d.trace1[i]=data[2304+i];d.trace1[256+i]=data[2304+i];
            d.spectrum[i]=data[2560+i];d.spectrum[256+i]=data[2560+i];
        end
        panel(1,800,480,31.25,1);
        panel(0,480,272,80.0,0);
        panel(4,800,480,40.0,0);
        panel(2,1024,600,20.0,0);
        panel(5,1280,800,20.0,0);
        // Reserved strap: ID latches but the hardware must suppress DE/BL.
        @(negedge clk);rst=0;strap=3;repeat(30)@(posedge clk);@(negedge clk);rst=1;
        wait(ready);wait(pr);force d.enable_cpu=1'b1;
        repeat(1500)begin @(posedge pix);#1;if(de||d.lcd_bl)$fatal(1,"Unknown panel enabled");end
        $display("PASS: all five panel IDs, raster timing profiles, full-frame DE counts, unknown-ID blanking, RTL screen capture");
        $finish;
    end
    initial begin #400000000;$fatal(1,"Panel test timeout");end
endmodule
