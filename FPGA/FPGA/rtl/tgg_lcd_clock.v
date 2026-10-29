`timescale 1ns/1ps
// 100 MHz PS FCLK -> 32 MHz for the user's ATK-MD0700R-800480,
// plus the legacy board-manual clock profiles for other panel IDs.
// ID is latched once while the colour bus is high impedance. The clock muxes
// settle before the pixel reset synchronizer is released.
module tgg_lcd_clock (
    input wire clk100, resetn, panel_ready,
    input wire [2:0] panel_id,
    output wire pix_clk,
    output wire pix_resetn
);
    wire fb, fb_buf, c50, c25, c12, c32, c_mid, c_legacy, locked;
    MMCME2_BASE #(.CLKIN1_PERIOD(10.0), .CLKFBOUT_MULT_F(8.0),
        .DIVCLK_DIVIDE(1), .CLKOUT0_DIVIDE_F(25.0),
        .CLKOUT1_DIVIDE(16), .CLKOUT2_DIVIDE(32), .CLKOUT3_DIVIDE(64)) mmcm (
        .CLKIN1(clk100), .RST(!resetn), .PWRDWN(1'b0),
        .CLKFBOUT(fb), .CLKFBIN(fb_buf), .LOCKED(locked),
        .CLKOUT0(c32), .CLKOUT1(c50), .CLKOUT2(c25), .CLKOUT3(c12),
        .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2B(),
        .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB());
    BUFG feedback (.I(fb), .O(fb_buf));
    wire use25 = panel_id == 3'b100;
    BUFGMUX mux1 (.I0(c50), .I1(c25), .S(use25), .O(c_mid));
    BUFGMUX mux2 (.I0(c_mid), .I1(c12), .S(panel_id == 3'b000), .O(c_legacy));
    BUFGMUX mux3 (.I0(c_legacy), .I1(c32), .S(panel_id == 3'b001), .O(pix_clk));
    reg [4:0] settle;
    always @(posedge clk100) begin
        if (!resetn || !locked || !panel_ready) settle <= 0;
        else if (!settle[4]) settle <= settle + 1'b1;
    end
    wire release_reset = resetn && locked && panel_ready && settle[4];
    (* ASYNC_REG = "TRUE" *) reg [2:0] pr;
    always @(posedge pix_clk or negedge release_reset) begin
        if (!release_reset) pr <= 0;
        else pr <= {pr[1:0], 1'b1};
    end
    assign pix_resetn = pr[2];
endmodule
