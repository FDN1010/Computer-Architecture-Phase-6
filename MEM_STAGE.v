module MEM_STAGE (
    input         iClk,
    input         iRstN,
    input  [31:0] iAddress,
    input  [31:0] iWriteData,
    input  [2:0]  iFunct3,
    input         iMemWrite,
    input         iMemRead,
    output [31:0] oReadData
);

    DATA_MEMORY data_memory (
        .iClk      (iClk),
        .iRstN     (iRstN),
        .iAddress  (iAddress),
        .iWriteData(iWriteData),
        .iFunct3   (iFunct3),
        .iMemWrite (iMemWrite),
        .iMemRead  (iMemRead),
        .oReadData (oReadData)
    );

endmodule
