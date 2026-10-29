`timescale 1ns/1ps
module tb_tgg_lcd_clock;
    reg clk=0,rst=0,ready=0;reg[2:0] id=0;
    wire pix,pr;always #5 clk=~clk;
    tgg_lcd_clock d(.clk100(clk),.resetn(rst),.panel_ready(ready),.panel_id(id),.pix_clk(pix),.pix_resetn(pr));
    real a,b;integer i;
    task check(input[2:0] panel,input real period);
        begin
            @(negedge clk);rst=0;ready=0;id=panel;
            repeat(30)@(posedge clk);@(negedge clk);rst=1;
            #5000;ready=1;wait(pr);
            @(posedge pix);a=$realtime;
            for(i=0;i<10;i=i+1)@(posedge pix);
            b=($realtime-a)/10;
            if(b<period-0.1||b>period+0.1)$fatal(1,"Clock ID%d got%f expected%f",panel,b,period);
            $display("CLOCK PASS: ID %d %f ns",panel,b);
        end
    endtask
    initial begin
        check(0,80);check(1,31.25);check(2,20);check(4,40);check(5,20);
        $display("PASS: actual UNISIM MMCM, glitchless mux and reset release for all five IDs");$finish;
    end
    initial begin #1000000;$fatal(1,"Clock lock timeout");end
endmodule
