`timescale 1ns / 1ps
//*************************************************************************
//   > 文件名: multi_cycle_cpu.v
//   > 描述  :多周期CPU模块，共实现36条指令 + FPU浮点指令，支持异常和中断处理
//   >        集成Bus4LZU模块替代原有的指令rom和数据ram
//   > 作者  : 饶甜甜 (修改：添加FPU支持)
//   > 日期  : 2025-07-04
//*************************************************************************
module multi_cycle_cpu(  // 多周期cpu
    input clk,           // 时钟
    input resetn,        // 复位信号，低电平有效
    
    // 外部中断信号 - 改为只接收timer_irq
    input timer_irq,     // Timer中断请求信号
    
    // 与Bus4LZU连接的接口
    output [31:0] inst_addr,  // 发送往Icache的地址
    input  [31:0] inst_data,  // 从Icache读取的指令
    output [31:0] data_addr,  // Dcache或外设的目的地址
    output [ 3:0] data_wen,   // Dcache或外设写使能信号
    output [31:0] write_data, // 发送往Dcache或外设的数据
    input  [31:0] read_data,  // 从Dcache或外设读取的数据
    
    //display data
    input  [ 4:0] rf_addr,  //输入一个5位的寄存器地址（范围0~31）
    output [31:0] rf_data,  //根据rf_addr输入的地址，输出对应寄存器的32位值
    input  [31:0] mem_addr, //外部输入一个32位地址，指定需要查看的数据存储器位置
    output [31:0] mem_data, //输出mem_addr指定地址对应存储器的32位值
    output [31:0] IF_inst,  //输出当前正在取指的32位指令内容
    output [31:0] IF_pc,    //取指阶段正在处理的指令地址
    output [31:0] ID_pc,    //译码阶段对应的指令地址
    output [31:0] EXE_pc,   //执行阶段对应的指令地址
    output [31:0] MEM_pc,   //访存阶段对应的指令地址
    output [31:0] WB_pc,    //写回阶段对应的指令地址
    output [31:0] display_state //低3位表示状态（state）
    );
    
    // 异常类型编码
    parameter EXC_INT    = 5'h00;  // 外部中断
    parameter EXC_ADEL   = 5'h04;  // 取指地址错误
    parameter EXC_ADES   = 5'h05;  // 存储地址错误
    parameter EXC_SYS    = 5'h08;  // 系统调用
    parameter EXC_BP     = 5'h09;  // 断点
    parameter EXC_RI     = 5'h0a;  // 保留指令
    parameter EXC_OV     = 5'h0c;  // 算术溢出

    // CP0寄存器
    reg [31:0] cp0_status;  // CP0状态寄存器
    reg [31:0] cp0_cause;   // CP0原因寄存器
    reg [31:0] cp0_epc;     // CP0异常PC寄存器
    reg [31:0] cp0_badvaddr;// CP0错误虚地址寄存器
    
    // CP0寄存器映射
    parameter CP0_STATUS    = 5'd12;  // Status寄存器地址
    parameter CP0_CAUSE     = 5'd13;  // Cause寄存器地址
    parameter CP0_EPC       = 5'd14;  // EPC寄存器地址
    parameter CP0_BADVADDR  = 5'd8;   // BadVAddr寄存器地址

//----------------------{控制多周期的状态机}begin------------------------//
    reg [2:0] state;       // 当前状态
    reg [2:0] next_state;  // 下一状态

    //展示当前处理器正在执行哪个模块
    assign display_state = {29'd0,state};
    // 状态机状态
    parameter IDLE   = 3'd0;  // 开始
    parameter FETCH  = 3'd1;  // 取指
    parameter DECODE = 3'd2;  // 译码
    parameter EXE    = 3'd3;  // 执行
    parameter MEM    = 3'd4;  // 访存
    parameter WB     = 3'd5;  // 写回
    parameter EXC    = 3'd6;  // 异常处理

    always @ (posedge clk)        // 当前状态
    begin
        if (!resetn) begin        // 如果复位信号有效
            state <= IDLE;       // 当前状态为 开始
        end
        else begin                // 否则
            state <= next_state;  // 为下一状态
        end
    end

    wire IF_over;     // IF模块已执行完
    wire ID_over;     // ID模块已执行完
    wire EXE_over;    // EXE模块已执行完
    wire MEM_over;    // MEM模块已执行完
    wire WB_over;     // WB模块已执行完
    wire EXC_over;    // 异常处理模块已执行完
    wire jbr_not_link;//分支指令(非link类)，只走IF和ID级
    
    // 异常和中断检测信号
    wire has_exc;           // 是否有异常发生
    wire [4:0] exc_code;    // 异常编码
    wire if_exc_detect;     // 取指级异常检测
    wire id_exc_detect;     // 译码级异常检测
    wire exe_exc_detect;    // 执行级异常检测
    wire mem_exc_detect;    // 访存级异常检测
    
    // 中断使能检测
    wire int_detect;        // 中断检测信号
    
    // 综合各级异常信号
    assign has_exc = if_exc_detect | id_exc_detect | exe_exc_detect | mem_exc_detect | int_detect;
    
    always @ (*)                             // 下一状态 
    begin
        case (state)
            IDLE : 
            begin
                next_state = FETCH;    // 开始->取指
            end
            FETCH: 
            begin
                if (IF_over)
                begin
                    if(if_exc_detect | int_detect)  // 取指级检测到异常或中断
                        next_state = EXC;          // 转到异常处理状态
                    else
                        next_state = DECODE;       // 取指->译码
                end
                else
                begin
                    next_state = FETCH;    // 取指->取指
                end
            end
            DECODE: 
            begin
                if (ID_over)
                begin
                    if(id_exc_detect)             // 译码级检测到异常
                        next_state = EXC;         // 转到异常处理状态
                    else                          // 译码->执行或取指   
                        next_state = jbr_not_link ? FETCH : EXE;
                end
                else
                begin
                    next_state = DECODE;   // 译码->译码
                end
            end
            EXE: 
            begin
                if (EXE_over)
                begin
                    if(exe_exc_detect)            // 执行级检测到异常
                        next_state = EXC;         // 转到异常处理状态
                    else
                        next_state = MEM;         // 执行->访存
                end
                else
                begin
                    next_state = EXE;   // 执行->执行
                end
            end
            MEM:
            begin
                if (MEM_over)
                begin
                    if(mem_exc_detect)            // 访存级检测到异常
                        next_state = EXC;         // 转到异常处理状态
                    else
                        next_state = WB;          // 访存->写回
                end
                else
                begin
                    next_state = MEM;   // 访存->访存
                end
            end
            WB:
            begin
                if (WB_over)
                begin
                    next_state = FETCH;    // 写回->取指
                end
                else
                begin
                    next_state = WB;   // 写回->写回
                end
            end
            EXC:
            begin
                if (EXC_over)
                begin
                    next_state = FETCH;    // 异常处理->取指
                end
                else
                begin
                    next_state = EXC;      // 异常处理->异常处理
                end
            end
            default : next_state = FETCH;
        endcase
    end
    //6模块的valid信号
    wire IF_valid;
    wire ID_valid;
    wire EXE_valid;
    wire MEM_valid;
    wire WB_valid;
    wire EXC_valid;
    assign  IF_valid = (state == FETCH );  // 当前状态为取指时，IF级有效
    assign  ID_valid = (state == DECODE);  // 当前状态为译码时，ID级有效
    assign EXE_valid = (state == EXE   );  // 当前状态为执行时，EXE级有效
    assign MEM_valid = (state == MEM   );  // 当前状态为访存时，MEM级有效
    assign  WB_valid = (state == WB    );  // 当前状态为写回时，WB级有效
    assign EXC_valid = (state == EXC   );  // 当前状态为异常处理时，EXC级有效
//-----------------------{控制多周期的状态机}end-------------------------//

//--------------------------{5级间的总线}begin---------------------------//
    // 各阶段之间传递数据的总线定义（扩展支持FPU）
    wire [ 69:0] IF_ID_bus;   // IF->ID级总线 (保持原有异常信息)
    wire [161:0] ID_EXE_bus;  // ID->EXE级总线 (扩展到162位支持FPU，与代码1一致)
    wire [111:0] EXE_MEM_bus; // EXE->MEM级总线 (保持原有异常信息)
    wire [ 75:0] MEM_WB_bus;  // MEM->WB级总线 (保持原有异常信息)
    wire [ 70:0] EXC_bus;     // 异常处理总线
    
    //锁存以上总线信号
    reg [ 69:0] IF_ID_bus_r;
    reg [161:0] ID_EXE_bus_r;  // 扩展到162位支持FPU
    reg [111:0] EXE_MEM_bus_r;
    reg [ 75:0] MEM_WB_bus_r;
    reg [ 70:0] EXC_bus_r;
    
    //IF到ID的锁存信号
    always @(posedge clk)
    begin
        if(IF_over)
        begin
            IF_ID_bus_r <= IF_ID_bus;
        end
    end
    //ID到EXE的锁存信号
    always @(posedge clk)
    begin
        if(ID_over)
        begin
            ID_EXE_bus_r <= ID_EXE_bus;
        end
    end
    //EXE到MEM的锁存信号
    always @(posedge clk)
    begin
        if(EXE_over)
        begin
            EXE_MEM_bus_r <= EXE_MEM_bus;
        end
    end    
    //MEM到WB的锁存信号
    always @(posedge clk)
    begin
        if(MEM_over)
        begin
            MEM_WB_bus_r <= MEM_WB_bus;
        end
    end
    //异常处理总线的锁存信号
    always @(posedge clk)
    begin
        if(has_exc)
        begin
            EXC_bus_r <= EXC_bus;
        end
    end
//---------------------------{5级间的总线}end----------------------------//

//--------------------------{其他交互信号}begin--------------------------//
    //跳转总线
    wire [ 32:0] jbr_bus;    

    //MEM与Bus4LZU交互的信号    
    wire [ 3:0] dm_wen;
    wire [31:0] dm_addr;
    wire [31:0] dm_wdata;
    wire [31:0] dm_rdata;
    
    // 将MEM模块的信号连接到Bus4LZU
    assign data_addr = dm_addr;
    assign data_wen = dm_wen;
    assign write_data = dm_wdata;
    assign dm_rdata = read_data;
    
    // 将调试访问信号连接到Bus4LZU
    // 如果地址在内存区域，直接查询read_data
    // 否则返回未知值(因为读取外设需要实际发起读操作)
    assign mem_data = (mem_addr[31:16] == 16'h0) ? read_data : 32'hxxxxxxxx;

    //ID与regfile交互
    wire [ 4:0] rs;
    wire [ 4:0] rt;   
    wire [31:0] rs_value;
    wire [31:0] rt_value;
    
    //WB与regfile交互
    wire        rf_wen;
    wire [ 4:0] rf_wdest;
    wire [31:0] rf_wdata;
    
    //与CP0寄存器交互
    wire        cp0_wen;
    wire [ 4:0] cp0_wnum;
    wire [31:0] cp0_wdata;
    wire [ 4:0] cp0_rnum;
    wire [31:0] cp0_rdata;
    
    //中断处理
    wire [31:0] exc_pc;       // 异常处理程序入口地址
    wire [31:0] exc_type;     // 异常类型
    wire [31:0] exc_badvaddr; // 错误的虚拟地址
    
    // CP0寄存器读写逻辑
    assign cp0_rdata = (cp0_rnum == CP0_STATUS)   ? cp0_status :
                       (cp0_rnum == CP0_CAUSE)    ? cp0_cause  :
                       (cp0_rnum == CP0_EPC)      ? cp0_epc    :
                       (cp0_rnum == CP0_BADVADDR) ? cp0_badvaddr : 32'h0;
                       
    // CP0寄存器写入逻辑
    always @(posedge clk)
    begin
        if(!resetn)
        begin
            cp0_status   <= 32'h00000001;  // 初始状态，开中断
            cp0_cause    <= 32'h0;
            cp0_epc      <= 32'h0;
            cp0_badvaddr <= 32'h0;
        end
        else if(cp0_wen)  // 写入CP0寄存器
        begin
            case(cp0_wnum)
                CP0_STATUS:   cp0_status   <= cp0_wdata;
                CP0_CAUSE:    cp0_cause    <= cp0_wdata;
                CP0_EPC:      cp0_epc      <= cp0_wdata;
                CP0_BADVADDR: cp0_badvaddr <= cp0_wdata;
            endcase
        end
        else if(has_exc)  // 发生异常，更新CP0寄存器
        begin
            cp0_status[1]      <= 1'b1;              // 进入异常模式
            cp0_cause[6:2]     <= exc_code;          // 异常编码
            cp0_epc            <= exc_pc;            // 异常PC
            if(exc_code == EXC_ADEL || exc_code == EXC_ADES)
                cp0_badvaddr   <= exc_badvaddr;      // 错误地址
        end
        else if(state == EXC && EXC_over) // 异常处理结束
        begin
            cp0_status[1]      <= 1'b0;              // 退出异常模式
        end
    end
    
    // 将timer_irq映射到外部中断向量的第0位
    wire [7:0] ext_int_mapped;
    assign ext_int_mapped = {7'b0000000, timer_irq};
    
    // 中断检测逻辑
    // 当外部中断有效且中断使能有效时产生中断
    assign int_detect = |(ext_int_mapped & cp0_status[15:8]) & cp0_status[0] & ~cp0_status[1];
//---------------------------{其他交互信号}end---------------------------//

//-------------------------{各模块实例化}begin---------------------------//
    wire next_fetch; //即将运行取指模块，需要先锁存PC值
    //当前状态为decode，且指令为跳转分支指令(非link类)，且decode执行完成
    //或者，当前状态为wb，且wb执行完成，则即将进入fetch状态
    //或者，当前状态为exc，且exc执行完成，则即将进入fetch状态
    assign next_fetch = (state==DECODE & ID_over & jbr_not_link)
                      | (state==WB     & WB_over)
                      | (state==EXC    & EXC_over);
                      
    // 修改fetch模块，增加异常检测
    fetch IF_module(             // 取指级
        .clk       (clk       ),  // I, 1
        .resetn    (resetn    ),  // I, 1
        .IF_valid  (IF_valid  ),  // I, 1
        .next_fetch(next_fetch),  // I, 1
        .inst      (inst_data ),  // I, 32，接收来自Bus4LZU的指令
        .jbr_bus   (jbr_bus   ),  // I, 33
        .exc_bus   (EXC_bus   ),  // I, 71 (新增，用于处理异常返回)
        .inst_addr (inst_addr ),  // O, 32，输出到Bus4LZU的地址
        .IF_over   (IF_over   ),  // O, 1
        .IF_ID_bus (IF_ID_bus ),  // O, 69 (增加异常信息)
        
        // 异常检测
        .if_exc_detect(if_exc_detect), // O, 1 (新增)
        .if_exc_code    (exc_code),       // O, 5 (新增)
        
        //展示PC和取出的指令
        .IF_pc     (IF_pc     ),
        .IF_inst   (IF_inst   )
    );

    // 译码模块，扩展支持FPU
    decode ID_module(               // 译码级
        .ID_valid    (ID_valid    ),  // I, 1
        .IF_ID_bus_r (IF_ID_bus_r ),  // I, 69 (增加异常信息)
        .rs_value    (rs_value    ),  // I, 32
        .rt_value    (rt_value    ),  // I, 32
        .rs          (rs          ),  // O, 5
        .rt          (rt          ),  // O, 5
        .jbr_bus     (jbr_bus     ),  // O, 33
        .jbr_not_link(jbr_not_link),  // O, 1
        .ID_over     (ID_over     ),  // O, 1
        .ID_EXE_bus  (ID_EXE_bus  ),  // O, 162 (扩展支持FPU，与代码1一致)
        
        // 异常检测
        .id_exc_detect(id_exc_detect), // O, 1 (新增)
        
        //展示PC
        .ID_pc      (ID_pc      )
    );

    // 执行模块，扩展支持FPU
    exe EXE_module(                   // 执行级
        .EXE_valid   (EXE_valid   ),  // I, 1
        .ID_EXE_bus_r(ID_EXE_bus_r),  // I, 162 (扩展支持FPU，与代码1一致)
        .EXE_over    (EXE_over    ),  // O, 1 
        .EXE_MEM_bus (EXE_MEM_bus ),  // O, 111 (增加异常信息)
        
        // 异常检测
        .exe_exc_detect(exe_exc_detect), // O, 1 (新增)
        
        //展示PC
        .EXE_pc      (EXE_pc      )
    );

    mem MEM_module(                     // 访存级
        .clk          (clk          ),  // I, 1 
        .MEM_valid    (MEM_valid    ),  // I, 1
        .EXE_MEM_bus_r(EXE_MEM_bus_r),  // I, 111 (增加异常信息)
        .dm_rdata     (dm_rdata     ),  // I, 32
        .dm_addr      (dm_addr      ),  // O, 32
        .dm_wen       (dm_wen       ),  // O, 4 
        .dm_wdata     (dm_wdata     ),  // O, 32
        .MEM_over     (MEM_over     ),  // O, 1
        .MEM_WB_bus   (MEM_WB_bus   ),  // O, 75 (增加异常信息)
        
        // 异常检测
        .mem_exc_detect(mem_exc_detect), // O, 1 (新增)
        
        //展示PC
        .MEM_pc       (MEM_pc       )
    );          
 
    wb WB_module(                     // 写回级
        .WB_valid    (WB_valid    ),  // I, 1
        .MEM_WB_bus_r(MEM_WB_bus_r),  // I, 75 (增加异常信息)
        .rf_wen      (rf_wen      ),  // O, 1
        .rf_wdest    (rf_wdest    ),  // O, 5
        .rf_wdata    (rf_wdata    ),  // O, 32
        .WB_over     (WB_over     ),  // O, 1
        
        // CP0寄存器访问接口
        .cp0_wen     (cp0_wen     ),  // O, 1 (新增)
        .cp0_wnum    (cp0_wnum    ),  // O, 5 (新增)
        .cp0_wdata   (cp0_wdata   ),  // O, 32 (新增)
        .cp0_rnum    (cp0_rnum    ),  // O, 5 (新增)
        .cp0_rdata   (cp0_rdata   ),  // I, 32 (新增)
        
        //展示PC
        .WB_pc       (WB_pc       )
    );
    
    exception EXC_module(              // 异常处理级
        .clk          (clk          ),  // I, 1
        .resetn       (resetn       ),  // I, 1
        .EXC_valid    (EXC_valid    ),  // I, 1
        .IF_ID_bus_r  (IF_ID_bus_r  ),  // I, 69 (异常发生在IF/ID阶段)
        .ID_EXE_bus_r (ID_EXE_bus_r ),  // I, 162 (异常发生在ID/EXE阶段，支持FPU)
        .EXE_MEM_bus_r(EXE_MEM_bus_r),  // I, 111 (异常发生在EXE/MEM阶段)
        .MEM_WB_bus_r (MEM_WB_bus_r ),  // I, 75 (异常发生在MEM/WB阶段)
        .cp0_status   (cp0_status   ),  // I, 32
        .cp0_cause    (cp0_cause    ),  // I, 32
        .cp0_epc      (cp0_epc      ),  // I, 32
        .int_detect   (int_detect   ),  // I, 1
        .exc_code     (exc_code     ),  // I, 5
        .EXC_over     (EXC_over     ),  // O, 1
        .EXC_bus      (EXC_bus      ),  // O, 71
        .exc_pc       (exc_pc       ),  // O, 32
        .exc_badvaddr (exc_badvaddr )   // O, 32
    );

    regfile rf_module(        // 寄存器堆模块
        .clk    (clk      ),  // I, 1
        .wen    (rf_wen   ),  // I, 1
        .raddr1 (rs       ),  // I, 5
        .raddr2 (rt       ),  // I, 5
        .waddr  (rf_wdest ),  // I, 5
        .wdata  (rf_wdata ),  // I, 32
        .rdata1 (rs_value ),  // O, 32
        .rdata2 (rt_value ),  // O, 32

        //display rf
        .test_addr(rf_addr),
        .test_data(rf_data)
    );
//--------------------------{各模块实例化}end----------------------------//
endmodule