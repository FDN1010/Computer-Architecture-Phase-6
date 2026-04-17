// CACHE_TB.v  
// Stimulus-driven testbench for CACHE.v.
// Timing: apply inputs at negedge, sample combinational outputs #1 later
// (before next posedge), then the posedge advances registers.
//
// Stimulus file: one line per cycle
//   cycle read write funct addr_hex cpu_data_hex ready valid mem_data_hex
// where mem_data_hex is always 512 bits (padded), lower BLOCK_BITS used.
//
// Output file (CSV): cycle,o_hit,o_miss,o_cpu_data,o_mem_rd,o_mem_wr,o_mem_rd_addr

`timescale 1ns/1ps

module CACHE_TB;

parameter EVICT_POLICY = 0;
parameter WAYS         = 4;
parameter CACHE_SIZE   = 32;
parameter BLOCK_SIZE   = 8;

localparam BLOCK_BITS = BLOCK_SIZE * 8;

// =========================================================
// DUT signals
// =========================================================
reg         clk, rstn;
reg         i_read, i_write;
reg  [1:0]  i_funct;
reg  [31:0] i_addr, i_cpu_data;
reg         i_mem_ready, i_mem_valid;
reg  [BLOCK_BITS-1:0] i_mem_data;

wire        o_hit, o_miss;
wire [31:0] o_cpu_data;
wire        o_mem_rd, o_mem_wr;
wire [31:0] o_mem_rd_addr, o_mem_wr_addr;
wire [BLOCK_BITS-1:0] o_mem_rd_data, o_mem_wr_data;

CACHE #(
    .EVICT_POLICY(EVICT_POLICY),
    .WAYS        (WAYS),
    .CACHE_SIZE  (CACHE_SIZE),
    .BLOCK_SIZE  (BLOCK_SIZE)
) dut (
    .i_clk      (clk),       .i_rstn     (rstn),
    .i_read     (i_read),    .i_write    (i_write),
    .i_funct    (i_funct),   .i_addr     (i_addr),
    .i_cpu_data (i_cpu_data),
    .i_mem_ready(i_mem_ready),.i_mem_valid(i_mem_valid),
    .i_mem_data (i_mem_data),
    .o_hit      (o_hit),     .o_miss     (o_miss),
    .o_cpu_data (o_cpu_data),
    .o_mem_rd   (o_mem_rd),  .o_mem_wr   (o_mem_wr),
    .o_mem_rd_addr(o_mem_rd_addr),
    .o_mem_wr_addr(o_mem_wr_addr),
    .o_mem_rd_data(o_mem_rd_data),
    .o_mem_wr_data(o_mem_wr_data)
);

// =========================================================
// Clock: 10 ns period, posedge at 5, 15, 25 ...
// =========================================================
initial clk = 0;
always  #5 clk = ~clk;

// =========================================================
// Main
// =========================================================
integer stim_fd, out_fd, r, k, cyc_in;
integer in_read, in_write, in_funct;
integer in_addr, in_cpu_data, in_ready, in_valid;
reg [511:0] in_wide;
integer n_cycles;
reg [1023:0] stim_file, out_file;

initial begin
    // Plusarg configuration
    if (!$value$plusargs("stim=%s",   stim_file))  $finish;
    if (!$value$plusargs("out=%s",    out_file))   $finish;
    if (!$value$plusargs("ncycles=%d", n_cycles))  n_cycles = 100000;

    stim_fd = $fopen(stim_file, "r");
    if (stim_fd == 0) begin $display("ERR: stim %s", stim_file); $finish; end

    out_fd = $fopen(out_file, "w");
    if (out_fd == 0) begin $display("ERR: out %s", out_file); $finish; end

    $fwrite(out_fd, "cycle,o_hit,o_miss,o_cpu_data,o_mem_rd,o_mem_wr,o_mem_rd_addr\n");

    // Initialise + reset
    rstn = 0; i_read = 0; i_write = 0; i_funct = 0;
    i_addr = 0; i_cpu_data = 0;
    i_mem_ready = 0; i_mem_valid = 0; i_mem_data = 0;

    // Hold reset for two posedges
    @(negedge clk);
    @(negedge clk);
    rstn = 1;

    for (k = 0; k < n_cycles; k = k + 1) begin
        // ── At negedge: apply inputs ──────────────────────────
        r = $fscanf(stim_fd, "%h %h %h %h %h %h %h %h %h\n",
                    cyc_in, in_read, in_write, in_funct,
                    in_addr, in_cpu_data, in_ready, in_valid,
                    in_wide);
        if (r < 9) begin
            k = n_cycles;  // done
        end else begin
            i_read      = in_read[0];
            i_write     = in_write[0];
            i_funct     = in_funct[1:0];
            i_addr      = in_addr;
            i_cpu_data  = in_cpu_data;
            i_mem_ready = in_ready[0];
            i_mem_valid = in_valid[0];
            i_mem_data  = in_wide[BLOCK_BITS-1:0];

            // ── Let combinational settle, THEN sample ────────
            #2;
            $fwrite(out_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                    cyc_in,
                    o_hit, o_miss, o_cpu_data,
                    o_mem_rd, o_mem_wr, o_mem_rd_addr);

            // ── Wait for next negedge (posedge happens between) ──
            @(negedge clk);
        end
    end

    $fclose(stim_fd);
    $fclose(out_fd);
    $finish;
end

endmodule
