`timescale 1ns/1ps

// MEM_WB.v  (Phase 6: adds iStall input for cache stall support)

module MEM_WB (
    input         iClk,
    input         iRstN,
    input         iStall,   // freeze register when 1

    // WB
    input         iRegWrite,
    input         iMemtoReg,
    input         iJump,
    input         iLui,

    // Data
    input  [31:0] iAluResult,
    input  [31:0] iMemReadData,
    input  [31:0] iPCPlus4,
    input  [31:0] iImm,
    input  [4:0]  iRd,

    output reg        oRegWrite,
    output reg        oMemtoReg,
    output reg        oJump,
    output reg        oLui,

    output reg [31:0] oAluResult,
    output reg [31:0] oMemReadData,
    output reg [31:0] oPCPlus4,
    output reg [31:0] oImm,
    output reg [4:0]  oRd
);
    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN) begin
            oRegWrite    <= 0; oMemtoReg    <= 0; oJump <= 0; oLui <= 0;
            oAluResult   <= 0; oMemReadData <= 0; oPCPlus4 <= 0;
            oImm         <= 0; oRd          <= 0;
        end else if (!iStall) begin
            oRegWrite    <= iRegWrite;    oMemtoReg    <= iMemtoReg;
            oJump        <= iJump;        oLui         <= iLui;
            oAluResult   <= iAluResult;   oMemReadData <= iMemReadData;
            oPCPlus4     <= iPCPlus4;     oImm         <= iImm;
            oRd          <= iRd;
        end
    end
endmodule
