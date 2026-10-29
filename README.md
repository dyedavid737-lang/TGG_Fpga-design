# TGG FPGA final DDR project

最终 Vivado 工程：[`FPGA/FPGA/project_lcd_7020_ddr/tgg_lcd_7020.xpr`](FPGA/FPGA/project_lcd_7020_ddr/tgg_lcd_7020.xpr)。

适用硬件为正点原子领航者 Zynq-7020（`xc7z020clg400-2`）和
ATK-MD0700R-800480 显示屏。工具版本为 Vivado 2025.2、Vitis 2025.2 Embedded。
该最终版已完成上板与实际 TGG 测量验证。

## 工程结构

```text
FPGA/FPGA/
  project_lcd_7020_ddr/   最终 Vivado 工程与现有硬件输出
  rtl/                   工程引用的 RTL
  constraints/           板级引脚和显示时序约束
  sw/                    ARM 采集、分析、显示与 DDR 自检源码
  scripts/               创建、重建、软件编译和 JTAG 调试脚本
  tb/                    功能测试平台
  tgg_final2.py          CSV 离线分析参考
display_20261024/ddr/delivery/
  tgg_design_wrapper.bit
  tgg_lcd_7020.xsa
  ps7_init.tcl
  ddr_memory_test.elf
  tgg_display_ddr.elf
```

`project_lcd_7020_ddr` 的 XPR 引用同级 `rtl` 与 `constraints`，因此请克隆整个仓库并保留目录关系。
缓存、`.Xil`、Python 字节码、Vivado GUI 会话日志和嵌套 Git 元数据未纳入上传；

## 打开与运行

1. 将整个仓库克隆到短英文路径，例如 `D:/TGG_Fpga-design`。
2. 使用 Vivado 2025.2 打开上述 XPR；修改后可使用
   `FPGA/FPGA/scripts/rebuild_lcd_ddr_project.tcl` 重新构建。
3. 上板前连接电源、JTAG、板上 PS 串口及显示屏，选择 JTAG 启动模式。
   P5 跳帽连接 1–3、2–4。板上“UART1”接口实际连接 **PS UART0**，MIO14 RX、MIO15 TX，115200 8N1。
4. 在已启动本机 hw_server、且打开对应串口的情况下执行以下命令；均从仓库根目录运行。

```powershell
xsdb FPGA/FPGA/scripts/ddr_debug.tcl -check -mode memtest
xsdb FPGA/FPGA/scripts/ddr_debug.tcl -check -mode app
xsdb FPGA/FPGA/scripts/ddr_debug.tcl -run -mode memtest
# 仅在本轮串口实收 DDR PASS 后启动主应用
xsdb FPGA/FPGA/scripts/ddr_debug.tcl -run -mode app
```

下载会复位开发板并写入易失内存。内存测试覆盖保留的 16 MiB DDR 区域。
BIT、XSA、PS 初始化和 ELF 应成组使用；JTAG 运行在断电后需要重新加载。

## 设计概览

- PL：100 MHz，XADC 10 kS/s，4096 点双 bank 采集和 AXI 接口。
- ARM：电压到角度主值反演、FFT、谱峰插值和正弦拟合，应用运行于 DDR。
- LCD：800×480 RGB888，32 MHz 像素时钟，显示参数、波形、拟合曲线、频谱与状态。
- 当前直接输出角度域参数和频率；绝对磁场量值需结合光路、晶体及实验标定参数解释。

