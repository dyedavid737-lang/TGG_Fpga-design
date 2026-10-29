`timescale 1ns/1ps
module tb_tgg_lcd_axi;
    reg clk=0,pix=0,rst=0;
    always #5 clk=~clk;
    always #10 pix=~pix;
    reg [15:0] aw=0,ar=0;
    reg av=0,wv=0,br=0,rv=0,rr=0;
    reg [31:0] wd=0;reg [3:0] ws=0;
    wire awr,wr,bv,arr,rvalid;
    wire [31:0] rd;wire [1:0] bp,rp;
    wire [23:0] rgb;wire hs,vs,de,bl,lr,lc;
    wire [2:0] id;wire ready;
    // ID100: B7 high, G7/R7 low. Weak pull resistors are overridden by pixels.
    pullup(rgb[7]);pulldown(rgb[15]);pulldown(rgb[23]);
    tgg_lcd_axi #(.AUTO_PANEL(0),.LCD_RESET_CYCLES(32),.LCD_READY_CYCLES(64),.H_SYNC(2),.H_BACK(2),.H_DISP(64),.H_FRONT(2),
        .V_SYNC(2),.V_BACK(2),.V_DISP(272),.V_FRONT(2)) d (
        .clk100(clk),.resetn(rst),.pix_clk(pix),.pix_resetn(rst),
        .s_axi_awaddr(aw),.s_axi_awvalid(av),.s_axi_awready(awr),
        .s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wr),
        .s_axi_bresp(bp),.s_axi_bvalid(bv),.s_axi_bready(br),
        .s_axi_araddr(ar),.s_axi_arvalid(rv),.s_axi_arready(arr),
        .s_axi_rdata(rd),.s_axi_rresp(rp),.s_axi_rvalid(rvalid),.s_axi_rready(rr),
        .panel_id(id),.panel_ready(ready),.lcd_hs(hs),.lcd_vs(vs),.lcd_de(de),
        .lcd_bl(bl),.lcd_rst(lr),.lcd_clk(lc),.lcd_rgb(rgb));
    task send_aw(input [15:0] a);
        begin @(negedge clk);aw=a;av=1;@(posedge clk);while(!awr)@(posedge clk);@(negedge clk);av=0;end
    endtask
    task send_w(input [31:0] v,input[3:0] mask);
        begin @(negedge clk);wd=v;ws=mask;wv=1;@(posedge clk);while(!wr)@(posedge clk);@(negedge clk);wv=0;end
    endtask
    task write(input [15:0] a,input [31:0] v,input [3:0] mask,input integer w_first);
        begin
            if(w_first!=0)begin send_w(v,mask);repeat(3)@(posedge clk);send_aw(a);end
            else begin send_aw(a);repeat(2)@(posedge clk);send_w(v,mask);end
            wait(bv);repeat(3)begin @(posedge clk);#1;if(!bv)$fatal(1,"B response lost under backpressure");end
            @(negedge clk);br=1;@(negedge clk);br=0;
        end
    endtask
    task read(input [15:0] a,output [31:0] v);
        begin
            @(negedge clk);ar=a;rv=1;@(posedge clk);while(!arr)@(posedge clk);
            @(negedge clk);rv=0;wait(rvalid);v=rd;
            repeat(3)begin @(posedge clk);#1;if(!rvalid||rd!==v)$fatal(1,"R data not held");end
            @(negedge clk);rr=1;@(negedge clk);rr=0;
        end
    endtask
    reg last_front;integer px=0,frames=0;reg [11:0] oldh,oldv;reg started=0;
    always @(posedge pix) begin
        oldh=d.hcount;oldv=d.vcount;
        #1;
        if(!rst) last_front=0;
        else begin
            if(d.front_pix!=last_front && !(oldh==0&&oldv==0))$fatal(1,"Page changed inside frame");
            last_front=d.front_pix;
            if(de)begin
                if((^rgb)===1'bx)$fatal(1,"Unknown visible pixel");
                px=px+1;
            end
            if(oldh==0&&oldv==0 && bl)begin
                if(started && px!=64*272)$fatal(1,"DE pixel count %d",px);
                started=1;px=0;frames=frames+1;
            end
        end
    end
    reg [31:0] val;integer i;
    initial begin
        #100;@(negedge clk);rst=1;
        wait(ready);read(16'h800c,val);
        if(val[9:8]!=3 || val[2:0]!=4)$fatal(1,"Incorrect ID readback %h",val);
        // Initialize exactly what the visible small frame reads.
        for(i=0;i<2048;i=i+1)begin
            write(i*4,32'd32,1,i%2);
            write(16'h4000+i*4,32'd32,1,i%2);
        end
        for(i=2048;i<2816;i=i+1)begin
            write(i*4,48,1,0);write(16'h4000+i*4,48,1,1);
        end
        write(16'h4000,65,1,1);
        write(16'h4000,66,2,0);
        if(d.chars[2048]!==65)$fatal(1,"WSTRB ignored");
        write(16'h8004,3,0,0);read(16'h8000,val);
        if(val[1])$fatal(1,"Masked commit applied");
        write(16'h8004,3,1,1);read(16'h8000,val);
        if(!val[1])$fatal(1,"Commit not pending");
        write(16'h8004,2,1,0);read(16'h8000,val);
        if(!val[2])$fatal(1,"Busy commit not flagged");
        wait(!d.pending);read(16'h8000,val);
        if(!val[0])$fatal(1,"Front page ack failed");
        write(16'h8008,3,1,0); // clear error and enable
        write(16'h4000,67,1,0);
        if(d.chars[2048]!==65)$fatal(1,"Front page modified");
        read(16'h8000,val);if(!val[2])$fatal(1,"Front write not flagged");
        wait(frames>=3);
        write(16'h8004,2,1,1);wait(!d.pending);
        read(16'h8000,val);if(val[0])$fatal(1,"Second page commit failed");
        $display("PASS: LCD AXI AW/W order, WSTRB, response backpressure, ID, frame-boundary CDC, protected front page and DE counts");
        $finish;
    end
    initial begin #20000000;$fatal(1,"LCD test timeout");end
endmodule
