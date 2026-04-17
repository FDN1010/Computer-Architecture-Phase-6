`timescale 1ns/1ps

// DATA_CACHE.v
// Data cache wrapper: CACHE + MAIN_MEMORY (data address space).
// Supports reads and writes (write-back on hit, write-allocate on miss).

module DATA_CACHE #(
    parameter EVICT_POLICY = 0,   // 0=LRU  1=PLRU
    parameter WAYS         = 4,
    parameter CACHE_SIZE   = 4096,
    parameter BLOCK_SIZE   = 64
) (
    input  wire        i_clk,
    input  wire        i_rstn,
    input  wire [31:0] i_addr,
    input  wire [31:0] i_wdata,
    input  wire [2:0]  i_funct3,
    input  wire        i_read,
    input  wire        i_write,
    output wire [31:0] o_rdata,
    output wire        o_stall
);

localparam BLOCK_BITS = BLOCK_SIZE * 8;

// Cache <-> memory signals
wire        w_mem_rd;
wire [31:0] w_mem_rd_addr;
wire        w_mem_wr;
wire [31:0] w_mem_wr_addr;
wire [BLOCK_BITS-1:0] w_mem_wr_data;
wire [BLOCK_BITS-1:0] w_mem_data;
wire        w_mem_ready;
wire        w_mem_valid;

// Cache output signals
wire        w_hit;
wire        w_miss;
wire [31:0] w_cpu_data;

// funct3 from MEM stage: lower 2 bits used by CACHE (byte/half/word select)
wire [1:0] w_funct = i_funct3[1:0];

CACHE #(
    .EVICT_POLICY (EVICT_POLICY),
    .WAYS         (WAYS),
    .CACHE_SIZE   (CACHE_SIZE),
    .BLOCK_SIZE   (BLOCK_SIZE)
) dcache (
    .i_clk       (i_clk),
    .i_rstn      (i_rstn),
    .i_read      (i_read),
    .i_write     (i_write),
    .i_funct     (w_funct),
    .i_addr      (i_addr),
    .i_cpu_data  (i_wdata),
    .i_mem_ready (w_mem_ready),
    .i_mem_valid (w_mem_valid),
    .i_mem_data  (w_mem_data),
    .o_hit       (w_hit),
    .o_miss      (w_miss),
    .o_cpu_data  (w_cpu_data),
    .o_mem_rd    (w_mem_rd),
    .o_mem_wr    (w_mem_wr),
    .o_mem_rd_addr (w_mem_rd_addr),
    .o_mem_wr_addr (w_mem_wr_addr),
    .o_mem_rd_data (),
    .o_mem_wr_data (w_mem_wr_data)
);

// Data memory covers initialized data [0x10010000, 0x1003FFFF]
// and heap [0x10040000, ...] - use a large enough array.
MAIN_MEMORY #(
    .BLOCK_SIZE (BLOCK_SIZE),
    .MEM_BYTES  (786432),        // 768KB covers data and some heap
    .BASE_ADDR  (32'h10010000),
    .INIT_FILE  ("data.txt")
) dmem (
    .i_clk     (i_clk),
    .i_rstn    (i_rstn),
    .i_rd      (w_mem_rd),
    .i_rd_addr (w_mem_rd_addr),
    .o_rd_data (w_mem_data),
    .o_ready   (w_mem_ready),
    .o_valid   (w_mem_valid),
    .i_wr      (w_mem_wr),
    .i_wr_addr (w_mem_wr_addr),
    .i_wr_data (w_mem_wr_data)
);

// Apply ISA-correct sign extension for LB/LH.
// CACHE always zero-extends byte/half reads (funct[1:0] selects width).
// funct3[2]=0 means signed (LB/LH), funct3[2]=1 means unsigned (LBU/LHU).
reg [31:0] w_extended;
always @(*) begin
    case (i_funct3)
        3'b000:  w_extended = {{24{w_cpu_data[7]}},  w_cpu_data[7:0]};   // LB
        3'b001:  w_extended = {{16{w_cpu_data[15]}}, w_cpu_data[15:0]};  // LH
        default: w_extended = w_cpu_data;  // LW=3'b010, LBU=3'b100, LHU=3'b101
    endcase
end

assign o_rdata = w_extended;
// Stall: any read/write request that hasn't hit the cache yet
assign o_stall = (i_read || i_write) && !w_hit;

endmodule
