`timescale 1ns / 1ps
//*************************************************************************
//   > 文件名: tb.v
//   > 描述  : 仿真测试文件
//   > 作者  : 白星炜
//   > 日期  : 2025-03-27
//   > 修改  : 加入取指模块信号观测 (2025-04-24)
//   > 修改  : 增强中断测试功能 (2025-04-25)
//*************************************************************************
module tb;

    // 基本信号声明
    reg clk;
    reg resetn;
    reg [4:0] rf_addr;
    reg [31:0] mem_addr;
    reg [7:0] ext_int;  // 外部中断信号输入

    // 原始输出信号
    wire [31:0] rf_data;
    wire [31:0] mem_data;
    wire [31:0] IF_inst;
    wire [31:0] IF_pc;
    wire [31:0] ID_pc;
    wire [31:0] EXE_pc;
    wire [31:0] MEM_pc;
    wire [31:0] WB_pc;
    wire [31:0] display_state;

    // 寄存器观测信号
    wire [31:0] reg0  = uut.rf_module.rf[0];
    wire [31:0] reg1  = uut.rf_module.rf[1];
    wire [31:0] reg2  = uut.rf_module.rf[2];
    wire [31:0] reg3  = uut.rf_module.rf[3];
    wire [31:0] reg4  = uut.rf_module.rf[4];
    wire [31:0] reg5  = uut.rf_module.rf[5];
    wire [31:0] reg6  = uut.rf_module.rf[6];
    wire [31:0] reg7  = uut.rf_module.rf[7];
    wire [31:0] reg8  = uut.rf_module.rf[8];
    wire [31:0] reg9  = uut.rf_module.rf[9];
    wire [31:0] reg10 = uut.rf_module.rf[10];
    wire [31:0] reg11 = uut.rf_module.rf[11];
    wire [31:0] reg12 = uut.rf_module.rf[12];
    wire [31:0] reg13 = uut.rf_module.rf[13];
    wire [31:0] reg14 = uut.rf_module.rf[14];
    wire [31:0] reg15 = uut.rf_module.rf[15];

    // CP0寄存器观测信号
    wire [31:0] cp0_status    = uut.cp0_status;    // CP0状态寄存器
    wire [31:0] cp0_cause     = uut.cp0_cause;     // CP0原因寄存器
    wire [31:0] cp0_epc       = uut.cp0_epc;       // CP0异常PC寄存器
    wire [31:0] cp0_badvaddr  = uut.cp0_badvaddr;  // CP0错误虚地址寄存器
    
    // 异常检测信号
    wire has_exc         = uut.has_exc;          // 是否有异常发生
    wire [4:0] exc_code  = uut.exc_code;         // 异常编码
    wire if_exc_detect   = uut.if_exc_detect;    // 取指级异常检测
    wire id_exc_detect   = uut.id_exc_detect;    // 译码级异常检测
    wire exe_exc_detect  = uut.exe_exc_detect;   // 执行级异常检测
    wire mem_exc_detect  = uut.mem_exc_detect;   // 访存级异常检测
    wire int_detect      = uut.int_detect;       // 中断检测

    // 结束信号
    wire IF_over = uut.IF_over;     // IF模块已执行完
    wire ID_over = uut.ID_over;     // ID模块已执行完
    wire EXE_over = uut.EXE_over;   // EXE模块已执行完
    wire MEM_over = uut.MEM_over;   // MEM模块已执行完
    wire WB_over = uut.WB_over;     // WB模块已执行完
    wire EXC_over = uut.EXC_over;   // 异常处理模块已执行完

    // 调试信号
    wire next_fetch = uut.next_fetch;
    wire [2:0] cpu_state = uut.state;  // CPU当前状态

    // 取指模块信号
    wire [31:0] if_pc = uut.IF_module.pc;
    wire [31:0] if_seq_pc = uut.IF_module.seq_pc;
    wire [31:0] if_next_pc = uut.IF_module.next_pc;
    wire if_jbr_taken = uut.IF_module.jbr_taken;
    wire [31:0] if_jbr_target = uut.IF_module.jbr_target;
    wire if_is_eret = uut.IF_module.is_eret;      
    wire [31:0] if_exc_return_addr = uut.IF_module.exc_return_addr; 
    wire if_exc_valid = uut.IF_module.exc_valid;      
    wire [31:0] if_exc_handler_addr = uut.IF_module.exc_handler_addr;

    // 中断控制和监控变量
    reg [31:0] pc_before_int;  // 中断前的PC值
    reg int_triggered;         // 中断是否已触发
    reg int_handled;           // 中断是否已处理
    reg int_returned;          // 是否已从中断返回
    reg [31:0] trigger_cycle;  // 触发中断的周期

    // ID_EXE总线解析
    wire [155:0] ID_EXE_bus;
    wire [11:0]  alu_control;
    wire [31:0]  alu_operand1;
    wire [31:0]  alu_operand2;
    wire [3:0]   mem_control;
    wire [31:0]  store_data;
    wire         id_rf_wen;
    wire [4:0]   id_rf_wdest;
    wire [31:0]  pc_in_ID_EXE;

    assign ID_EXE_bus = uut.ID_module.ID_EXE_bus;
    assign {
        alu_control,
        alu_operand1,
        alu_operand2,
        mem_control,
        store_data,
        id_rf_wen,
        id_rf_wdest,
        pc_in_ID_EXE
    } = ID_EXE_bus;

    // 实例化被测单元
    multi_cycle_cpu uut (
        .clk(clk),
        .resetn(resetn),
        .ext_int(ext_int),         // 外部中断输入
        .rf_addr(rf_addr),
        .rf_data(rf_data),
        .mem_addr(mem_addr),
        .mem_data(mem_data),
        .IF_inst(IF_inst),
        .IF_pc(IF_pc),
        .ID_pc(ID_pc),
        .EXE_pc(EXE_pc),
        .MEM_pc(MEM_pc),
        .WB_pc(WB_pc),
        .display_state(display_state)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 周期计数器
    reg [31:0] cycle_count;
    initial begin
        cycle_count = 0;
        int_triggered = 0;
        int_handled = 0;
        int_returned = 0;
        trigger_cycle = 0;
    end
    
    always @(posedge clk) begin
        if (resetn) begin
            cycle_count <= cycle_count + 1;
        end
    end

    // 测试流程控制
    initial begin
        // 初始化
        resetn = 0;
        rf_addr = 0;
        mem_addr = 32'h1000;
        ext_int = 8'h00;       // 初始化外部中断为0
        
        // 复位释放
        #100;
        resetn = 1;
        
        // 在CPU稳定运行后记录初始寄存器状态
        #500;
        $display("---- Initial Register Snapshot @%0t ns (Cycle %0d) ----", $time, cycle_count);
        $display("$0 : %h", reg0);
        $display("$1 : %h", reg1);
        $display("$2 : %h", reg2);
        $display("$3 : %h", reg3);
        $display("$8 : %h", reg8);
        $display("$9 : %h", reg9);
        
        // 添加取指模块信号显示
        $display("---- Fetch Module Signals @%0t ns ----", $time);
        $display("PC: %h", if_pc);
        $display("Seq PC: %h", if_seq_pc);
        $display("Next PC: %h", if_next_pc);
        $display("Jump/Branch Taken: %b", if_jbr_taken);
        $display("Jump/Branch Target: %h", if_jbr_target);
        $display("Is ERET: %b", if_is_eret);
        $display("Exception Return Address: %h", if_exc_return_addr);
        $display("Exception Valid: %b", if_exc_valid);
        $display("Exception Handler Address: %h", if_exc_handler_addr);

        // 添加CP0和异常状态显示
        $display("---- Exception Status @%0t ns ----", $time);
        $display("has_exc: %b, exc_code: %h", has_exc, exc_code);
        $display("IF_exc: %b, ID_exc: %b, EXE_exc: %b, MEM_exc: %b", 
                 if_exc_detect, id_exc_detect, exe_exc_detect, mem_exc_detect);
        $display("CP0_Status: %h, CP0_Cause: %h", cp0_status, cp0_cause);
        $display("CP0_EPC: %h, CP0_BadVAddr: %h", cp0_epc, cp0_badvaddr);
        
        // 运行一段时间后在固定周期触发外部中断0
        // 等待CPU执行到第500个周期后触发中断
        wait(cycle_count >= 500);
        pc_before_int = IF_pc;  // 记录中断前的PC
        trigger_cycle = cycle_count;
        $display("\n---- Triggering External Interrupt @%0t ns (Cycle %0d) ----", $time, cycle_count);
        $display("PC before interrupt: %h", pc_before_int);
        $display("Current instruction: %h", IF_inst);
        $display("CPU State: %d", cpu_state);
        
        // 触发中断0
        ext_int = 8'h01;
        int_triggered = 1;
        
        // 维持中断信号一段时间后清除
        #200;
        ext_int = 8'h00;
        $display("---- Cleared External Interrupt @%0t ns (Cycle %0d) ----\n", $time, cycle_count);
        
        // 等待中断处理完成
        wait(int_returned);
        $display("\n---- Interrupt Processing Complete @%0t ns (Cycle %0d) ----", $time, cycle_count);
        $display("Total cycles for interrupt handling: %0d", cycle_count - trigger_cycle);
        
        // 运行一段时间后检查寄存器状态
        #5000;
        $display("\n---- Register State After Interrupt @%0t ns (Cycle %0d) ----", $time, cycle_count);
        $display("$0 : %h", reg0);
        $display("$1 : %h", reg1);
        $display("$2 : %h", reg2);
        $display("$3 : %h", reg3);
        $display("$8 : %h", reg8);
        $display("$9 : %h", reg9);
        $display("$10: %h", reg10);
        $display("$11: %h", reg11);
        $display("$15: %h", reg15);
        
        // 从中断返回后的CP0状态
        $display("\n---- CP0 State After Interrupt Return ----");
        $display("CP0_Status: %h, CP0_Cause: %h", cp0_status, cp0_cause);
        $display("CP0_EPC: %h, CP0_BadVAddr: %h", cp0_epc, cp0_badvaddr);
        
        // 继续运行一段时间，确保所有指令执行完毕
        #10000;
        $display("\n---- Final Register Values @%0t ns (Cycle %0d) ----", $time, cycle_count);
        $display("$10: %h", reg10);
        $display("$11: %h", reg11);
        $display("$15: %h", reg15);
        
        // 添加最终CP0寄存器状态显示
        $display("\n---- Final Exception Status @%0t ns ----", $time);
        $display("CP0_Status: %h, CP0_Cause: %h", cp0_status, cp0_cause);
        $display("CP0_EPC: %h, CP0_BadVAddr: %h", cp0_epc, cp0_badvaddr);
        
        #100;
        $finish;
    end
    
    // 中断处理检测
    always @(posedge clk) begin
        if (resetn && int_triggered && !int_handled && uut.state == uut.EXC) begin
            int_handled = 1;
            $display("\n---- Entered Exception Handling State @%0t ns (Cycle %0d) ----", $time, cycle_count);
            $display("Exception Code: %h (Expected: %h for external interrupt)", exc_code, 5'h00);
            $display("CP0_Status: %h", cp0_status);
            $display("CP0_Cause: %h", cp0_cause);
            $display("CP0_EPC (saved PC): %h (Expected close to: %h)", cp0_epc, pc_before_int);
        end
    end
    
    // 从中断返回检测 (检测ERET指令执行)
    always @(posedge clk) begin
        if (resetn && int_handled && !int_returned && if_is_eret) begin
            int_returned = 1;
            $display("\n---- Returning From Exception @%0t ns (Cycle %0d) ----", $time, cycle_count);
            $display("Exception Return Address: %h", if_exc_return_addr);
            $display("Should match CP0_EPC: %h", cp0_epc);
            $display("CPU resuming execution from: %h", if_next_pc);
        end
    end
    
    // 异常检测监视器
    always @(posedge clk) begin
        if (has_exc && resetn) begin
            $display("\n---- Exception Detected @%0t ns (Cycle %0d) ----", $time, cycle_count);
            $display("Exception Code: %h", exc_code);
            $display("PC at Exception: IF=%h, ID=%h, EXE=%h, MEM=%h", IF_pc, ID_pc, EXE_pc, MEM_pc);
            $display("CP0_Status: %h, CP0_Cause: %h", cp0_status, cp0_cause);
        end
    end

    // 波形记录配置
    initial begin
        $dumpfile("cpu_waveform.vcd");
        $dumpvars(0, tb);
        
        // 记录中断处理相关信号
        $dumpvars(0, int_triggered, int_handled, int_returned, pc_before_int, trigger_cycle);
        $dumpvars(0, cpu_state, next_fetch);
        $dumpvars(0, IF_over, ID_over, EXE_over, MEM_over, WB_over, EXC_over);
        
        // 显式记录关键寄存器
        $dumpvars(0, reg0, reg1, reg2, reg3, reg4, reg5);
        $dumpvars(0, reg6, reg7, reg8, reg9, reg10, reg11);
        
        // 添加CP0寄存器和异常信号到波形记录
        $dumpvars(0, cp0_status, cp0_cause, cp0_epc, cp0_badvaddr);
        $dumpvars(0, has_exc, exc_code, if_exc_detect, id_exc_detect, exe_exc_detect, mem_exc_detect, int_detect);
        $dumpvars(0, ext_int, cycle_count);
        
        // 添加取指模块信号到波形记录
        $dumpvars(0, if_pc, if_seq_pc, if_next_pc, if_is_eret, if_exc_return_addr, if_exc_valid);
        $dumpvars(0, if_exc_handler_addr, if_jbr_taken, if_jbr_target);
    end

endmodule