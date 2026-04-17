module DECODER (
    input [31:0] iInstr,

    output [6:0] oOpcode,
    output [4:0] oRd,
    output [2:0] oFunct3,
    output [4:0] oRs1,
    output [4:0] oRs2,
    output [6:0] oFunct7,
    output [31:0] oImm
);

    assign oOpcode = iInstr[6:0];
    assign oRd     = iInstr[11:7];
    assign oFunct3 = iInstr[14:12];
    assign oRs1    = iInstr[19:15];
    assign oRs2    = iInstr[24:20];
    assign oFunct7 = iInstr[31:25];

    wire [31:0] imm_I, imm_S, imm_B, imm_U, imm_J;

    assign imm_I = {{20{iInstr[31]}}, iInstr[31:20]};

    assign imm_S = {{20{iInstr[31]}}, iInstr[31:25], iInstr[11:7]};

    assign imm_B = {{19{iInstr[31]}}, iInstr[31], iInstr[7], iInstr[30:25], iInstr[11:8], 1'b0};

    assign imm_U = {iInstr[31:12], 12'b0};

    assign imm_J = {{11{iInstr[31]}}, iInstr[31], iInstr[19:12], iInstr[20], iInstr[30:21], 1'b0};

    reg [31:0] imm_out;

    always @(*) begin
        case (oOpcode)
            7'b0110011: imm_out = 32'b0;           // R-type
            7'b0010011: imm_out = imm_I;            // I-type (arithmetic imm)
            7'b0000011: imm_out = imm_I;            // I-type (load)
            7'b1100111: imm_out = imm_I;            // I-type (JALR)
            7'b0100011: imm_out = imm_S;            // S-type (store)
            7'b1100011: imm_out = imm_B;            // B-type (branch)
            7'b0110111: imm_out = imm_U;            // U-type (LUI)
            7'b0010111: imm_out = imm_U;            // U-type (AUIPC)
            7'b1101111: imm_out = imm_J;            // J-type (JAL)
            7'b1110011: imm_out = 32'b0;            // I-type (SYSTEM) //set to imm_I instead of 32'b0 (Andrew bugfix)
            default:    imm_out = 32'b0;
        endcase
    end

    assign oImm = imm_out;

endmodule
