module HAZARD (
    input        iIDEX_MemRd,
    input [4:0]  iIDEX_Rd,
    input        iIDEX_Bubble,
    input        iEXMEM_MemRd,
    input [4:0]  iEXMEM_Rd,
    input [4:0]  iIFID_Rs1,
    input [4:0]  iIFID_Rs2,
    input [4:0]  iIDEX_Rs1,
    input [4:0]  iIDEX_Rs2,
    input        iIFID_MemWr,   // high when IF/ID holds a store instruction
    output reg   oStall,
    output reg   oIDEX_Flush
);
    always @(*) begin
        // Stall 1 cycle when a load (in ID/EX) is followed by a consumer (in IF/ID)
        // that needs the load result in the EX stage.
        //
        // Exception: a store's Rs2 is the data-to-store, which is only consumed at
        // the MEM stage.  After one stall the load is in MEM/WB and the store is in
        // EX; the existing 2'b01 MEM/WB forward path supplies the data in time.
        // Therefore we must NOT stall when the only hazard is Rs2 of a store.
        // We DO still stall if Rs1 of a store matches (Rs1 is the base address,
        // needed in EX for the address calculation).
        if (iIDEX_MemRd && (iIDEX_Rd != 5'b0) &&
            ((iIDEX_Rd == iIFID_Rs1) ||
             (iIDEX_Rd == iIFID_Rs2 && !iIFID_MemWr))) begin
            oStall      = 1'b1;
            oIDEX_Flush = 1'b1;
        end
        else begin
            oStall      = 1'b0;
            oIDEX_Flush = 1'b0;
        end
    end
endmodule
