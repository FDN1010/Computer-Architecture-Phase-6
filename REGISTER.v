module REGISTER (
    input         iClk,
    input         iRstN,
    input         iWriteEn,
    input  [4:0]  iRdAddr,
    input  [4:0]  iRs1Addr,
    input  [4:0]  iRs2Addr,
    input  [31:0] iWriteData,
    output [31:0] oRs1Data,
    output [31:0] oRs2Data
);

    reg [31:0] registers [0:31];

    integer i;

    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'b0;
        end else begin
            if (iWriteEn && (iRdAddr != 5'b0))
                registers[iRdAddr] <= iWriteData;
        end
    end

    // Write-before-read: if WB is writing the same register we're reading,
    // forward the new value directly rather than reading the stale register.
    assign oRs1Data = (iWriteEn && (iRdAddr != 5'b0) && (iRdAddr == iRs1Addr))
                      ? iWriteData : registers[iRs1Addr];

    assign oRs2Data = (iWriteEn && (iRdAddr != 5'b0) && (iRdAddr == iRs2Addr))
                      ? iWriteData : registers[iRs2Addr];

endmodule
