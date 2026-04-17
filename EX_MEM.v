`timescale 1ns/1ps

// EX_MEM.v  (Phase 6: adds iStall input for cache stall support)

module EX_MEM (
    input         iClk,
    input         iRstN,
    input         iFlush,
    input         iStall,   // freeze register when 1

    // WB
    input         iRegWrite,
    input         iMemtoReg,
    input         iJump,
    input         iLui,

    // MEM
    input         iMemRd,
    input         iMemWr,
    input  [2:0]  iFunct3,

    // Data
    input  [31:0] iAluResult,
    input  [31:0] iRs2Data,
    input  [31:0] iPCPlus4,
    input  [31:0] iImm,
    input  [4:0]  iRd,

    output reg        oRegWrite,
    output reg        oMemtoReg,
    output reg        oJump,
    output reg        oLui,

    output reg        oMemRd,
    output reg        oMemWr,
    output reg [2:0]  oFunct3,

    output reg [31:0] oAluResult,
    output reg [31:0] oRs2Data,
    output reg [31:0] oPCPlus4,
    output reg [31:0] oImm,
    output reg [4:0]  oRd
);
    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN || iFlush) begin
            oRegWrite  <= 0; oMemtoReg <= 0; oJump <= 0; oLui <= 0;
            oMemRd     <= 0; oMemWr    <= 0; oFunct3 <= 0;
            oAluResult <= 0; oRs2Data  <= 0; oPCPlus4 <= 0;
            oImm       <= 0; oRd       <= 0;
        end else if (!iStall) begin
            oRegWrite  <= iRegWrite;  oMemtoReg <= iMemtoReg;
            oJump      <= iJump;      oLui      <= iLui;
            oMemRd     <= iMemRd;     oMemWr    <= iMemWr;
            oFunct3    <= iFunct3;
            oAluResult <= iAluResult; oRs2Data  <= iRs2Data;
            oPCPlus4   <= iPCPlus4;   oImm      <= iImm;
            oRd        <= iRd;
        end
    end
endmodule
