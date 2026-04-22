module MEM_WB (
    input         i_clk,
    input         i_rstn,

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
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            oRegWrite    <= 0; oMemtoReg    <= 0; oJump <= 0; oLui <= 0;
            oAluResult   <= 0; oMemReadData <= 0; oPCPlus4 <= 0;
            oImm         <= 0; oRd          <= 0;
        end else begin
            oRegWrite    <= iRegWrite;    oMemtoReg    <= iMemtoReg;
            oJump        <= iJump;        oLui         <= iLui;
            oAluResult   <= iAluResult;   oMemReadData <= iMemReadData;
            oPCPlus4     <= iPCPlus4;     oImm         <= iImm;
            oRd          <= iRd;
        end
    end
endmodule
