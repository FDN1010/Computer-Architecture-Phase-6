module MEM_STAGE (
    input         i_clk,
    input         i_rstn,
    input  [31:0] iAddress,
    input  [31:0] i_cpu_data,
    input  [2:0]  i_funct,
    input         i_write,
    input         i_read,
    output [31:0] o_cpu_data
);

    DATA_MEMORY data_memory (
        .i_clk      (i_clk),
        .i_rstn     (i_rstn),
        .iAddress  (iAddress),
        .i_cpu_data(i_cpu_data),
        .i_funct   (i_funct),
        .i_write (i_write),
        .i_read  (i_read),
        .o_cpu_data (o_cpu_data)
    );

endmodule
