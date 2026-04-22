module CONTROL (
    input  [6:0] iOpcode,
    output reg   oLui,
    output reg   oPcSrc,
    output reg   oMemRd,
    output reg   oMemWr,
    output reg [2:0] oAluOp,
    output reg   oMemtoReg,
    output reg   oAluSrc1,
    output reg   oAluSrc2,
    output reg   oRegWrite,
    output reg   oBranch,
    output reg   oJump
);

    always @(*) begin
        // Default safe values
        oLui       = 1'b0;
        oPcSrc     = 1'b0;
        oMemRd     = 1'b0;
        oMemWr     = 1'b0;
        oAluOp     = 3'b000;
        oMemtoReg  = 1'b0;
        oAluSrc1   = 1'b0;
        oAluSrc2   = 1'b0;
        oRegWrite  = 1'b0;
        oBranch    = 1'b0;
        oJump      = 1'b0;

        case (iOpcode)

            // R-type (ADD, SUB, AND, OR, etc.)
            7'b0110011: begin
                oRegWrite = 1'b1;
                oAluOp    = 3'b010;
            end

            // I-type arithmetic (ADDI, ANDI, ORI, shifts)
            7'b0010011: begin
                oRegWrite = 1'b1;
                oAluOp    = 3'b011;
                oAluSrc2  = 1'b1;
            end

            // Load (LB, LH, LW, LBU, LHU)
            7'b0000011: begin
                oRegWrite = 1'b1;
                oMemRd    = 1'b1;
                oMemtoReg = 1'b1;
                oAluOp    = 3'b000;
                oAluSrc2  = 1'b1;
            end

            // Store (SB, SH, SW)
            7'b0100011: begin
                oMemWr    = 1'b1;
                oAluOp    = 3'b000;
                oAluSrc2  = 1'b1;
            end

            // Branch (BEQ, BNE, BLT, BGE, BLTU, BGEU)
            7'b1100011: begin
                oBranch   = 1'b1;
                oAluOp    = 3'b001;
            end

            // JAL jump to PC + imm, write PC+4 to rd
            // oPcSrc = 0: base address is PC (not RS1)
            7'b1101111: begin
                oJump     = 1'b1;
                oRegWrite = 1'b1;
                oPcSrc    = 1'b0;  // base = PC
            end

            // JALR jump to RS1 + imm, write PC+4 to rd
            // oPcSrc = 1: base address is RS1
            7'b1100111: begin
                oJump     = 1'b1;
                oRegWrite = 1'b1;
                oPcSrc    = 1'b1;  // base = RS1
                oAluSrc2  = 1'b1;
            end

            // LUI
            7'b0110111: begin
                oLui      = 1'b1;
                oRegWrite = 1'b1;
            end

            // AUIPC PC + upper immediate
            7'b0010111: begin
                oRegWrite = 1'b1;
                oAluSrc1  = 1'b1;  // operand1 = PC
                oAluSrc2  = 1'b1;  // operand2 = imm
                oAluOp    = 3'b000; // ADD
            end

            default: begin
                // keep defaults
            end

        endcase
    end
    
endmodule
