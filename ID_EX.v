module ID_EX (
    input         iClk,
    input         iRstN,
    input         iFlush,
    input         iStall,

    // WB controls
    input         iRegWrite,
    input         iMemtoReg,
    input         iJump,
    input         iLui,

    // MEM controls
    input         iMemRd,
    input         iMemWr,
    input  [2:0]  iFunct3,

    // EX controls
    input  [2:0]  iAluOp,
    input         iAluSrc1,
    input         iAluSrc2,
    input         iBranch,
    input         iPcSrc,

    // Data
    input  [31:0] iPC,
    input  [31:0] iRs1Data,
    input  [31:0] iRs2Data,
    input  [31:0] iImm,
    input  [6:0]  iFunct7,
    input  [4:0]  iRs1,
    input  [4:0]  iRs2,
    input  [4:0]  iRd,

    // Outputs
    output reg        oRegWrite,
    output reg        oMemtoReg,
    output reg        oJump,
    output reg        oLui,

    output reg        oMemRd,
    output reg        oMemWr,
    output reg [2:0]  oFunct3,

    output reg [2:0]  oAluOp,
    output reg        oAluSrc1,
    output reg        oAluSrc2,
    output reg        oBranch,
    output reg        oPcSrc,

    output reg [31:0] oPC,
    output reg [31:0] oRs1Data,
    output reg [31:0] oRs2Data,
    output reg [31:0] oImm,
    output reg [6:0]  oFunct7,
    output reg [4:0]  oRs1,
    output reg [4:0]  oRs2,
    output reg [4:0]  oRd
);
    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN || iFlush || iStall) begin
            oRegWrite <= 0; oMemtoReg <= 0; oJump <= 0; oLui <= 0;
            oMemRd    <= 0; oMemWr    <= 0; oFunct3 <= 0;
            oAluOp    <= 0; oAluSrc1  <= 0; oAluSrc2 <= 0;
            oBranch   <= 0; oPcSrc    <= 0;
            oPC       <= 0; oRs1Data  <= 0; oRs2Data <= 0;
            oImm      <= 0; oFunct7   <= 0;
            oRs1      <= 0; oRs2      <= 0; oRd <= 0;
        end else begin
            oRegWrite <= iRegWrite; oMemtoReg <= iMemtoReg;
            oJump     <= iJump;     oLui      <= iLui;
            oMemRd    <= iMemRd;    oMemWr    <= iMemWr;
            oFunct3   <= iFunct3;
            oAluOp    <= iAluOp;    oAluSrc1  <= iAluSrc1;
            oAluSrc2  <= iAluSrc2;  oBranch   <= iBranch;
            oPcSrc    <= iPcSrc;
            oPC       <= iPC;       oRs1Data  <= iRs1Data;
            oRs2Data  <= iRs2Data;  oImm      <= iImm;
            oFunct7   <= iFunct7;
            oRs1      <= iRs1;      oRs2      <= iRs2;
            oRd       <= iRd;
        end
    end
endmodule
