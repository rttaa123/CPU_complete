`default_nettype none

//`include "riscv_defines.vh"
module tag_ram #(
    parameter TAG_RAM_ADDR_WIDTH = 6,//地址宽度
    parameter TAG_WIDTH = 20,
    parameter PAYLOAD_WIDTH = 32
) (
    input wire clk,//时钟
    input wire resetn,//复位信号,低电平有效
    input wire [TAG_RAM_ADDR_WIDTH -1:0] idx, //组号
    input wire [TAG_WIDTH -1:0] tag,//存储
    input wire [PAYLOAD_WIDTH -1:0] payload_i,  //pte
    input wire we,//写入有效位
    input wire valid_i,//操作有效
    output reg hit_o, //命中
    output reg [PAYLOAD_WIDTH -1:0] payload_o //输出数据, 未命中输出0
);
  localparam LINES = 2 ** TAG_RAM_ADDR_WIDTH;
  localparam WAYS = 2; //二路组相联
  reg [TAG_WIDTH-1:0] tags[0:LINES-1][0:WAYS-1];   //标签位      
  reg [PAYLOAD_WIDTH-1:0] payloads[0:LINES-1][0:WAYS-1]; //存储实际数据
  reg v[0:LINES-1][0:WAYS-1];   //有效位

  reg lru[0:LINES-1]; //LRU替换算法. 每组记录一个为0表示最近使用过第0路, 为1表示最近使用过第1路

  integer i;
  //判断当前访问是否命中
  always @(*) begin
    /* verilator lint_off WIDTHTRUNC */
    // hit_o = (tag == tags[idx]) && v[idx];
    // payload_o = hit_o ? payloads[idx] : 0;
    /* verilator lint_on WIDTHTRUNC */

    hit_o = 0;
    payload_o = 0;

    //组内遍历
    for(i = 0; i < WAYS; i = i+1) begin
      if(v[idx][i] && (tags[idx][i] == tag)) begin
        hit_o = 1;
        payload_o = payloads[idx][i];
      end
    end
  end

  always @(posedge clk) begin
    /*复位*/
    if (!resetn) begin
      // v <= 0;
      for(i = 0; i < WAYS; i = i+1) begin
        v[idx][i] <= 0;
      end
      lru[idx] <= 0;
    end
    /*更新lru*/
    else begin
      if(v[idx][0] && (tags[idx][0] == tag)) begin
        lru[idx] <= 0;
      end
      else if(v[idx][1] && (tags[idx][1] == tag)) begin
        lru[idx] <= 1;
      end
      /*写入逻辑*/
      if(valid_i && we) begin
        if(!v[idx][0]) begin
          tags[idx][0] <= tag;
          payloads[idx][0] <= payload_i;
          v[idx][0] <= 1;
          lru[idx] <= 0;
        end
        else if(!v[idx][1]) begin
          tags[idx][1] <= tag;
          payloads[idx][1] <= payload_i;
          v[idx][1] <= 1;
          lru[idx] <= 1;
        end
        /*若两路都被写入, 则进入LRU替换逻辑*/
        else begin
          if(lru[idx] == 0) begin
            tags[idx][1] <= tag;
            payloads[idx][1] <= payload_i;
            v[idx][1] <= 1;
            lru[idx] <= 1;
          end
          else begin
            tags[idx][0] <= tag;
            payloads[idx][0] <= payload_i;
            v[idx][0] <= 1;
            lru[idx] <= 0;
          end
        end
      end
    end
    // else begin
    //   if (valid_i) begin
    //     if (we) begin
    //       /* verilator lint_off WIDTHTRUNC */
    //       tags[idx] <= tag;
    //       payloads[idx] <= payload_i;
    //       v[idx] <= 1'b1;
    //       /* verilator lint_on WIDTHTRUNC */
    //     end
    //   end
    // end
  end
endmodule

