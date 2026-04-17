`timescale 1ns/1ps

// MAIN_MEMORY.v
// Byte-addressable memory with configurable 100-cycle read latency.
// Serves cache block reads and accepts cache write-back.

module MAIN_MEMORY #(
    parameter BLOCK_SIZE = 64,         // bytes per block
    parameter MEM_BYTES  = 1048576,    // total bytes
    parameter BASE_ADDR  = 32'h00400000,
    parameter INIT_FILE  = ""
) (
    input  wire        i_clk,
    input  wire        i_rstn,

    // Read port (from cache)
    input  wire        i_rd,
    input  wire [31:0] i_rd_addr,
    output reg  [BLOCK_SIZE*8-1:0] o_rd_data,
    output wire        o_ready,  // always 1
    output reg         o_valid,

    // Write port (cache write-back eviction)
    input  wire        i_wr,
    input  wire [31:0] i_wr_addr,
    input  wire [BLOCK_SIZE*8-1:0] i_wr_data
);

localparam PENALTY   = 100;
localparam BLOCK_BITS = BLOCK_SIZE * 8;

reg [7:0] mem [0:MEM_BYTES-1];

initial begin
    if (INIT_FILE != "")
        $readmemh(INIT_FILE, mem);
end

assign o_ready = 1'b1;

// Write-back (immediate, no penalty)
integer wi;
always @(posedge i_clk) begin
    if (i_wr) begin
        for (wi = 0; wi < BLOCK_SIZE; wi = wi + 1) begin
            if ((i_wr_addr - BASE_ADDR + wi) < MEM_BYTES)
                mem[(i_wr_addr - BASE_ADDR + wi)] <= i_wr_data[wi*8 +: 8];
        end
    end
end

// Read with PENALTY-cycle latency
reg [7:0]  r_count;
reg        r_busy;
reg [31:0] r_held_addr;
integer ri;

always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        r_count     <= 0;
        r_busy      <= 0;
        o_valid     <= 0;
        r_held_addr <= 0;
        o_rd_data   <= 0;
    end else begin
        if (!r_busy) begin
            o_valid <= 0;
            if (i_rd) begin
                r_busy      <= 1;
                r_count     <= PENALTY - 1;
                r_held_addr <= i_rd_addr;
            end
        end else begin
            if (r_count == 0) begin
                r_busy  <= 0;
                o_valid <= 1;
                for (ri = 0; ri < BLOCK_SIZE; ri = ri + 1) begin
                    if ((r_held_addr - BASE_ADDR + ri) < MEM_BYTES)
                        o_rd_data[ri*8 +: 8] <= mem[r_held_addr - BASE_ADDR + ri];
                    else
                        o_rd_data[ri*8 +: 8] <= 8'b0;
                end
            end else begin
                r_count <= r_count - 1;
                o_valid <= 0;
            end
        end
    end
end

endmodule
