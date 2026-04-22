module FORWARDING (
    input [4:0]  iEX_Rs1,
    input [4:0]  iEX_Rs2,

    // From EX/MEM
    input        iEXMEM_RegWrite,
    input        iEXMEM_MemRd,    // if set, EX/MEM holds a load; forward from MEM output
    input [4:0]  iEXMEM_Rd,

    // From MEM/WB
    input        iMEMWB_RegWrite,
    input [4:0]  iMEMWB_Rd,

    // 00=register file, 01=MEM/WB, 10=EX/MEM ALU result, 11=MEM stage load data
    output reg [1:0] oForwardA,
    output reg [1:0] oForwardB
);
    always @(*) begin
        // Forward A
        if (iEXMEM_RegWrite && !iEXMEM_MemRd &&
            (iEXMEM_Rd != 5'b0) && (iEXMEM_Rd == iEX_Rs1))
            oForwardA = 2'b10;          // EX/MEM ALU result
        else if (iEXMEM_RegWrite && iEXMEM_MemRd &&
            (iEXMEM_Rd != 5'b0) && (iEXMEM_Rd == iEX_Rs1))
            oForwardA = 2'b11;          // MEM stage load data (after 1-cycle stall)
        else if (iMEMWB_RegWrite &&
            (iMEMWB_Rd != 5'b0) && (iMEMWB_Rd == iEX_Rs1))
            oForwardA = 2'b01;
        else
            oForwardA = 2'b00;

        // Forward B
        if (iEXMEM_RegWrite && !iEXMEM_MemRd &&
            (iEXMEM_Rd != 5'b0) && (iEXMEM_Rd == iEX_Rs2))
            oForwardB = 2'b10;          // EX/MEM ALU result
        else if (iEXMEM_RegWrite && iEXMEM_MemRd &&
            (iEXMEM_Rd != 5'b0) && (iEXMEM_Rd == iEX_Rs2))
            oForwardB = 2'b11;          // MEM stage load data (after 1-cycle stall)
        else if (iMEMWB_RegWrite &&
            (iMEMWB_Rd != 5'b0) && (iMEMWB_Rd == iEX_Rs2))
            oForwardB = 2'b01;
        else
            oForwardB = 2'b00;
    end
endmodule
