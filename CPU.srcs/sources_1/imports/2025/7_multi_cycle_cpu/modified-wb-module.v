`timescale 1ns / 1ps
//*************************************************************************
//   > 文件名: wb.v
//   > 描述  :多周期CPU的写回模块，加入异常处理功能
//   > 作者  : LOONGSON (modified)
//   > 日期  : 2025-04-21
//*************************************************************************
module wb(                      // 写回级
    input         WB_valid,     // 写回级有效
    input  [75:0] MEM_WB_bus_r, // MEM->WB总线
    output        rf_wen,       // 寄存器写使能
    output [ 4:0] rf_wdest,     // 寄存器写地址
    output [31:0] rf_wdata,     // 寄存器写数据
    output        WB_over,      // WB模块执行完成

    // CP0寄存器访问接口
    output        cp0_wen,      // CP0寄存器写使能
    output [ 4:0] cp0_wnum,     // CP0寄存器写编号
    output [31:0] cp0_wdata,    // CP0寄存器写数据
    output [ 4:0] cp0_rnum,     // CP0寄存器读编号
    input  [31:0] cp0_rdata,    // CP0寄存器读数据

    //展示PC
    output [ 31:0] WB_pc
);

//-----{MEM->WB总线}begin
    // MEM_WB_bus = {dm_addr, rf_wen, rf_wdest, mem_result, pc, mem_exc_code, mem_exc_detect};
    wire [31:0] dm_addr;
    wire        wen;
    wire [ 4:0] wdest;
    wire [31:0] mem_result;
    wire [31:0] pc;
    wire [ 4:0] exc_code_in;   // 访存级异常码
    wire        mem_exc_detect; // 访存级异常检测信号
    
    assign {dm_addr, wen, wdest, mem_result, pc, exc_code_in, mem_exc_detect} = MEM_WB_bus_r;
//-----{MEM->WB总线}end

//-----{WB执行完成}begin
    //WB模块只是传递寄存器堆的写使能/写地址和写数据
    //可在一拍内完成
    //故WB_valid即是WB_over信号
    assign WB_over = WB_valid;
//-----{WB执行完成}end

//-----{WB->regfile信号}begin
    // 如果检测到异常，不进行寄存器写回
    assign rf_wen   = wen & WB_valid & ~mem_exc_detect;
    assign rf_wdest = wdest;
    assign rf_wdata = mem_result;
//-----{WB->regfile信号}end

//-----{CP0寄存器访问}begin
    // 指令格式判断
    wire inst_mtc0;  // MTC0指令标识
    wire inst_mfc0;  // MFC0指令标识
    
    // 解析特殊指令 - 这里需要根据您的具体指令格式来实现
    // 假设wdest字段在MTC0/MFC0指令中用于指示CP0寄存器编号
    // 且mem_result高8位用于指示指令类型
    
    assign inst_mtc0 = (mem_result[31:24] == 8'h40) & WB_valid;
    assign inst_mfc0 = (mem_result[31:24] == 8'h41) & WB_valid;
    
    // CP0写使能和地址
    assign cp0_wen   = inst_mtc0 & ~mem_exc_detect;
    assign cp0_wnum  = (inst_mtc0) ? wdest : 5'd0;
    assign cp0_wdata = (inst_mtc0) ? mem_result : 32'd0;
    
    // CP0读地址
    assign cp0_rnum  = (inst_mfc0) ? wdest : 5'd0;
    
    // 对于MFC0指令，需要将CP0寄存器的值读出
    // 注意：这个值会在下一周期通过cp0_rdata返回
    // 如果需要马上使用，需要在这里处理
//-----{CP0寄存器访问}end

//-----{展示WB模块的PC值}begin
    assign WB_pc = pc;
//-----{展示WB模块的PC值}end
endmodule