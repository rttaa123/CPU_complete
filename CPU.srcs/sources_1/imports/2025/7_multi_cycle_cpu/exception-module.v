module exception(
    input  wire        clk,           // 时钟
    input  wire        resetn,        // 复位信号，低电平有效
    input  wire        EXC_valid,     // 异常处理级有效信号
    
    // 各流水级总线，用于定位异常发生位置
    input  wire [69:0] IF_ID_bus_r,   // IF->ID总线
    input  wire [155:0] ID_EXE_bus_r,  // ID->EXE总线 
    input  wire [111:0] EXE_MEM_bus_r, // EXE->MEM总线
    input  wire [75:0] MEM_WB_bus_r,   // MEM->WB总线
    
    // CP0寄存器信息
    input  wire [31:0] cp0_status,    // CP0状态寄存器
    input  wire [31:0] cp0_cause,     // CP0原因寄存器
    input  wire [31:0] cp0_epc,       // CP0异常PC寄存器
    
    // 异常检测信号
    input  wire        int_detect,    // 中断检测信号
    input  wire [4:0]  exc_code,      // 异常编码
    
    // 输出信号
    output wire        EXC_over,      // 异常处理完成
    output wire [70:0] EXC_bus,       // 异常总线
    output wire [31:0] exc_pc,        // 异常发生的PC
    output wire [31:0] exc_badvaddr   // 错误的虚地址
);

    // 异常处理状态
    reg [1:0] exc_state;
    parameter EXC_IDLE = 2'b00;   // 空闲
    parameter EXC_PROC = 2'b01;   // 处理中
    parameter EXC_DONE = 2'b10;   // 完成
    
    // 异常处理入口地址
    parameter EXC_HANDLER_ADDR = 32'h80000180;  // 标准MIPS异常处理入口
    
    // 异常处理完成信号
    assign EXC_over = (exc_state == EXC_DONE);
    
    // 记录异常信息
    reg  [31:0] exc_pc_r;          // 发生异常时的PC值 
    reg  [31:0] exc_badvaddr_r;    // 导致异常的错误地址
    wire [31:0] return_pc;         // 异常处理完成后返回的PC
    
    // 获取返回地址
    assign return_pc = cp0_epc;
    
    // 输出异常PC和错误虚地址
    assign exc_pc = exc_pc_r;
    assign exc_badvaddr = exc_badvaddr_r;
    
    // 异常处理总线
    // [70:39] - 返回地址
    // [38:7]  - 异常处理程序入口
    // [6]     - 是否是异常返回指令
    // [5:1]   - 异常码
    // [0]     - 异常总线有效位
    // assign EXC_bus = {return_pc, EXC_HANDLER_ADDR, 1'b1, exc_code, 1'b1};
    // 异常处理总线赋值
    assign EXC_bus = (EXC_valid && exc_state == EXC_PROC) ? 
                 {cp0_epc, EXC_HANDLER_ADDR, 1'b0, exc_code, 1'b1} : 
                 71'd0;


    // 异常状态机
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            exc_state <= EXC_IDLE;
        end
        else if (EXC_valid) begin
            case (exc_state)
                EXC_IDLE: begin
                    exc_state <= EXC_PROC;
                end
                EXC_PROC: begin
                    exc_state <= EXC_DONE;
                end
                EXC_DONE: begin
                    exc_state <= EXC_IDLE;
                end
                default: begin
                    exc_state <= EXC_IDLE;
                end
            endcase
        end
    end
    
    // 确定异常来源和发生位置
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            exc_pc_r <= 32'h0;
            exc_badvaddr_r <= 32'h0;
        end
        else if (EXC_valid && exc_state == EXC_IDLE) begin
            // 根据当前异常发生的级别，从对应的总线中提取PC
            if (int_detect) begin
                // 中断，使用当前PC
                if (IF_ID_bus_r[0]) begin  // IF阶段总线有效
                    exc_pc_r <= IF_ID_bus_r[69:38];  // 假设PC位于高位
                end
                else if (ID_EXE_bus_r[0]) begin  // ID阶段总线有效
                    exc_pc_r <= ID_EXE_bus_r[155:124];  // 假设PC位于高位
                end
                else if (EXE_MEM_bus_r[0]) begin  // EXE阶段总线有效
                    exc_pc_r <= EXE_MEM_bus_r[111:80];  // 假设PC位于高位
                end
                else if (MEM_WB_bus_r[0]) begin  // MEM阶段总线有效
                    exc_pc_r <= MEM_WB_bus_r[75:44];  // 假设PC位于高位
                end
            end
            // 取指异常 (IF阶段)
            else if (IF_ID_bus_r[0] && exc_code == 5'h04) begin // ADEL
                exc_pc_r <= IF_ID_bus_r[69:38];
                exc_badvaddr_r <= IF_ID_bus_r[37:6]; // 假设存储了错误的指令地址
            end
            // 解码异常 (ID阶段，如保留指令)
            else if (ID_EXE_bus_r[0] && exc_code == 5'h0a) begin // RI
                exc_pc_r <= ID_EXE_bus_r[155:124];
            end
            // 执行异常 (EXE阶段，如算术溢出)
            else if (EXE_MEM_bus_r[0] && exc_code == 5'h0c) begin // OV
                exc_pc_r <= EXE_MEM_bus_r[111:80];
            end
            // 访存异常 (MEM阶段，如地址错误)
            else if (MEM_WB_bus_r[0] && (exc_code == 5'h04 || exc_code == 5'h05)) begin // ADEL/ADES
                exc_pc_r <= MEM_WB_bus_r[75:44];
                exc_badvaddr_r <= MEM_WB_bus_r[43:12]; // 假设存储了访存的地址
            end
            // 其他异常情况
            else begin
                // 默认使用IF阶段PC
                if (IF_ID_bus_r[0]) begin
                    exc_pc_r <= IF_ID_bus_r[69:38];
                end
                else if (ID_EXE_bus_r[0]) begin
                    exc_pc_r <= ID_EXE_bus_r[155:124];
                end
                else if (EXE_MEM_bus_r[0]) begin
                    exc_pc_r <= EXE_MEM_bus_r[111:80];
                end
                else if (MEM_WB_bus_r[0]) begin
                    exc_pc_r <= MEM_WB_bus_r[75:44];
                end
            end
        end
    end
    
endmodule