module blk_mem_gen_0 (
    input wire clka,        
    input wire [15:0] addra,
    input wire [31:0] dina, 
    output reg [31:0] douta,
    input wire [3:0] wea    
);

reg [31:0]mem[0:262143];

initial begin
    for(integer i=0; i<262144; i=i+1) begin
        mem[i] = 32'h0;
    end
end

always @(posedge clka) begin
    if(wea[0]) mem[addra][7:0]   <= dina[7:0];
    if(wea[1]) mem[addra][15:8]  <= dina[15:8];
    if(wea[2]) mem[addra][23:16] <= dina[23:16];
    if(wea[3]) mem[addra][31:24] <= dina[31:24];
    
    douta <= mem[addra];
end

endmodule