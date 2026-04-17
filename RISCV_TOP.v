`timescale 1ns/1ps

// RISCV_TOP.v  (Phase 6 - with Instruction Cache and Data Cache)
// Extends Phase 5 forwarded pipeline with cache-backed memory:
//   - INSTRUCTION_CACHE replaces INSTRUCTION_MEMORY
//   - DATA_CACHE replaces DATA_MEMORY / MEM_STAGE
//   - Pipeline stalls on any cache miss

module RISCV_TOP (
    input iClk,
    input iRstN
);

// =============================================================
// STALL / FLUSH signals
// =============================================================
wire wHazardStall;     // load-use stall from hazard unit
wire wIDEX_Bubble;     // hazard unit bubble into ID/EX
wire wFlush;           // branch/jump flush from EX stage (1-cycle penalty)

wire wICStall;         // instruction cache miss stall
wire wDCStall;         // data cache miss stall
wire wCacheStall;      // any cache miss stall
wire wTotalStall;      // combined: hazard + any cache miss

assign wCacheStall = wICStall | wDCStall;
assign wTotalStall = wHazardStall | wCacheStall;

// Forward declarations used by HAZARD and FORWARDING (outputs of later modules)
wire        wEXMEM_RegWrite;
wire [4:0]  wEXMEM_Rd;
wire        wEXMEM_MemRd;
wire        wMEMWB_RegWrite;
wire [4:0]  wMEMWB_Rd;
wire [31:0] wEXMEM_AluResult;
wire [4:0]  wIDEX_Rs1;
wire [4:0]  wIDEX_Rs2;

// =============================================================
// IF STAGE   Program Counter
// =============================================================
reg  [31:0] wPC;
wire [31:0] wNextPC;
wire [31:0] wPCPlus4_IF;
wire [31:0] wInstr_raw;

assign wPCPlus4_IF = wPC + 32'd4;

always @(posedge iClk or negedge iRstN) begin
    if (!iRstN)
        wPC <= 32'h00400000;
    else if (!wTotalStall)
        wPC <= wNextPC;
end

// Instruction cache: read every cycle with current PC
wire        wICStall_raw;

INSTRUCTION_CACHE #(
    .EVICT_POLICY (0),
    .WAYS         (4),
    .CACHE_SIZE   (4096),
    .BLOCK_SIZE   (64)
) instruction_cache (
    .i_clk   (iClk),
    .i_rstn  (iRstN),
    .i_addr  (wPC),
    .i_read  (1'b1),
    .o_data  (wInstr_raw),
    .o_stall (wICStall_raw)
);

assign wICStall = wICStall_raw;

// =============================================================
// IF/ID Pipeline Register
// =============================================================
reg [31:0] wInstr;
reg [31:0] wPc;

always @(posedge iClk or negedge iRstN) begin
    if (!iRstN || wFlush) begin
        wInstr <= 32'h00000013;
        wPc    <= 32'b0;
    end else if (!wTotalStall) begin
        wInstr <= wInstr_raw;
        wPc    <= wPC;
    end
end

// =============================================================
// ID STAGE   Decode + Register Read
// =============================================================
wire [6:0]  wOpcode;
wire [4:0]  wRd_ID;
wire [2:0]  wFunct3_ID;
wire [4:0]  wRs1_ID;
wire [4:0]  wRs2_ID;
wire [6:0]  wFunct7_ID;
wire [31:0] wImm_ID;

DECODER id_stage (
    .iInstr  (wInstr),
    .oOpcode (wOpcode),
    .oRd     (wRd_ID),
    .oFunct3 (wFunct3_ID),
    .oRs1    (wRs1_ID),
    .oRs2    (wRs2_ID),
    .oFunct7 (wFunct7_ID),
    .oImm    (wImm_ID)
);

wire        wCtrl_Lui, wCtrl_PcSrc, wCtrl_MemRd, wCtrl_MemWr;
wire [2:0]  wCtrl_AluOp;
wire        wCtrl_MemtoReg, wCtrl_AluSrc1, wCtrl_AluSrc2;
wire        wCtrl_RegWrite, wCtrl_Branch, wCtrl_Jump;

CONTROL control (
    .iOpcode   (wOpcode),
    .oLui      (wCtrl_Lui),
    .oPcSrc    (wCtrl_PcSrc),
    .oMemRd    (wCtrl_MemRd),
    .oMemWr    (wCtrl_MemWr),
    .oAluOp    (wCtrl_AluOp),
    .oMemtoReg (wCtrl_MemtoReg),
    .oAluSrc1  (wCtrl_AluSrc1),
    .oAluSrc2  (wCtrl_AluSrc2),
    .oRegWrite (wCtrl_RegWrite),
    .oBranch   (wCtrl_Branch),
    .oJump     (wCtrl_Jump)
);

// WB writeback (driven later)
wire [31:0] wWbData;
wire [4:0]  wWbRd;
wire        wWbRegWrite;

wire [31:0] wRs1Data_ID;
wire [31:0] wRs2Data_ID;

REGISTER register (
    .iClk       (iClk),
    .iRstN      (iRstN),
    .iWriteEn   (wWbRegWrite),
    .iRdAddr    (wWbRd),
    .iRs1Addr   (wRs1_ID),
    .iRs2Addr   (wRs2_ID),
    .iWriteData (wWbData),
    .oRs1Data   (wRs1Data_ID),
    .oRs2Data   (wRs2Data_ID)
);

// =============================================================
// Hazard Detection Unit  (load-use stall)
// =============================================================
wire [4:0] wIDEX_Rd;
wire       wIDEX_MemRd;

// Track whether ID/EX is a bubble
wire wIDEX_IsBubble = !wIDEX_RegWrite && !wIDEX_MemRd && !wIDEX_MemWr &&
                      !wIDEX_Branch && !wIDEX_Jump;

HAZARD hd (
    .iIDEX_MemRd   (wIDEX_MemRd),
    .iIDEX_Rd      (wIDEX_Rd),
    .iIDEX_Bubble  (wIDEX_IsBubble),
    .iEXMEM_MemRd  (wEXMEM_MemRd),
    .iEXMEM_Rd     (wEXMEM_Rd),
    .iIFID_Rs1     (wRs1_ID),
    .iIFID_Rs2     (wRs2_ID),
    .iIDEX_Rs1     (wIDEX_Rs1),
    .iIDEX_Rs2     (wIDEX_Rs2),
    .iIFID_MemWr   (wCtrl_MemWr),
    .oStall        (wHazardStall),
    .oIDEX_Flush   (wIDEX_Bubble)
);

// ID/EX flush = load-use bubble OR branch/jump flush
wire wIDEX_Flush = wIDEX_Bubble | wFlush;

// =============================================================
// ID/EX Pipeline Register
// =============================================================
wire        wIDEX_RegWrite, wIDEX_MemtoReg, wIDEX_Jump, wIDEX_Lui;
wire        wIDEX_MemWr;
wire [2:0]  wIDEX_Funct3;
wire [2:0]  wIDEX_AluOp;
wire        wIDEX_AluSrc1, wIDEX_AluSrc2, wIDEX_Branch, wIDEX_PcSrc;
wire [31:0] wIDEX_PC, wIDEX_Rs1Data, wIDEX_Rs2Data, wIDEX_Imm;
wire [6:0]  wIDEX_Funct7;

ID_EX id_stage_reg (
    .iClk      (iClk),
    .iRstN     (iRstN),
    .iFlush    (wIDEX_Flush),
    .iStall    (wCacheStall),   // freeze ID/EX on cache miss

    .iRegWrite (wCtrl_RegWrite),
    .iMemtoReg (wCtrl_MemtoReg),
    .iJump     (wCtrl_Jump),
    .iLui      (wCtrl_Lui),
    .iMemRd    (wCtrl_MemRd),
    .iMemWr    (wCtrl_MemWr),
    .iFunct3   (wFunct3_ID),
    .iAluOp    (wCtrl_AluOp),
    .iAluSrc1  (wCtrl_AluSrc1),
    .iAluSrc2  (wCtrl_AluSrc2),
    .iBranch   (wCtrl_Branch),
    .iPcSrc    (wCtrl_PcSrc),

    .iPC       (wPc),
    .iRs1Data  (wRs1Data_ID),
    .iRs2Data  (wRs2Data_ID),
    .iImm      (wImm_ID),
    .iFunct7   (wFunct7_ID),
    .iRs1      (wRs1_ID),
    .iRs2      (wRs2_ID),
    .iRd       (wRd_ID),

    .oRegWrite (wIDEX_RegWrite),
    .oMemtoReg (wIDEX_MemtoReg),
    .oJump     (wIDEX_Jump),
    .oLui      (wIDEX_Lui),
    .oMemRd    (wIDEX_MemRd),
    .oMemWr    (wIDEX_MemWr),
    .oFunct3   (wIDEX_Funct3),
    .oAluOp    (wIDEX_AluOp),
    .oAluSrc1  (wIDEX_AluSrc1),
    .oAluSrc2  (wIDEX_AluSrc2),
    .oBranch   (wIDEX_Branch),
    .oPcSrc    (wIDEX_PcSrc),

    .oPC       (wIDEX_PC),
    .oRs1Data  (wIDEX_Rs1Data),
    .oRs2Data  (wIDEX_Rs2Data),
    .oImm      (wIDEX_Imm),
    .oFunct7   (wIDEX_Funct7),
    .oRs1      (wIDEX_Rs1),
    .oRs2      (wIDEX_Rs2),
    .oRd       (wIDEX_Rd)
);

// =============================================================
// EX STAGE
// =============================================================

wire [1:0] wForwardA, wForwardB;

FORWARDING fwd (
    .iEX_Rs1         (wIDEX_Rs1),
    .iEX_Rs2         (wIDEX_Rs2),
    .iEXMEM_RegWrite (wEXMEM_RegWrite),
    .iEXMEM_MemRd    (wEXMEM_MemRd),
    .iEXMEM_Rd       (wEXMEM_Rd),
    .iMEMWB_RegWrite (wMEMWB_RegWrite),
    .iMEMWB_Rd       (wMEMWB_Rd),
    .oForwardA       (wForwardA),
    .oForwardB       (wForwardB)
);

// Select correct EX/MEM forwarding data
wire [31:0] wEXMEM_FwdData = wEXMEM_Jump ? wEXMEM_PCPlus4 :
                              wEXMEM_Lui  ? wEXMEM_Imm     :
                                            wEXMEM_AluResult;

wire [31:0] wAluIn1_fwd, wAluIn2_fwd;

assign wAluIn1_fwd = (wForwardA == 2'b10) ? wEXMEM_FwdData :
                     (wForwardA == 2'b01) ? wWbData         :
                     (wForwardA == 2'b11) ? wMemReadData    :
                                            wIDEX_Rs1Data;

assign wAluIn2_fwd = (wForwardB == 2'b10) ? wEXMEM_FwdData :
                     (wForwardB == 2'b01) ? wWbData         :
                     (wForwardB == 2'b11) ? wMemReadData    :
                                            wIDEX_Rs2Data;

wire [31:0] wAluOperand1, wAluOperand2;

MUX_2_1 #(.WIDTH(32)) mux_alu_src1 (
    .iData0 (wAluIn1_fwd),
    .iData1 (wIDEX_PC),
    .iSel   (wIDEX_AluSrc1),
    .oData  (wAluOperand1)
);

MUX_2_1 #(.WIDTH(32)) mux_alu_src2 (
    .iData0 (wAluIn2_fwd),
    .iData1 (wIDEX_Imm),
    .iSel   (wIDEX_AluSrc2),
    .oData  (wAluOperand2)
);

wire [3:0]  wAluCtrl;
wire [31:0] wAluResult_EX;
wire        wAluZero;

ALU_CONTROL alu_control (
    .iAluOp   (wIDEX_AluOp),
    .iFunct3  (wIDEX_Funct3),
    .iFunct7  (wIDEX_Funct7),
    .oAluCtrl (wAluCtrl)
);

ALU alu (
    .iDataA   (wAluOperand1),
    .iDataB   (wAluOperand2),
    .iAluCtrl (wAluCtrl),
    .iFunct7  (wIDEX_Funct7),
    .oData    (wAluResult_EX),
    .oZero    (wAluZero)
);

wire [31:0] wBranchJumpTarget_EX;

BRANCH_JUMP branch_jump (
    .iBranch (wIDEX_Branch),
    .iJump   (wIDEX_Jump),
    .iZero   (wAluZero),
    .iOffset (wIDEX_Imm),
    .iPc     (wIDEX_PC),
    .iRs1    (wAluIn1_fwd),
    .iPcSrc  (wIDEX_PcSrc),
    .oPc     (wBranchJumpTarget_EX)
);

wire wTaken_EX;
assign wTaken_EX = wIDEX_Jump | (wIDEX_Branch & wAluZero);

assign wFlush  = wTaken_EX;
assign wNextPC = wTaken_EX ? wBranchJumpTarget_EX : wPCPlus4_IF;

wire [31:0] wIDEX_PCPlus4;
assign wIDEX_PCPlus4 = wIDEX_PC + 32'd4;

// =============================================================
// EX/MEM Pipeline Register  (Phase 6: adds iStall)
// =============================================================
wire        wEXMEM_MemtoReg, wEXMEM_Jump, wEXMEM_Lui;
wire        wEXMEM_MemWr;
wire [2:0]  wEXMEM_Funct3;
wire [31:0] wEXMEM_Rs2Data, wEXMEM_PCPlus4, wEXMEM_Imm;

EX_MEM ex_stage (
    .iClk      (iClk),
    .iRstN     (iRstN),
    .iFlush    (1'b0),
    .iStall    (wCacheStall),   // freeze on cache miss

    .iRegWrite (wIDEX_RegWrite),
    .iMemtoReg (wIDEX_MemtoReg),
    .iJump     (wIDEX_Jump),
    .iLui      (wIDEX_Lui),
    .iMemRd    (wIDEX_MemRd),
    .iMemWr    (wIDEX_MemWr),
    .iFunct3   (wIDEX_Funct3),

    .iAluResult    (wAluResult_EX),
    .iRs2Data      (wAluIn2_fwd),
    .iPCPlus4      (wIDEX_PCPlus4),
    .iImm          (wIDEX_Imm),
    .iRd           (wIDEX_Rd),

    .oRegWrite     (wEXMEM_RegWrite),
    .oMemtoReg     (wEXMEM_MemtoReg),
    .oJump         (wEXMEM_Jump),
    .oLui          (wEXMEM_Lui),
    .oMemRd        (wEXMEM_MemRd),
    .oMemWr        (wEXMEM_MemWr),
    .oFunct3       (wEXMEM_Funct3),

    .oAluResult    (wEXMEM_AluResult),
    .oRs2Data      (wEXMEM_Rs2Data),
    .oPCPlus4      (wEXMEM_PCPlus4),
    .oImm          (wEXMEM_Imm),
    .oRd           (wEXMEM_Rd)
);

// =============================================================
// MEM STAGE  (Phase 6: DATA_CACHE replaces DATA_MEMORY)
// =============================================================

wire [31:0] wMemReadData;
wire        wDCStall_raw;

DATA_CACHE #(
    .EVICT_POLICY (0),
    .WAYS         (4),
    .CACHE_SIZE   (4096),
    .BLOCK_SIZE   (64)
) data_cache (
    .i_clk    (iClk),
    .i_rstn   (iRstN),
    .i_addr   (wEXMEM_AluResult),
    .i_wdata  (wEXMEM_Rs2Data),
    .i_funct3 (wEXMEM_Funct3),
    .i_read   (wEXMEM_MemRd),
    .i_write  (wEXMEM_MemWr),
    .o_rdata  (wMemReadData),
    .o_stall  (wDCStall_raw)
);

assign wDCStall = wDCStall_raw;

// =============================================================
// MEM/WB Pipeline Register  (Phase 6: adds iStall)
// =============================================================
wire        wMEMWB_MemtoReg, wMEMWB_Jump, wMEMWB_Lui;
wire [31:0] wMEMWB_AluResult, wMEMWB_MemReadData;
wire [31:0] wMEMWB_PCPlus4, wMEMWB_Imm;

MEM_WB wb_stage (
    .iClk         (iClk),
    .iRstN        (iRstN),
    .iStall       (wCacheStall),   // freeze on cache miss

    .iRegWrite    (wEXMEM_RegWrite),
    .iMemtoReg    (wEXMEM_MemtoReg),
    .iJump        (wEXMEM_Jump),
    .iLui         (wEXMEM_Lui),

    .iAluResult   (wEXMEM_AluResult),
    .iMemReadData (wMemReadData),
    .iPCPlus4     (wEXMEM_PCPlus4),
    .iImm         (wEXMEM_Imm),
    .iRd          (wEXMEM_Rd),

    .oRegWrite    (wMEMWB_RegWrite),
    .oMemtoReg    (wMEMWB_MemtoReg),
    .oJump        (wMEMWB_Jump),
    .oLui         (wMEMWB_Lui),

    .oAluResult   (wMEMWB_AluResult),
    .oMemReadData (wMEMWB_MemReadData),
    .oPCPlus4     (wMEMWB_PCPlus4),
    .oImm         (wMEMWB_Imm),
    .oRd          (wMEMWB_Rd)
);

// =============================================================
// WB STAGE
// =============================================================
wire [31:0] wbFromMem, wbFromLui;

MUX_2_1 #(.WIDTH(32)) mux_mem_to_reg (
    .iData0 (wMEMWB_AluResult),
    .iData1 (wMEMWB_MemReadData),
    .iSel   (wMEMWB_MemtoReg),
    .oData  (wbFromMem)
);

MUX_2_1 #(.WIDTH(32)) mux_lui (
    .iData0 (wbFromMem),
    .iData1 (wMEMWB_Imm),
    .iSel   (wMEMWB_Lui),
    .oData  (wbFromLui)
);

MUX_2_1 #(.WIDTH(32)) mux_jump_ret (
    .iData0 (wbFromLui),
    .iData1 (wMEMWB_PCPlus4),
    .iSel   (wMEMWB_Jump),
    .oData  (wWbData)
);

assign wWbRegWrite = wMEMWB_RegWrite;
assign wWbRd       = wMEMWB_Rd;

endmodule
