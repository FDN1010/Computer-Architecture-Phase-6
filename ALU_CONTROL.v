module ALU_CONTROL (
    input [2:0] iAluOp,
    input [2:0] i_funct,
    input [6:0] iFunct7,
    output [3:0] oAluCtrl
);

    // ALU operation
    localparam ADD  = 4'b0000;
    localparam SUB  = 4'b1000;
    localparam SLL  = 4'b0001;
    localparam SRL  = 4'b1001;
    localparam SRA  = 4'b1101;
    localparam SLT  = 4'b0010;
    localparam SLTU = 4'b0011;
    localparam XOR  = 4'b0100;
    localparam OR   = 4'b0110;
    localparam AND  = 4'b0111;
    localparam BEQ  = 4'b1000;
    localparam BNE  = 4'b1100;
    localparam BLT  = 4'b1010;
    localparam BGE  = 4'b1110;
    localparam BLTU = 4'b1011;
    localparam BGEU = 4'b1111;

    reg [3:0] aluCtrl;
    assign oAluCtrl = aluCtrl;

    always @(*) begin
        case (iAluOp)
            // Load/Store: always ADD
            3'b000: aluCtrl = ADD;

            // Branch: decode funct3
            3'b001: begin
                case (i_funct)
                    3'b000: aluCtrl = BEQ;
                    3'b001: aluCtrl = BNE;
                    3'b100: aluCtrl = BLT;
                    3'b101: aluCtrl = BGE;
                    3'b110: aluCtrl = BLTU;
                    3'b111: aluCtrl = BGEU;
                    default: aluCtrl = BEQ;
                endcase
            end

            // R-type: decode funct3 + funct7
            3'b010: begin
                case (i_funct)
                    3'b000: aluCtrl = (iFunct7[5]) ? SUB : ADD;
                    3'b001: aluCtrl = SLL;
                    3'b010: aluCtrl = SLT;
                    3'b011: aluCtrl = SLTU;
                    3'b100: aluCtrl = XOR;
                    3'b101: aluCtrl = (iFunct7[5]) ? SRA : SRL;
                    3'b110: aluCtrl = OR;
                    3'b111: aluCtrl = AND;
                    default: aluCtrl = ADD;
                endcase
            end

            // I-type arithmetic: decode funct3
            3'b011: begin
                case (i_funct)
                    3'b000: aluCtrl = ADD;   // ADDI
                    3'b001: aluCtrl = SLL;   // SLLI
                    3'b010: aluCtrl = SLT;   // SLTI
                    3'b011: aluCtrl = SLTU;  // SLTIU
                    3'b100: aluCtrl = XOR;   // XORI
                    3'b101: aluCtrl = (iFunct7[5]) ? SRA : SRL; // SRAI/SRLI
                    3'b110: aluCtrl = OR;    // ORI
                    3'b111: aluCtrl = AND;   // ANDI
                    default: aluCtrl = ADD;
                endcase
            end

            // AUIPC: ADD (PC + imm)
            3'b100: aluCtrl = ADD;

            default: aluCtrl = ADD;
        endcase
    end

endmodule
