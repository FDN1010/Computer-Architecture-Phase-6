module INSTRUCTION_MEMORY (
    input [31:0] iRdAddr,
    output [31:0] oInstr
);
    
    localparam B = 8;
    localparam K = 1024;

    reg [B-1:0] rInstrMem [0:K-1]; // 1KB instruction memory byte addressable.

    initial begin
        $readmemh("instr.txt", rInstrMem);
    end
    assign oInstr = {
            rInstrMem[iRdAddr + 3],
            rInstrMem[iRdAddr + 2],
            rInstrMem[iRdAddr + 1],
            rInstrMem[iRdAddr]
        };
endmodule
