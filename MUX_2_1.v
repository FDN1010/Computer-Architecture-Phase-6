module MUX_2_1 #(
    parameter WIDTH = 32
) (
    input [WIDTH-1:0] iData0,
    input [WIDTH-1:0] iData1,
    input iSel,
    output [WIDTH-1:0] oData
);
    assign oData = iSel ? iData1 : iData0;

endmodule