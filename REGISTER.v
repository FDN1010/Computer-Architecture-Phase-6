module REGISTER (
    input         i_clk,
    input         i_rstn,
    input         iWriteEn,
    input  [4:0]  iRdAddr,
    input  [4:0]  iRs1Addr,
    input  [4:0]  iRs2Addr,
    input  [31:0] i_cpu_data,
    output [31:0] oRs1Data,
    output [31:0] oRs2Data
);

    reg [31:0] registers [0:31];

    integer i;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'b0;
        end else begin
            if (iWriteEn && (iRdAddr != 5'b0))
                registers[iRdAddr] <= i_cpu_data;
        end
    end

    // Write-before-read: if WB is writing the same register we're reading,
    // forward the new value directly rather than reading the stale register.
    assign oRs1Data = (iWriteEn && (iRdAddr != 5'b0) && (iRdAddr == iRs1Addr))
                      ? i_cpu_data : registers[iRs1Addr];

    assign oRs2Data = (iWriteEn && (iRdAddr != 5'b0) && (iRdAddr == iRs2Addr))
                      ? i_cpu_data : registers[iRs2Addr];

endmodule
