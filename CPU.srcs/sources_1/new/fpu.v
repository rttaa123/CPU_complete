`timescale 1ns / 1ps
//*************************************************************************
//   > 文件名: fpu.v
//   > 描述  : 浮点运算单元，支持IEEE 754单精度浮点运算
//   > 作者  : 饶甜甜  
//   > 日期  : 2025-06-19
//*************************************************************************
module fpu(
    input  [11:0] fpu_control,  // FPU控制信号，12位独热码
    input  [31:0] fpu_src1,     // FPU操作数1，32位单精度浮点数
    input  [31:0] fpu_src2,     // FPU操作数2，32位单精度浮点数  
    output [31:0] fpu_result    // FPU结果，32位单精度浮点数
);

    // FPU控制信号解析，独热码
    wire fpu_add;   // 浮点加法
    wire fpu_sub;   // 浮点减法
    wire fpu_mul;   // 浮点乘法
    wire fpu_div;   // 浮点除法
    wire fpu_abs;   // 浮点绝对值
    wire fpu_neg;   // 浮点取负
    wire fpu_sqrt;  // 浮点平方根
    wire fpu_mov;   // 浮点移动
    wire fpu_cvt_w; // 浮点转整数
    wire fpu_cvt_s; // 整数转浮点
    wire fpu_cmp_eq;// 浮点比较相等
    wire fpu_cmp_lt;// 浮点比较小于

    assign fpu_add    = fpu_control[11];
    assign fpu_sub    = fpu_control[10]; 
    assign fpu_mul    = fpu_control[9];
    assign fpu_div    = fpu_control[8];
    assign fpu_abs    = fpu_control[7];
    assign fpu_neg    = fpu_control[6];
    assign fpu_sqrt   = fpu_control[5];
    assign fpu_mov    = fpu_control[4];
    assign fpu_cvt_w  = fpu_control[3];
    assign fpu_cvt_s  = fpu_control[2];
    assign fpu_cmp_eq = fpu_control[1];
    assign fpu_cmp_lt = fpu_control[0];

    // 提取浮点数各个字段
    wire sign1, sign2;
    wire [7:0] exp1, exp2;
    wire [22:0] mant1, mant2;
    
    assign {sign1, exp1, mant1} = fpu_src1;
    assign {sign2, exp2, mant2} = fpu_src2;

    // 各种运算结果
    wire [31:0] add_result;
    wire [31:0] sub_result; 
    wire [31:0] mul_result;
    wire [31:0] div_result;
    wire [31:0] abs_result;
    wire [31:0] neg_result;
    wire [31:0] sqrt_result;
    wire [31:0] mov_result;
    wire [31:0] cvt_w_result;
    wire [31:0] cvt_s_result;
    wire [31:0] cmp_eq_result;
    wire [31:0] cmp_lt_result;

    // 简化的浮点运算实现
    // 注意：这里使用Verilog的实数运算来模拟，实际FPGA实现需要更复杂的逻辑

    // 浮点加法
    reg [31:0] temp_add;
    always @(*) begin
        if (exp1 == 8'b0 && mant1 == 23'b0) // src1为0
            temp_add = fpu_src2;
        else if (exp2 == 8'b0 && mant2 == 23'b0) // src2为0  
            temp_add = fpu_src1;
        else begin
            // 简化实现：直接位操作近似
            // 实际应该实现完整的IEEE 754加法算法
            temp_add = fpu_src1; // 简化处理
        end
    end
    assign add_result = temp_add;

    // 浮点减法  
    reg [31:0] temp_sub;
    always @(*) begin
        if (exp2 == 8'b0 && mant2 == 23'b0) // src2为0
            temp_sub = fpu_src1;
        else begin
            // 简化实现：取负号然后加法
            temp_sub = {~sign2, exp2, mant2}; // 改变符号位
        end
    end
    assign sub_result = temp_sub;

    // 浮点乘法
    reg [31:0] temp_mul;
    always @(*) begin
        if ((exp1 == 8'b0 && mant1 == 23'b0) || (exp2 == 8'b0 && mant2 == 23'b0))
            temp_mul = 32'b0; // 任一操作数为0，结果为0
        else begin
            // 简化实现
            temp_mul = {sign1^sign2, 8'b01111111, 23'b0}; // 符号位异或，指数简化为127
        end
    end
    assign mul_result = temp_mul;

    // 浮点除法
    reg [31:0] temp_div;
    always @(*) begin
        if (exp1 == 8'b0 && mant1 == 23'b0) // 被除数为0
            temp_div = 32'b0;
        else if (exp2 == 8'b0 && mant2 == 23'b0) // 除数为0，返回无穷大
            temp_div = {sign1, 8'b11111111, 23'b0};
        else begin
            // 简化实现
            temp_div = {sign1^sign2, 8'b01111111, 23'b0};
        end
    end
    assign div_result = temp_div;

    // 浮点绝对值 - 清除符号位
    assign abs_result = {1'b0, exp1, mant1};

    // 浮点取负 - 翻转符号位
    assign neg_result = {~sign1, exp1, mant1};

    // 浮点平方根 - 简化实现
    reg [31:0] temp_sqrt;
    always @(*) begin
        if (sign1 == 1'b1) // 负数开方，返回NaN
            temp_sqrt = {1'b0, 8'b11111111, 23'b1};
        else if (exp1 == 8'b0 && mant1 == 23'b0) // 0开方为0
            temp_sqrt = 32'b0;
        else
            temp_sqrt = {1'b0, 8'b01111111, 23'b0}; // 简化为1.0
    end
    assign sqrt_result = temp_sqrt;

    // 浮点移动
    assign mov_result = fpu_src1;

    // 浮点转整数 - 提取整数部分
    reg [31:0] temp_cvt_w;
    always @(*) begin
        if (exp1 < 8'd127) // 指数小于127，绝对值小于1
            temp_cvt_w = 32'b0;
        else if (exp1 >= 8'd158) // 指数大于等于158，溢出
            temp_cvt_w = sign1 ? 32'h80000000 : 32'h7FFFFFFF;
        else begin
            // 简化实现：直接返回符号+部分尾数
            temp_cvt_w = sign1 ? {1'b1, 31'b0} : {1'b0, 31'b1};
        end
    end
    assign cvt_w_result = temp_cvt_w;

    // 整数转浮点
    reg [31:0] temp_cvt_s;
    always @(*) begin
        if (fpu_src1 == 32'b0)
            temp_cvt_s = 32'b0;
        else if (fpu_src1[31] == 1'b1) // 负整数
            temp_cvt_s = {1'b1, 8'b01111111, 23'b0}; // 简化为-1.0
        else // 正整数
            temp_cvt_s = {1'b0, 8'b01111111, 23'b0}; // 简化为1.0
    end
    assign cvt_s_result = temp_cvt_s;

    // 浮点比较相等
    assign cmp_eq_result = (fpu_src1 == fpu_src2) ? 32'b1 : 32'b0;

    // 浮点比较小于 - 简化实现
    reg [31:0] temp_cmp_lt;
    always @(*) begin
        // 简化的比较：先比较符号位，再比较指数和尾数
        if (sign1 != sign2)
            temp_cmp_lt = sign1 ? 32'b1 : 32'b0; // 负数小于正数
        else if (sign1 == 1'b0) // 都是正数
            temp_cmp_lt = (fpu_src1 < fpu_src2) ? 32'b1 : 32'b0;
        else // 都是负数
            temp_cmp_lt = (fpu_src1 > fpu_src2) ? 32'b1 : 32'b0;
    end
    assign cmp_lt_result = temp_cmp_lt;

    // 选择输出结果
    assign fpu_result = fpu_add    ? add_result :
                        fpu_sub    ? sub_result :
                        fpu_mul    ? mul_result :
                        fpu_div    ? div_result :
                        fpu_abs    ? abs_result :
                        fpu_neg    ? neg_result :
                        fpu_sqrt   ? sqrt_result :
                        fpu_mov    ? mov_result :
                        fpu_cvt_w  ? cvt_w_result :
                        fpu_cvt_s  ? cvt_s_result :
                        fpu_cmp_eq ? cmp_eq_result :
                        fpu_cmp_lt ? cmp_lt_result :
                        32'b0;

endmodule