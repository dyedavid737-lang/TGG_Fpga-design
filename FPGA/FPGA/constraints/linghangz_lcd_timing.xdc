# The panel ID is sampled once per reset. Exactly one MMCM output is selected
# while the pixel domain is held in reset; pixel data cannot transfer between
# the alternative clock modes during operation.
set_clock_groups -logically_exclusive -group [get_clocks c12] -group [get_clocks c25] -group [get_clocks c32] -group [get_clocks c50]
# RGB input is only an asynchronous, static panel-ID strap at startup. Only
# the first stage of its synchronizer is excluded; internal CDC stages and all
# pixel/data paths keep their timing checks. No blanket clock false paths.
set_false_path -from [get_ports {lcd_rgb[*]}] -to [get_pins -hier -filter {NAME =~ */id_meta_reg*/D}]
# Asynchronous input to ONLY the first register of each synchronizer. The
# following register, request guard cycle, RAM data and all functional paths
# retain setup/hold analysis. 100 MHz and 32 MHz have 1.25 ns near-coincident
# edges: the first stage deliberately permits that event and contains it.
set_false_path -to [get_pins -hier -filter {NAME =~ */tgg_lcd_0/inst/ack_meta_reg/D || NAME =~ */tgg_lcd_0/inst/req_meta_reg/D || NAME =~ */tgg_lcd_0/inst/en_meta_reg/D || NAME =~ */tgg_lcd_0/inst/panel_meta_reg*/D || NAME =~ */tgg_lcd_0/inst/req_page_meta_reg/D}]
# Mux selects are latched once, before the pixel-domain reset is released.
# BUFGMUX handles switching; no running raster changes its clock selection.
set_false_path -from [get_cells -hier -filter {NAME =~ */panel_id_reg*}] -to [get_pins -hier -filter {NAME =~ */lcd_clock_0/inst/mux*/CE* || NAME =~ */lcd_clock_0/inst/mux*/S*}]
# Async assertion / three-clock synchronous deassertion reset bridge. Exclude
# recovery only on this bridge's async clear pins, not on the pixel consumers.
set_false_path -to [get_pins -hier -filter {NAME =~ */lcd_clock_0/inst/pr_reg*/CLR}]
