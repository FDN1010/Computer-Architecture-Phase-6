module IF_ID (
    input         iClk,
    input         iRstN,
    input         iFlush,
    input         iStall,
    input  [31:0] iPC,
    input  [31:0] iInstr,
    output reg [31:0] oPC,
    output reg [31:0] oInstr
);
    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN || iFlush) begin
            oPC    <= 32'b0;
            oInstr <= 32'b0;
        end else if (!iStall) begin
            oPC    <= iPC;
            oInstr <= iInstr;
        end
    end
endmodule
