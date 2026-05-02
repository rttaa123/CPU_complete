`timescale 1ns / 1ps
//*************************************************************************
//   > 文件名: fetch.v
//   > 描述  :多周期CPU的取指模块，增加异常处理功能，适配Bus4LZU
//   > 作者  : 饶甜甜 (修改日期: 2025-04-24)
//*************************************************************************
`define STARTADDR 32'd0             // 程序起始地址为0
module fetch(                       // 取指级
    input             clk,          // 时钟
    input             resetn,       // 复位信号，低电平有效
    input             IF_valid,     // 取指级有效信号
    input             next_fetch,   // 取下一条指令，用来锁存PC值
    input      [31:0] inst,         // 从Bus4LZU取出的指令
    input      [32:0] jbr_bus,      // 跳转总线
    input      [70:0] exc_bus,      // 异常总线输入

    // 异常检测输出
    output reg        if_exc_detect, // 取指阶段异常检测
    output reg  [4:0] if_exc_code,      // 异常编码

    output     [31:0] inst_addr,    // 发往Bus4LZU的取指地址
    output reg        IF_over,      // IF模块执行完成
    output     [69:0] IF_ID_bus,    // IF->ID总线，增加异常信息
    
    //展示PC和取出的指令
    output     [31:0] IF_pc,
    output     [31:0] IF_inst
);

//-----{程序计数器PC}begin
    wire [31:0] next_pc;
    wire [31:0] seq_pc;
    reg  [31:0] pc;
    //跳转pc
    wire        jbr_taken;
    wire [31:0] jbr_target;
    assign {jbr_taken, jbr_target} = jbr_bus; //跳转总线
    
    // 异常处理相关信号
    wire        exc_valid;          // 异常总线有效
    wire [31:0] exc_handler_addr;   // 异常处理程序入口地址
    wire [31:0] exc_return_addr;    // 异常返回地址
    wire        is_eret;            // 是否是异常返回指令
    wire [4:0]  exc_type;           // 异常类型
    
    // 解析异常总线
    assign {exc_return_addr, exc_handler_addr, is_eret, exc_type, exc_valid} = exc_bus;
    
    assign seq_pc = pc + 32'h4;  

    // 新指令：若指令跳转，为跳转地址；若异常有效，为异常处理地址；若异常返回，为返回地址；否则为下一指令
    assign next_pc = is_eret       ? exc_return_addr : 
                     exc_valid      ? exc_handler_addr :
                     jbr_taken      ? jbr_target : 
                     seq_pc; 
    // assign next_pc = jbr_taken      ? jbr_target : 
    //                  seq_pc; 
    
    
    always @(posedge clk)    // PC程序计数器
    begin
        if (!resetn)
        begin
            pc <= `STARTADDR; // 复位，取程序起始地址
        end
        else if (next_fetch)
        begin
            pc <= next_pc;    // 不复位，取新指令
        end
    end
//-----{程序计数器PC}end

//-----{异常检测}begin
    // 地址异常检测（指令地址错误）
    always @(posedge clk)
    begin
        if (!resetn)
        begin
            if_exc_detect <= 1'b0;
            if_exc_code <= 5'h00;
        end
        else if (IF_valid)
        begin
            // 检测指令地址是否对齐（MIPS要求指令地址4字节对齐）
            if (pc[1:0] != 2'b00)
            begin
                if_exc_detect <= 1'b1;
                if_exc_code <= 5'h04;  // 加载地址错误异常(AdEL)
            end
            // 检测指令地址是否越界（此处简化，可根据需要自定义地址范围）
            else if (pc > 32'h7FFFFFFF) // 假设有效地址范围为0x00000000-0x7FFFFFFF
            begin
                if_exc_detect <= 1'b1;
                if_exc_code <= 5'h04;  // 加载地址错误异常(AdEL)
            end
            else
            begin
                if_exc_detect <= 1'b0;
                if_exc_code <= 5'h00;
            end
        end
        else
        begin
            if_exc_detect <= 1'b0;
            if_exc_code <= 5'h00;
        end
    end
//-----{异常检测}end


assign inst_addr = pc >> 2;
// //-----{发往Bus4LZU的取指地址}begin
//     // 修改: 直接发送完整的PC值给Bus4LZU，不再需要右移
//     assign inst_addr = pc;
// //-----{发往Bus4LZU的取指地址}end

//-----{IF执行完成}begin
    // Bus4LZU模块也是同步读取，保持原有逻辑
    always @(posedge clk)
    begin
        IF_over <= IF_valid;
    end
//-----{IF执行完成}end

//-----{IF->ID总线}begin
    // 修改IF_ID_bus结构，增加异常信息 [69:0]
    // [69:38] - PC值
    // [37:6]  - 指令
    // [5:1]   - 异常码
    // [0]     - 异常有效位
    assign IF_ID_bus = {pc, inst, if_exc_code, if_exc_detect};
//-----{IF->ID总线}end

//-----{展示IF模块的PC值和指令}begin
    assign IF_pc   = pc;
    assign IF_inst = inst;
//-----{展示IF模块的PC值和指令}end
endmodule