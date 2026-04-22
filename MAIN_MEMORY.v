// MAIN_MEMORY.v
// Unified main memory backing both instruction and data caches.
// Byte-addressable. Initialised from instr.txt (instructions) and
// data.txt (data) via $readmemh.
//
// Address map (matches Phase 6 spec):
//   Instructions : 0x00400000 – 0x0FFFFFFF  (loaded from instr.txt)
//   Init data    : 0x10010000 – 0x1003FFFF  (loaded from data.txt)
//
// The cache hands us a full 32-bit byte address.  We translate it to
// an internal array index so both regions fit in a reasonably-sized
// simulation array.
//
// Internal layout (flat byte array):
//   [0          … INSTR_SIZE-1]  ← instruction region
//   [INSTR_SIZE … INSTR_SIZE+DATA_SIZE-1] ← data region
//
// Block-level interface: the cache requests/returns BLOCK_SIZE bytes
// at a time so we never have to loop outside this module.

module MAIN_MEMORY #(
    parameter BLOCK_SIZE  = 64,          // bytes per cache block
    parameter INSTR_SIZE  = 65536,       // bytes reserved for instructions (64 KB)
    parameter DATA_SIZE   = 196608       // bytes reserved for data        (192 KB)
)(
    input                        i_clk,
    input                        i_rstn,

    // Port A – instruction cache
    input  [31:0]                iInstrAddr,      // byte address
    input                        iInstrReq,       // cache is requesting a block
    output reg [BLOCK_SIZE*8-1:0] oInstrBlock,    // block returned to i-cache
    output reg                   oInstrReady,     // block is valid this cycle

    // Port B – data cache
    input  [31:0]                iDataAddr,       // byte address
    input                        iDataReq,        // cache requesting a block (read or write-back)
    input                        iDataWrite,      // 1 = write block back to memory
    input  [BLOCK_SIZE*8-1:0]    iDataBlock,      // block to write (write-back)
    output reg [BLOCK_SIZE*8-1:0] oDataBlock,     // block returned to d-cache
    output reg                   oDataReady       // block is valid this cycle
);

    // ----------------------------------------------------------------
    // Internal byte arrays
    // ----------------------------------------------------------------
    reg [7:0] rInstrMem [0:INSTR_SIZE-1];
    reg [7:0] rDataMem  [0:DATA_SIZE-1];

    initial begin
        $readmemh("instr.txt", rInstrMem);
        $readmemh("data.txt",  rDataMem);
    end

    // ----------------------------------------------------------------
    // Address translation helpers
    // ----------------------------------------------------------------
    localparam [31:0] INSTR_BASE = 32'h00400000;
    localparam [31:0] DATA_BASE  = 32'h10010000;

    // Align address down to block boundary
    function [31:0] block_base;
        input [31:0] addr;
        begin
            block_base = addr & ~(BLOCK_SIZE - 1);
        end
    endfunction

    // ----------------------------------------------------------------
    // Instruction port – combinational read, 1-cycle registered output
    // (the cache drives oInstrReady the cycle after it asserts iInstrReq)
    // ----------------------------------------------------------------
    integer ib;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            oInstrBlock <= 0;
            oInstrReady <= 1'b0;
        end else begin
            oInstrReady <= 1'b0;
            if (iInstrReq) begin
                // read BLOCK_SIZE bytes from instruction array
                begin : instr_read_block
                    reg [31:0] base;
                    reg [31:0] idx;
                    base = block_base(iInstrAddr) - INSTR_BASE;
                    for (ib = 0; ib < BLOCK_SIZE; ib = ib + 1) begin
                        idx = base + ib;
                        if (idx < INSTR_SIZE)
                            oInstrBlock[ib*8 +: 8] <= rInstrMem[idx];
                        else
                            oInstrBlock[ib*8 +: 8] <= 8'h0;
                    end
                end
                oInstrReady <= 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // Data port – combinational read / synchronous write-back
    // ----------------------------------------------------------------
    integer db;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            oDataBlock <= 0;
            oDataReady <= 1'b0;
        end else begin
            oDataReady <= 1'b0;
            if (iDataReq) begin
                begin : data_block_op
                    reg [31:0] base;
                    reg [31:0] idx;
                    base = block_base(iDataAddr) - DATA_BASE;
                    if (iDataWrite) begin
                        // Write-back: store block bytes into data array
                        for (db = 0; db < BLOCK_SIZE; db = db + 1) begin
                            idx = base + db;
                            if (idx < DATA_SIZE)
                                rDataMem[idx] <= iDataBlock[db*8 +: 8];
                        end
                    end else begin
                        // Read: fetch block from data array
                        for (db = 0; db < BLOCK_SIZE; db = db + 1) begin
                            idx = base + db;
                            if (idx < DATA_SIZE)
                                oDataBlock[db*8 +: 8] <= rDataMem[idx];
                            else
                                oDataBlock[db*8 +: 8] <= 8'h0;
                        end
                    end
                end
                oDataReady <= 1'b1;
            end
        end
    end

endmodule
