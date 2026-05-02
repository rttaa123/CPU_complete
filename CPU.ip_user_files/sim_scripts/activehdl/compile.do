transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib activehdl/xpm
vlib activehdl/blk_mem_gen_v8_4_8
vlib activehdl/xil_defaultlib

vmap xpm activehdl/xpm
vmap blk_mem_gen_v8_4_8 activehdl/blk_mem_gen_v8_4_8
vmap xil_defaultlib activehdl/xil_defaultlib

vlog -work xpm  -sv2k12 "+incdir+../../../project_130316.gen/sources_1/ip/bus4LZU_0/sources_1/new/header" -l xpm -l blk_mem_gen_v8_4_8 -l xil_defaultlib \
"D:/app/Xilinx/Vivado/2024.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93  \
"D:/app/Xilinx/Vivado/2024.1/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work blk_mem_gen_v8_4_8  -v2k5 "+incdir+../../../project_130316.gen/sources_1/ip/bus4LZU_0/sources_1/new/header" -l xpm -l blk_mem_gen_v8_4_8 -l xil_defaultlib \
"../../ipstatic/simulation/blk_mem_gen_v8_4.v" \

vlog -work xil_defaultlib  -v2k5 "+incdir+../../../project_130316.gen/sources_1/ip/bus4LZU_0/sources_1/new/header" -l xpm -l blk_mem_gen_v8_4_8 -l xil_defaultlib \
"../../../project_130316.gen/sources_1/ip/data_ram/sim/data_ram.v" \
"../../../project_130316.gen/sources_1/ip/inst_rom_1/sim/inst_rom.v" \
"../../../project_130316.srcs/sources_1/imports/2025/7_multi_cycle_cpu/adder.v" \
"../../../project_130316.srcs/sources_1/imports/2025/7_multi_cycle_cpu/exception-module.v" \
"../../../project_130316.srcs/sources_1/imports/2025/7_multi_cycle_cpu/mips-multicycle-cpu-with-exceptions.v" \
"../../../project_130316.srcs/sources_1/imports/2025/7_multi_cycle_cpu/modified-alu-module.v" \
"../../../project_130316.srcs/sources_1/imports/2025/7_multi_cycle_cpu/modified-decode-module.v" \
"../../../project_130316.srcs/sources_1/imports/2025/7_multi_cycle_cpu/modified-exe-module.v" \
"../../../project_130316.srcs/sources_1/imports/2025/7_multi_cycle_cpu/modified-fetch-module.v" \
"../../../project_130316.srcs/sources_1/imports/2025/7_multi_cycle_cpu/modified-mem-module.v" \
"../../../project_130316.srcs/sources_1/imports/2025/7_multi_cycle_cpu/modified-wb-module.v" \
"../../../project_130316.srcs/sources_1/imports/2025/7_multi_cycle_cpu/regfile.v" \
"../../../project_130316.srcs/sim_1/imports/7_multi_cycle_cpu/tb.v" \

vlog -work xil_defaultlib \
"glbl.v"

