`timescale 1ns/1ps

// INSTRUCTION_CACHE.v
// Instruction cache wrapper: CACHE + MAIN_MEMORY (instruction address space).
// Read-only from CPU perspective.

module INSTRUCTION_CACHE #(
    parameter EVICT_POLICY = 0,   // 0=LRU  1=PLRU
    parameter WAYS         = 4,
    parameter CACHE_SIZE   = 4096,
    parameter BLOCK_SIZE   = 64
) (
    input  wire        i_clk,
    input  wire        i_rstn,
    input  wire [31:0] i_addr,
    input  wire        i_read,
    output wire [31:0] o_data,
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

CACHE #(
    .EVICT_POLICY (EVICT_POLICY),
    .WAYS         (WAYS),
    .CACHE_SIZE   (CACHE_SIZE),
    .BLOCK_SIZE   (BLOCK_SIZE)
) icache (
    .i_clk       (i_clk),
    .i_rstn      (i_rstn),
    .i_read      (i_read),
    .i_write     (1'b0),
    .i_funct     (2'b10),
    .i_addr      (i_addr),
    .i_cpu_data  (32'b0),
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

MAIN_MEMORY #(
    .BLOCK_SIZE (BLOCK_SIZE),
    .MEM_BYTES  (12582912),      // 12MB covers [0x00400000, 0x00FFFFFF]
    .BASE_ADDR  (32'h00400000),
    .INIT_FILE  ("instr.txt")
) imem (
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

assign o_data  = w_cpu_data;
// Stall until CACHE.o_hit=1 (only asserted in S_IDLE with tag match).
// CACHE.o_hit is 0 in S_MISS and S_PREFETCH, so stall covers entire miss+prefetch sequence.
assign o_stall = i_read && !w_hit;

endmodule
