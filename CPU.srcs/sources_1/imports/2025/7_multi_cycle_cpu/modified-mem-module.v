`timescale 1ns / 1ps
module mem(
    input              clk,             // 时钟信号
    input              MEM_valid,       // 访存级有效信号
    input      [110:0] EXE_MEM_bus_r,   // 从执行级接收的扩展总线（包含异常信息）
    input      [31:0]  dm_rdata,        // 数据存储器读取的数据
    output     [31:0]  dm_addr,         // 数据存储器地址
    output reg [3:0]   dm_wen,          // 数据存储器写使能信号
    output reg [31:0]  dm_wdata,        // 数据存储器写数据
    output             MEM_over,        // 访存级执行完成信号
    output     [75:0]  MEM_WB_bus,      // 访存级到写回级的扩展总线（包含异常信息）
    output     [31:0]  MEM_pc,          // 访存级PC值
    
    // 异常检测
    output             mem_exc_detect,   // 访存级异常检测信号
    output reg [4:0]   mem_exc_code

);

    //-----{EXE->MEM总线信号解析}begin
    wire [3:0]  mem_control;     // 访存控制信号
    wire [31:0] store_data;      // 存储数据
    wire [31:0] alu_result;      // ALU结果
    wire        rf_wen;          // 寄存器写使能
    wire [4:0]  rf_wdest;        // 寄存器写目标地址
    wire [31:0] pc;              // 程序计数器
    wire [4:0]  exc_code_in;    // 从执行级传递的异常码
    wire        exe_exc_detect;   // 从执行级传递的异常有效信号
    
    assign {mem_control, store_data, alu_result, rf_wen, rf_wdest, pc, exc_code_in, exc_exc_detect } = EXE_MEM_bus_r;
    //-----{EXE->MEM总线信号解析}end

    //-----{访存操作处理}begin
    wire inst_load, inst_store, ls_word, lb_sign;  // 访存控制信号解析
    assign {inst_load, inst_store, ls_word, lb_sign} = mem_control;
    assign dm_addr = alu_result;  // 访存地址为ALU计算结果

    // 异常检测逻辑
    // reg [4:0] mem_exc_code;      // 访存级异常码
    reg       mem_exc_valid;     // 访存级异常有效信号
    
    // 地址对齐检查
    wire addr_align_error = (ls_word && (dm_addr[1:0] != 2'b00));  // 字访问必须对齐
    
    // 地址范围检查（可选，取决于内存映射）
    // 示例：检查地址是否在有效范围内（例如 0x00000000-0x0FFFFFFF）
    wire addr_range_error = (dm_addr[31:28] != 4'h0 && dm_addr[31:28] != 4'h8);
    
    // 基于操作类型的异常检测
    always @(*) begin
        if (exe_exc_detect) begin
            // 传递前一阶段的异常
            mem_exc_valid = 1'b1;
            mem_exc_code = exc_code_in;
        end
        else if (MEM_valid) begin
            if (inst_store && addr_align_error) begin
                // 存储地址对齐错误
                mem_exc_valid = 1'b1;
                mem_exc_code = 5'h05;  // EXC_ADES（存储地址错误）
            end
            else if (inst_load && addr_align_error) begin
                // 加载地址对齐错误
                mem_exc_valid = 1'b1;
                mem_exc_code = 5'h04;  // EXC_ADEL（加载地址错误）
            end
            else if ((inst_store || inst_load) && addr_range_error) begin
                // 内存地址超出范围
                mem_exc_valid = 1'b1;
                mem_exc_code = inst_store ? 5'h05 : 5'h04;  // EXC_ADES或EXC_ADEL
            end
            else begin
                mem_exc_valid = 1'b0;
                mem_exc_code = 5'h00;
            end
        end
        else begin
            mem_exc_valid = 1'b0;
            mem_exc_code = 5'h00;
        end
    end
    
    // 输出异常检测信号
    assign mem_exc_detect = mem_exc_valid;

    // 写使能信号生成 - 仅在无异常时启用写操作
    always @ (*) begin
        if (MEM_valid && inst_store && !mem_exc_valid) begin
            if (ls_word)
                dm_wen = 4'b1111;  // 字存储，所有字节都写入
            else begin
                case (dm_addr[1:0])
                    2'b00   : dm_wen = 4'b0001;  // 最低字节
                    2'b01   : dm_wen = 4'b0010;  // 次低字节
                    2'b10   : dm_wen = 4'b0100;  // 次高字节
                    2'b11   : dm_wen = 4'b1000;  // 最高字节
                    default : dm_wen = 4'b0000;
                endcase
            end
        end else
            dm_wen = 4'b0000;  // 默认不写入
    end

    // 写数据生成
    always @ (*) begin
        if (ls_word) begin
            dm_wdata = store_data;  // 字存储，直接使用原始数据
        end else begin
            case (dm_addr[1:0])
                2'b00   : dm_wdata = {24'd0, store_data[7:0]};             // 最低字节位置
                2'b01   : dm_wdata = {16'd0, store_data[7:0], 8'd0};       // 次低字节位置
                2'b10   : dm_wdata = {8'd0, store_data[7:0], 16'd0};       // 次高字节位置
                2'b11   : dm_wdata = {store_data[7:0], 24'd0};             // 最高字节位置
                default : dm_wdata = store_data;
            endcase
        end
    end

    // 读数据处理
    wire [31:0] load_byte = (dm_addr[1:0]==2'd0) ? dm_rdata[7:0] :
                            (dm_addr[1:0]==2'd1) ? dm_rdata[15:8] :
                            (dm_addr[1:0]==2'd2) ? dm_rdata[23:16] : 
                                                   dm_rdata[31:24];  // 根据地址选择字节
    wire        load_sign = load_byte[7];  // 字节的符号位
    wire [31:0] load_result = ls_word ? dm_rdata : 
                             (lb_sign ? {{24{load_sign}}, load_byte} : {24'd0, load_byte});  // 字节扩展
    //-----{访存操作处理}end

    //-----{访存执行完成信号}begin
    reg MEM_valid_r;
    always @(posedge clk) MEM_valid_r <= MEM_valid;
    assign MEM_over = inst_load ? MEM_valid_r : MEM_valid;  // 加载指令需要等待一个周期
    //-----{访存执行完成信号}end

    //-----{MEM->WB总线生成}begin
    wire [31:0] mem_result = inst_load ? load_result : alu_result;  // 传递给写回级的结果
    // 在访存到写回总线中包含异常信息
    assign MEM_WB_bus = {dm_addr, rf_wen, rf_wdest, mem_result, pc, mem_exc_code, mem_exc_detect};
    //-----{MEM->WB总线生成}end

    assign MEM_pc = pc;  // 输出访存级PC值
endmodule