module RISCV_TOP (
    input i_clk,
    input i_rstn
);

// =============================================================
// STALL / FLUSH signals
// =============================================================
wire wHazardStall_raw;  // load-use stall from hazard unit (ungated)
wire wIDEX_Bubble_raw;  // hazard bubble into ID/EX (ungated)
wire wICacheStall;      // instruction cache miss stall
wire wDCacheStall;      // data cache miss stall
wire wFlush;            // branch/jump flush from EX stage (1-cycle penalty)

// Gate hazard unit off during any cache miss so it cannot inject spurious
// bubbles into the frozen instruction stream
wire wCacheStall  = wICacheStall | wDCacheStall;
wire wHazardStall = wHazardStall_raw & ~wCacheStall;
wire wIDEX_Bubble = wIDEX_Bubble_raw & ~wCacheStall;

// Any stall freezes PC and IF/ID
wire wStall = wHazardStall | wCacheStall;

// =============================================================
// IF STAGE   Program Counter
// PC starts at 0x00400000 per Phase 6 memory map
// =============================================================
reg  [31:0] wPC;
wire [31:0] wNextPC;
wire [31:0] wPCPlus4_IF;
wire [31:0] wInstr_raw;

assign wPCPlus4_IF = wPC + 32'd4;

always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn)
        wPC <= 32'h00400000;      // Phase 6: text segment base
    else if (!wStall)
        wPC <= wNextPC;
end

// =============================================================
// Instruction Cache
// =============================================================
wire [31:0]      wICache_MemAddr;
wire             wICache_MemReq;
wire [64*8-1:0]  wICache_MemRdBlock;
wire             wICache_MemReady;

