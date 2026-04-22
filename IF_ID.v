module IF_ID (
    input         i_clk,
    input         i_rstn,
    input         iFlush,
    input         iStall,
    input  [31:0] iPC,
    input  [31:0] iInstr,
    output reg [31:0] oPC,
    output reg [31:0] oInstr
);
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn || iFlush) begin
            oPC    <= 32'b0;
            oInstr <= 32'b0;
        end else if (!iStall) begin
            oPC    <= iPC;
            oInstr <= iInstr;
        end
    end
endmodule
