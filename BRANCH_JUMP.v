module BRANCH_JUMP (
    input iBranch,
    input iJump,
    input iZero,
    input [31:0] iOffset,
    input [31:0] iPc,
    input [31:0] iRs1,
    input iPcSrc,
    output [31:0] oPc
);
    // PC+4 always computed
    wire [31:0] pc_plus4;
    assign pc_plus4 = iPc + 32'd4;

    // JAL:  target = PC   + offset
    // JALR: target = RS1  + offset, LSB cleared to 0
    wire [31:0] base_addr;
    assign base_addr = iPcSrc ? iRs1 : iPc;

    wire [31:0] jump_target_raw;
    assign jump_target_raw = base_addr + iOffset;

    // JALR requires LSB = 0; JAL target is always aligned so masking is safe for both
    wire [31:0] jump_target;
    assign jump_target = {jump_target_raw[31:1], 1'b0};

    // Branch target always PC-relative
    wire [31:0] branch_target;
    assign branch_target = iPc + iOffset;

    wire take_branch;
    assign take_branch = iBranch & iZero;

    // Priority: jump > branch > sequential
    assign oPc = iJump       ? jump_target   :
                 take_branch ? branch_target :
                               pc_plus4;

endmodule
