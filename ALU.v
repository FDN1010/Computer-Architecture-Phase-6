module ALU (
    input [31:0] iDataA,
    input [31:0] iDataB,
    input [3:0]  iAluCtrl, //prototype from fabian was missing iAluCtrl so i readded it Andrew
    input [6:0]  iFunct7,
    output reg [31:0] oData,
    output reg oZero
);

    /* verilator lint_off UNUSED */
    wire unused_funct7 = |iFunct7;
    /* verilator lint_on UNUSED */


    // ADD / SUB shared adder
    wire [31:0] b_val;
    wire cin;

    wire force_sub;                         //Logic Fix Andrew
    assign force_sub =
        (iAluCtrl == 4'b1000) | // SUB / BEQ
        (iAluCtrl == 4'b1100) | // BNE
        (iAluCtrl == 4'b1010) | // BLT
        (iAluCtrl == 4'b1110) | // BGE
        (iAluCtrl == 4'b0010) | // SLT
        (iAluCtrl == 4'b0011);  // SLTU

    assign b_val = force_sub ? ~iDataB : iDataB;
    assign cin   = force_sub ? 1'b1    : 1'b0;


    /* verilator lint_off UNOPTFLAT */

    wire [32:0] carry_add;
    wire [31:0] add_result;

    assign carry_add[0] = cin;

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : ripple_adder
            assign add_result[i]   = iDataA[i] ^ b_val[i] ^ carry_add[i];
            assign carry_add[i+1]  = (iDataA[i] & b_val[i]) | (carry_add[i] & (iDataA[i] ^ b_val[i]));
        end
    endgenerate

    /* verilator lint_on UNOPTFLAT */

    //mark unused wires for autograder (Andrew)
    wire unused_carry_add = carry_add[32];

    //wire [32:0] carry_sub;
    //wire [31:0] sub_result;
    //wire [31:0] b_inv;

    //assign b_inv = ~iDataB;
    //assign carry_sub[0] = 1'b1;

    //generate
    //    for (i = 0; i < 32; i = i + 1) begin : sub_adder
    //        assign sub_result[i]   = iDataA[i] ^ b_inv[i] ^ carry_sub[i];
    //        assign carry_sub[i+1]  = (iDataA[i] & b_inv[i]) | (carry_sub[i] & (iDataA[i] ^ b_inv[i]));
    //    end
    //endgenerate

    // SLT / SLTU (Andrew Fix)

    wire sub_overflow;
    assign sub_overflow =
        (iDataA[31] ^ iDataB[31]) &
        (add_result[31] ^ iDataA[31]);

    wire slt_result;
    assign slt_result = sub_overflow ^ add_result[31];

    wire sltu_result;
    assign sltu_result = ~carry_add[32];

    // Shifts

    wire [4:0] shamt;
    assign shamt = iDataB[4:0];

    wire [31:0] sll_s0, sll_s1, sll_s2, sll_s3, sll_s4;
    assign sll_s0 = shamt[0] ? {iDataA[30:0], 1'b0}   : iDataA;
    assign sll_s1 = shamt[1] ? {sll_s0[29:0], 2'b0}    : sll_s0;
    assign sll_s2 = shamt[2] ? {sll_s1[27:0], 4'b0}    : sll_s1;
    assign sll_s3 = shamt[3] ? {sll_s2[23:0], 8'b0}    : sll_s2;
    assign sll_s4 = shamt[4] ? {sll_s3[15:0], 16'b0}   : sll_s3;

    wire [31:0] srl_s0, srl_s1, srl_s2, srl_s3, srl_s4;
    assign srl_s0 = shamt[0] ? {1'b0,   iDataA[31:1]}  : iDataA;
    assign srl_s1 = shamt[1] ? {2'b0,   srl_s0[31:2]}  : srl_s0;
    assign srl_s2 = shamt[2] ? {4'b0,   srl_s1[31:4]}  : srl_s1;
    assign srl_s3 = shamt[3] ? {8'b0,   srl_s2[31:8]}  : srl_s2;
    assign srl_s4 = shamt[4] ? {16'b0,  srl_s3[31:16]} : srl_s3;

    wire sign_bit;
    assign sign_bit = iDataA[31];

    wire [31:0] sra_s0, sra_s1, sra_s2, sra_s3, sra_s4;
    assign sra_s0 = shamt[0] ? {sign_bit,         iDataA[31:1]}  : iDataA;
    assign sra_s1 = shamt[1] ? {{2{sign_bit}},    sra_s0[31:2]}  : sra_s0;
    assign sra_s2 = shamt[2] ? {{4{sign_bit}},    sra_s1[31:4]}  : sra_s1;
    assign sra_s3 = shamt[3] ? {{8{sign_bit}},    sra_s2[31:8]}  : sra_s2;
    assign sra_s4 = shamt[4] ? {{16{sign_bit}},   sra_s3[31:16]} : sra_s3;

    // Logic ops

    wire [31:0] xor_result;
    assign xor_result = iDataA ^ iDataB;
    wire [31:0] or_result;
    assign or_result = iDataA | iDataB;
    wire [31:0] and_result;
    assign and_result = iDataA & iDataB;

    // Output mux (Andrew)

    always @(*) begin
        oData = 32'b0;
        oZero = 1'b0;

        case (iAluCtrl)

            4'b0000: oData = add_result;           // ADD

            4'b0001: oData = sll_s4;
            4'b1001: oData = srl_s4;
            4'b1101: oData = sra_s4;

            4'b0010: oData = {31'b0, slt_result};
            4'b0011: oData = {31'b0, sltu_result};

            4'b0100: oData = xor_result;
            4'b0110: oData = or_result;
            4'b0111: oData = and_result;

            // Branches
            4'b1100: begin // BNE
                oZero = (add_result != 32'b0);
                oData = add_result;
            end

            4'b1010: begin // BLT
                oZero = slt_result;
                oData = add_result;
            end

            4'b1110: begin // BGE
                oZero = ~slt_result;
                oData = add_result;
            end


            //SUB BEQ overlap fix
            4'b1000: begin
                oData = add_result;                 // SUB result (ignored for BEQ)
                oZero = (add_result == 32'b0);       // BEQ condition
            end

            4'b1011: begin // BLTU
                oZero = sltu_result;
                oData = add_result;
            end

            4'b1111: begin // BGEU
                oZero = ~sltu_result;
                oData = add_result;
            end

            default: begin
                oData = 32'b0;
                oZero = 1'b0;
            end
        endcase
    end


endmodule
