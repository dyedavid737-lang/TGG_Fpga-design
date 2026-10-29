# Effective Vivado 2025.2 PS7 DDR settings.
# Source this file to read the tgg_effective_ps7_ddr dict; no IP is modified.
# Tool-resolved defaults are not measured PCB trace delays.
set tgg_effective_ps7_ddr [dict create]
dict set tgg_effective_ps7_ddr CONFIG.PCW_APU_PERIPHERAL_FREQMHZ 666.666666
dict set tgg_effective_ps7_ddr CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ 33.333333
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_DDR_PLL_FREQMHZ 1066.667
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_HPRLPR_QUEUE_PARTITION HPR(0)/LPR(32)
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_HPR_TO_CRITICAL_PRIORITY_LEVEL 15
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_LPR_TO_CRITICAL_PRIORITY_LEVEL 2
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PERIPHERAL_CLKSRC {DDR PLL}
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PERIPHERAL_DIVISOR0 2
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PORT0_HPR_ENABLE 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PORT1_HPR_ENABLE 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PORT2_HPR_ENABLE 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PORT3_HPR_ENABLE 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PRIORITY_READPORT_0 <Select>
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PRIORITY_READPORT_1 <Select>
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PRIORITY_READPORT_2 <Select>
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PRIORITY_READPORT_3 <Select>
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PRIORITY_WRITEPORT_0 <Select>
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PRIORITY_WRITEPORT_1 <Select>
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PRIORITY_WRITEPORT_2 <Select>
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_PRIORITY_WRITEPORT_3 <Select>
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_RAM_BASEADDR 0x00100000
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_RAM_HIGHADDR 0x3FFFFFFF
dict set tgg_effective_ps7_ddr CONFIG.PCW_DDR_WRITE_TO_CRITICAL_PRIORITY_LEVEL 2
dict set tgg_effective_ps7_ddr CONFIG.PCW_EN_DDR 1
dict set tgg_effective_ps7_ddr CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY0 0.089
dict set tgg_effective_ps7_ddr CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY1 0.075
dict set tgg_effective_ps7_ddr CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY2 0.085
dict set tgg_effective_ps7_ddr CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY3 0.092
dict set tgg_effective_ps7_ddr CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_0 -0.025
dict set tgg_effective_ps7_ddr CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_1 0.014
dict set tgg_effective_ps7_ddr CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_2 -0.009
dict set tgg_effective_ps7_ddr CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_3 -0.033
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART0_BASEADDR 0xE0000000
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART0_BAUD_RATE 115200
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART0_GRP_FULL_ENABLE 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART0_GRP_FULL_IO <Select>
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART0_HIGHADDR 0xE0000FFF
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART0_PERIPHERAL_ENABLE 1
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15}
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART1_BASEADDR 0xE0001000
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART1_BAUD_RATE 115200
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART1_GRP_FULL_ENABLE 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART1_GRP_FULL_IO <Select>
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART1_HIGHADDR 0xE0001FFF
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART1_PERIPHERAL_ENABLE 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UART1_UART1_IO <Select>
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ 533.333374
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_ADV_ENABLE 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_AL 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_BANK_ADDR_COUNT 3
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_BL 8
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0 0.25
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1 0.25
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2 0.25
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3 0.25
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit}
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CL 7
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_0_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PACKAGE_LENGTH 80.4535
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_1_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PACKAGE_LENGTH 80.4535
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_2_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PACKAGE_LENGTH 80.4535
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_3_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PACKAGE_LENGTH 80.4535
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CLOCK_STOP_EN 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_COL_ADDR_COUNT 10
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_CWL 6
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DEVICE_CAPACITY {4096 MBits}
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_0_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_0_PACKAGE_LENGTH 105.056
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_0_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_1_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_1_PACKAGE_LENGTH 66.904
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_1_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_2_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_2_PACKAGE_LENGTH 89.1715
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_2_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_3_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_3_PACKAGE_LENGTH 113.63
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_3_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 0.0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 0.0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 0.0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 0.0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_0_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_0_PACKAGE_LENGTH 98.503
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_0_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_1_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_1_PACKAGE_LENGTH 68.5855
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_1_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_2_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_2_PACKAGE_LENGTH 90.295
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_2_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_3_LENGTH_MM 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_3_PACKAGE_LENGTH 103.977
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DQ_3_PROPOGATION_DELAY 160
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH {16 Bits}
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_ECC Disabled
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_ENABLE 1
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ 533.333333
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_HIGH_TEMP {Normal (0-85)}
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3 (Low Voltage)}
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125}
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_ROW_ADDR_COUNT 15
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_SPEED_BIN DDR3_1066F
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE 1
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE 1
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL 1
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_T_FAW 40.0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_T_RAS_MIN 35.0
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_T_RC 48.75
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_T_RCD 7
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_T_RP 7
dict set tgg_effective_ps7_ddr CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF 0
dict set tgg_effective_ps7_ddr CONFIG.PCW_USE_DDR_BYPASS 0