CACHE #(
    .CACHE_SIZE (4096),
    .BLOCK_SIZE (64),
    .WAYS       (4),
    .IS_INSTR   (1)
) instr_cache (
    .i_clk          (i_clk),
    .i_rstn         (i_rstn),

    .i_addr         (wPC),
    .i_cpu_data     (32'b0),
    .i_funct        (3'b010),
    .i_read         (!wICacheStall),   // don't re-request while already missing
    .i_write        (1'b0),

    .i_mem_ready    (wICache_MemReady),
    .i_mem_valid    (1'b0),
    .i_mem_rd_data  (wICache_MemRdBlock),

    .o_hit          (),
    .o_miss         (),
    .o_cpu_data     (wInstr_raw),
    .o_stall        (wICacheStall),

    .o_mem_rd       (wICache_MemReq),
    .o_mem_wr       (),
    .o_mem_rd_addr  (wICache_MemAddr),
    .o_mem_wr_addr  (),
    .o_mem_wr_data  ()
);

// =============================================================
// IF/ID Pipeline Register
// wInstr and wPc match signals.yaml ("wInstr") ("wPc")
// =============================================================
reg [31:0] wInstr;
reg [31:0] wPc;

always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn || wFlush) begin
        wInstr <= 32'h00000013;
        wPc    <= 32'h00400000;
    end else if (!wStall) begin
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
    .i_clk       (i_clk),
    .i_rstn      (i_rstn),
    .iWriteEn   (wWbRegWrite),
    .iRdAddr    (wWbRd),
    .iRs1Addr   (wRs1_ID),
    .iRs2Addr   (wRs2_ID),
    .i_cpu_data (wWbData),
    .oRs1Data   (wRs1Data_ID),
    .oRs2Data   (wRs2Data_ID)
);

// =============================================================
// Hazard Detection Unit  (load-use stall)
// =============================================================
wire [4:0] wIDEX_Rd;
wire       wIDEX_MemRd;

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
    .oStall        (wHazardStall_raw),
    .oIDEX_Flush   (wIDEX_Bubble_raw)
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
wire [4:0]  wIDEX_Rs1, wIDEX_Rs2;

ID_EX id_stage_reg (
    .i_clk      (i_clk),
    .i_rstn     (i_rstn),
    .iFlush    (wIDEX_Flush),
    .iStall    (wStall),

    .iRegWrite (wCtrl_RegWrite),
    .iMemtoReg (wCtrl_MemtoReg),
    .iJump     (wCtrl_Jump),
    .iLui      (wCtrl_Lui),
    .iMemRd    (wCtrl_MemRd),
    .iMemWr    (wCtrl_MemWr),
    .i_funct   (wFunct3_ID),
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

wire        wEXMEM_RegWrite;
wire [4:0]  wEXMEM_Rd;
wire        wMEMWB_RegWrite;
wire [4:0]  wMEMWB_Rd;
wire [31:0] wEXMEM_AluResult;

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
    .i_funct  (wIDEX_Funct3),
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
// EX/MEM Pipeline Register
// =============================================================
wire        wEXMEM_MemtoReg, wEXMEM_Jump, wEXMEM_Lui;
wire        wEXMEM_MemRd, wEXMEM_MemWr;
wire [2:0]  wEXMEM_Funct3;
wire [31:0] wEXMEM_Rs2Data, wEXMEM_PCPlus4, wEXMEM_Imm;

EX_MEM ex_stage (
    .i_clk      (i_clk),
    .i_rstn     (i_rstn),
    .iFlush    (1'b0),
    .iStall    (wDCacheStall),
    .iRegWrite (wIDEX_RegWrite),
    .iMemtoReg (wIDEX_MemtoReg),
    .iJump     (wIDEX_Jump),
    .iLui      (wIDEX_Lui),
    .iMemRd    (wIDEX_MemRd),
    .iMemWr    (wIDEX_MemWr),
    .i_funct   (wIDEX_Funct3),

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
// MEM STAGE  –  Data Cache sits in front of main memory
// =============================================================
wire [31:0]      wDCache_MemRdAddr;
wire [31:0]      wDCache_MemWrAddr;
wire             wDCache_MemReq;
wire             wDCache_MemWrite;
wire [64*8-1:0]  wDCache_MemWrBlock;
wire [64*8-1:0]  wDCache_MemRdBlock;
wire             wDCache_MemReady;
wire [31:0]      wMemReadData;

CACHE #(
    .CACHE_SIZE (4096),
    .BLOCK_SIZE (64),
    .WAYS       (4),
    .IS_INSTR   (0)
) data_cache (
    .i_clk          (i_clk),
    .i_rstn         (i_rstn),

    .i_addr         (wEXMEM_AluResult),
    .i_cpu_data     (wEXMEM_Rs2Data),
    .i_funct        (wEXMEM_Funct3),
    .i_read         (wEXMEM_MemRd),
    .i_write        (wEXMEM_MemWr),

    .i_mem_ready    (wDCache_MemReady),
    .i_mem_valid    (1'b0),
    .i_mem_rd_data  (wDCache_MemRdBlock),

    .o_hit          (),
    .o_miss         (),
    .o_cpu_data     (wMemReadData),
    .o_stall        (wDCacheStall),

    .o_mem_rd       (wDCache_MemReq),
    .o_mem_wr       (wDCache_MemWrite),
    .o_mem_rd_addr  (wDCache_MemRdAddr),
    .o_mem_wr_addr  (wDCache_MemWrAddr),
    .o_mem_wr_data  (wDCache_MemWrBlock)
);

// =============================================================
// Unified Main Memory  (backing store for both caches)
// =============================================================
MAIN_MEMORY #(
    .BLOCK_SIZE (64),
    .INSTR_SIZE (65536),
    .DATA_SIZE  (196608)
) main_memory (
    .i_clk          (i_clk),
    .i_rstn         (i_rstn),

    // Instruction cache port
    .iInstrAddr    (wICache_MemAddr),
    .iInstrReq     (wICache_MemReq),
    .oInstrBlock   (wICache_MemRdBlock),
    .oInstrReady   (wICache_MemReady),

    // Data cache port
    // MAIN_MEMORY uses a single address port; mux read vs write-back address
    .iDataAddr     (wDCache_MemWrite ? wDCache_MemWrAddr : wDCache_MemRdAddr),
    .iDataReq      (wDCache_MemReq | wDCache_MemWrite),
    .iDataWrite    (wDCache_MemWrite),
    .iDataBlock    (wDCache_MemWrBlock),
    .oDataBlock    (wDCache_MemRdBlock),
    .oDataReady    (wDCache_MemReady)
);

// =============================================================
// MEM/WB Pipeline Register
// =============================================================
wire        wMEMWB_MemtoReg, wMEMWB_Jump, wMEMWB_Lui;
wire [31:0] wMEMWB_AluResult, wMEMWB_MemReadData;
wire [31:0] wMEMWB_PCPlus4, wMEMWB_Imm;

MEM_WB wb_stage (
    .i_clk         (i_clk),
    .i_rstn        (i_rstn),
    .iStall        (wDCacheStall),
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
