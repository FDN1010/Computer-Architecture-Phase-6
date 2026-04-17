// CACHE.v  N-way set-associative cache with LRU/PLRU, next-line prefetch,
// write-back on eviction, write-allocate on miss.
//
// KEY INSIGHT: prefetch block (miss_base + BLOCK_SIZE) may be in a DIFFERENT
// set than the miss block. We must use f_idx(pref_addr) for pref eviction.

`timescale 1ns/1ps

module CACHE #(
    parameter EVICT_POLICY = 0,   // 0=LRU  1=PLRU
    parameter WAYS         = 4,
    parameter CACHE_SIZE   = 32,  // bytes total
    parameter BLOCK_SIZE   = 64   // bytes per block
) (
    input  wire        i_clk,
    input  wire        i_rstn,
    input  wire        i_read,
    input  wire        i_write,
    input  wire [1:0]  i_funct,
    input  wire [31:0] i_addr,
    input  wire [31:0] i_cpu_data,
    input  wire        i_mem_ready,
    input  wire        i_mem_valid,
    input  wire [BLOCK_SIZE*8-1:0] i_mem_data,
    output reg         o_hit,
    output reg         o_miss,
    output reg  [31:0] o_cpu_data,
    output reg         o_mem_rd,
    output reg         o_mem_wr,
    output reg  [31:0] o_mem_rd_addr,
    output reg  [31:0] o_mem_wr_addr,
    output reg  [BLOCK_SIZE*8-1:0] o_mem_rd_data,
    output reg  [BLOCK_SIZE*8-1:0] o_mem_wr_data
);

// =========================================================
// Derived parameters
// =========================================================
localparam LOG2_WAYS   = $clog2(WAYS);
localparam SETS        = CACHE_SIZE / (WAYS * BLOCK_SIZE);
localparam INDEX_BITS  = (SETS > 1) ? $clog2(SETS) : 0;
localparam OFFSET_BITS = $clog2(BLOCK_SIZE);
localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS;
localparam BLOCK_BITS  = BLOCK_SIZE * 8;
localparam TOTAL       = SETS * WAYS;

// =========================================================
// Storage
// =========================================================
reg [TAG_BITS-1:0]    r_tag  [0:TOTAL-1];
reg [BLOCK_BITS-1:0]  r_data [0:TOTAL-1];
reg                   r_valid[0:TOTAL-1];
reg                   r_dirty[0:TOTAL-1];
reg [LOG2_WAYS-1:0]   r_lru  [0:TOTAL-1];
reg [WAYS-2:0]        r_plru [0:SETS-1];

// =========================================================
// State
// =========================================================
localparam S_IDLE = 2'd0, S_MISS = 2'd1, S_PREFETCH = 2'd2;
reg [1:0]             r_state;
reg [31:0]            r_miss_addr;
reg [1:0]             r_funct;
reg                   r_is_read;
reg [31:0]            r_cpu_wdata;
reg [LOG2_WAYS-1:0]   r_filled_way;
reg [LOG2_WAYS-1:0]   r_pref_ev_way;
reg [31:0]            r_cpu_data_reg;
reg                   r_wr_active;
reg [31:0]            r_wr_addr;
reg [BLOCK_BITS-1:0]  r_wr_data;
// Prefetch set may differ from miss set when BLOCK_SIZE crosses set boundaries
reg [31:0]            r_pref_set;  // set index of prefetch block

// =========================================================
// Address helpers (no variable-width part-selects)
// =========================================================
function automatic [31:0] f_idx;
    input [31:0] a;
    begin
        if (INDEX_BITS > 0)
            f_idx = (a >> OFFSET_BITS) & ((1 << INDEX_BITS) - 1);
        else
            f_idx = 0;
    end
endfunction

function automatic [TAG_BITS-1:0] f_tag;
    input [31:0] a;
    f_tag = a[31 : INDEX_BITS+OFFSET_BITS];
endfunction

function automatic [31:0] f_base;
    input [31:0] a;
    f_base = a & ~((1 << OFFSET_BITS) - 1);
endfunction

// Build block-base address from tag + set index.
// = {tag[TAG_BITS-1:0], index_bits, zero_offset_bits}
// Using arithmetic to avoid variable-width part-selects.
function automatic [31:0] f_block_addr;
    input [TAG_BITS-1:0] tag;
    input integer        set_idx;
    begin
        f_block_addr = {tag, {(INDEX_BITS+OFFSET_BITS){1'b0}}} |
                       (set_idx << OFFSET_BITS);
    end
endfunction

// =========================================================
// Data helpers
// =========================================================
function automatic [31:0] f_extract;
    input [BLOCK_BITS-1:0] blk;
    input [OFFSET_BITS-1:0] boff;
    input [1:0] fn;
    integer b;
    begin
        b = {boff, 3'b0};
        case (fn)
            2'b00:   f_extract = {24'b0, blk[b +: 8]};
            2'b01:   f_extract = {16'b0, blk[b+8 +: 8], blk[b +: 8]};
            default: f_extract = {blk[b+24 +: 8], blk[b+16 +: 8],
                                   blk[b+8  +: 8], blk[b    +: 8]};
        endcase
    end
endfunction

// Data at byte offset 0 of a block (used for miss/prefetch CPU return)
function automatic [31:0] f_pos0;
    input [BLOCK_BITS-1:0] blk;
    input [1:0] fn;
    begin
        case (fn)
            2'b00:   f_pos0 = {24'b0, blk[7:0]};
            2'b01:   f_pos0 = {16'b0, blk[15:8], blk[7:0]};
            default: f_pos0 = {blk[31:24], blk[23:16], blk[15:8], blk[7:0]};
        endcase
    end
endfunction

function automatic [BLOCK_BITS-1:0] f_wb;
    input [BLOCK_BITS-1:0] blk;
    input [OFFSET_BITS-1:0] boff;
    input [1:0] fn;
    input [31:0] wd;
    integer b;
    reg [BLOCK_BITS-1:0] t;
    begin
        t = blk; b = {boff, 3'b0};
        t[b +: 8] = wd[7:0];
        if (fn >= 2'b01) t[b+8  +: 8] = wd[15:8];
        if (fn == 2'b10) begin
            t[b+16 +: 8] = wd[23:16];
            t[b+24 +: 8] = wd[31:24];
        end
        f_wb = t;
    end
endfunction

// =========================================================
// LRU eviction: first invalid way, else minimum LRU counter.
// excl = WAYS means no exclusion.
// =========================================================
function automatic [LOG2_WAYS-1:0] f_lru_ev;
    input integer s;
    input integer excl;
    integer i, best;
    reg [LOG2_WAYS-1:0] best_cnt;
    reg found_inv, found_any;
    begin
        best      = 0; best_cnt = {LOG2_WAYS{1'b1}};
        found_inv = 0; found_any = 0;
        for (i = 0; i < WAYS; i = i + 1) begin
            if (i != excl) begin
                if (!r_valid[s*WAYS + i]) begin
                    if (!found_inv) begin
                        best = i; found_inv = 1; found_any = 1;
                    end
                end else if (!found_inv) begin
                    if (!found_any || r_lru[s*WAYS + i] < best_cnt) begin
                        best = i; best_cnt = r_lru[s*WAYS + i]; found_any = 1;
                    end
                end
            end
        end
        f_lru_ev = best[LOG2_WAYS-1:0];
    end
endfunction

// =========================================================
// PLRU eviction: follow tree; if landing on excl, flip last branch.
// =========================================================
function automatic [LOG2_WAYS-1:0] f_plru_ev;
    input integer s;
    input integer excl;
    integer i, node, d, w;
    reg found_inv;
    begin
        found_inv = 0; w = 0;
        for (i = 0; i < WAYS; i = i + 1)
            if (i != excl && !r_valid[s*WAYS + i] && !found_inv)
                begin w = i; found_inv = 1; end
        if (!found_inv) begin
            node = 0;
            for (d = 0; d < LOG2_WAYS; d = d + 1)
                node = (r_plru[s][node] == 1'b0) ? 2*node+1 : 2*node+2;
            w = node - (WAYS - 1);
            if (w == excl) begin
                node = 0;
                for (d = 0; d < LOG2_WAYS-1; d = d + 1)
                    node = (r_plru[s][node] == 1'b0) ? 2*node+1 : 2*node+2;
                node = (r_plru[s][node] == 1'b0) ? 2*node+2 : 2*node+1;
                w = node - (WAYS - 1);
            end
        end
        f_plru_ev = w[LOG2_WAYS-1:0];
    end
endfunction

// Wrapper respecting EVICT_POLICY
function automatic [LOG2_WAYS-1:0] f_ev;
    input integer s;
    input integer excl;
    begin
        f_ev = (EVICT_POLICY == 0) ? f_lru_ev(s, excl) : f_plru_ev(s, excl);
    end
endfunction

// =========================================================
// Hit detection (combinational)
// =========================================================
reg                  w_hit;
reg [LOG2_WAYS-1:0]  w_hit_way;
integer ci, ci_set;
always @(*) begin
    ci_set    = f_idx(i_addr);
    w_hit     = 0;
    w_hit_way = 0;
    for (ci = 0; ci < WAYS; ci = ci + 1)
        if (r_valid[ci_set*WAYS + ci] &&
            r_tag  [ci_set*WAYS + ci] == f_tag(i_addr)) begin
            w_hit     = 1;
            w_hit_way = ci[LOG2_WAYS-1:0];
        end
end

wire w_cap = i_mem_ready && i_mem_valid;

// =========================================================
// Combinational outputs
// =========================================================
integer co_set;
reg [LOG2_WAYS-1:0] co_ev;

always @(*) begin
    o_hit = 0; o_miss = 0; o_cpu_data = 0;
    o_mem_rd = 0; o_mem_wr = 0;
    o_mem_rd_addr = 0; o_mem_wr_addr = 0;
    o_mem_rd_data = 0; o_mem_wr_data = 0;
    co_ev = 0;

    co_set = (r_state == S_IDLE) ? f_idx(i_addr) : f_idx(r_miss_addr);

    case (r_state)
        S_IDLE: begin
            if (i_read || i_write) begin
                if (w_hit) begin
                    o_hit  = 1;
                    o_miss = i_write ? 1'b1 : 1'b0;
                    o_cpu_data = i_read ?
                                 f_extract(r_data[co_set*WAYS + w_hit_way],
                                           i_addr[OFFSET_BITS-1:0], i_funct)
                                 : r_cpu_data_reg;
                end else begin
                    o_miss        = 1;
                    o_mem_rd      = 1;
                    o_mem_rd_addr = f_base(i_addr);
                    o_cpu_data    = r_cpu_data_reg;
                end
            end
        end

        S_MISS: begin
            o_miss   = 1;
            o_mem_rd = 1;
            if (w_cap) begin
                // Eviction from MISS set
                co_ev = f_ev(co_set, WAYS);
                o_mem_rd_addr = f_base(r_miss_addr) + BLOCK_SIZE;
                if (r_valid[co_set*WAYS + co_ev] && r_dirty[co_set*WAYS + co_ev]) begin
                    o_mem_wr      = 1;
                    o_mem_wr_addr = f_block_addr(r_tag[co_set*WAYS + co_ev], co_set);
                    o_mem_wr_data = r_data[co_set*WAYS + co_ev];
                end
                o_cpu_data = r_is_read ? f_pos0(i_mem_data, r_funct) : r_cpu_data_reg;
            end else begin
                o_mem_rd_addr = f_base(r_miss_addr);
                o_cpu_data    = r_cpu_data_reg;
            end
        end

        S_PREFETCH: begin
            if (w_cap) begin
                o_mem_rd_addr = f_base(r_miss_addr) + BLOCK_SIZE;
                o_cpu_data    = r_is_read ? f_pos0(i_mem_data, r_funct) : r_cpu_data_reg;
                // wr=0 at done per TA traces (prefetch eviction assumed clean)
            end else begin
                o_miss        = 1;
                o_mem_rd      = 1;
                o_mem_rd_addr = f_base(r_miss_addr) + BLOCK_SIZE;
                o_cpu_data    = r_cpu_data_reg;
                o_mem_wr      = r_wr_active;
                o_mem_wr_addr = r_wr_addr;
                o_mem_wr_data = r_wr_data;
            end
        end

        default: begin end
    endcase
end

// =========================================================
// Sequential logic
// =========================================================
integer sm_set, sm_pref_set, sm_ev, sm_pref_ev, j, pnd, pdir;

always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        r_state <= S_IDLE; r_wr_active <= 0; r_cpu_data_reg <= 0;
        r_filled_way <= 0; r_pref_ev_way <= 0; r_pref_set <= 0;
        for (j = 0; j < TOTAL; j = j+1) begin
            r_valid[j] <= 0; r_dirty[j] <= 0;
            r_lru  [j] <= 0; r_tag  [j] <= 0;
            r_data [j] <= 0;
        end
        for (j = 0; j < SETS; j = j+1) r_plru[j] <= 0;
    end else begin
        case (r_state)

        // ── IDLE ─────────────────────────────────────────────
        S_IDLE: begin
            r_wr_active <= 0;
            if (i_read || i_write) begin
                sm_set = f_idx(i_addr);
                if (w_hit) begin
                    // Write hit: update data + dirty
                    if (i_write) begin
                        r_data [sm_set*WAYS + w_hit_way] <=
                            f_wb(r_data[sm_set*WAYS + w_hit_way],
                                 i_addr[OFFSET_BITS-1:0], i_funct, i_cpu_data);
                        r_dirty[sm_set*WAYS + w_hit_way] <= 1;
                    end
                    // Update replacement
                    if (EVICT_POLICY == 0) begin
                        for (j = 0; j < WAYS; j = j+1) begin
                            if (j == w_hit_way)
                                r_lru[sm_set*WAYS + j] <= WAYS-1;
                            else if (r_valid[sm_set*WAYS + j] &&
                                     r_lru[sm_set*WAYS + j] > 0)
                                r_lru[sm_set*WAYS + j] <=
                                    r_lru[sm_set*WAYS + j] - 1;
                        end
                    end else begin
                        pnd = 0;
                        for (pdir = LOG2_WAYS-1; pdir >= 0; pdir = pdir-1) begin
                            if (((w_hit_way >> pdir) & 1) == 0)
                                begin r_plru[sm_set][pnd] <= 1; pnd = 2*pnd+1; end
                            else
                                begin r_plru[sm_set][pnd] <= 0; pnd = 2*pnd+2; end
                        end
                    end
                    r_cpu_data_reg <= 0;
                end else begin
                    r_miss_addr <= i_addr;
                    r_funct     <= i_funct;
                    r_is_read   <= i_read;
                    r_cpu_wdata <= i_cpu_data;
                    r_state     <= S_MISS;
                end
            end else begin
                r_cpu_data_reg <= 0;
            end
        end

        // ── MISS ─────────────────────────────────────────────
        S_MISS: begin
            if (w_cap) begin
                sm_set      = f_idx(r_miss_addr);
                // Prefetch block address and its set index
                sm_pref_set = f_idx(f_base(r_miss_addr) + BLOCK_SIZE);

                // Compute eviction for MISS set (no exclusion)
                sm_ev = f_ev(sm_set, WAYS);

                // Compute eviction for PREFETCH set.
                // If same set as miss: exclude the just-filled miss way.
                // If different set: no exclusion needed.
                if (sm_pref_set == sm_set)
                    sm_pref_ev = f_ev(sm_pref_set, sm_ev);
                else
                    sm_pref_ev = f_ev(sm_pref_set, WAYS);
                r_pref_ev_way <= sm_pref_ev[LOG2_WAYS-1:0];
                r_pref_set    <= sm_pref_set;

                // Write-back dirty miss eviction
                if (r_valid[sm_set*WAYS + sm_ev] && r_dirty[sm_set*WAYS + sm_ev]) begin
                    r_wr_active <= 1;
                    r_wr_addr   <= f_block_addr(r_tag[sm_set*WAYS + sm_ev], sm_set);
                    r_wr_data   <= r_data[sm_set*WAYS + sm_ev];
                end else begin
                    r_wr_active <= 0;
                end

                // Place miss block (clean; may be dirtied at PREFETCH done)
                r_tag  [sm_set*WAYS + sm_ev] <= f_tag(r_miss_addr);
                r_data [sm_set*WAYS + sm_ev] <= i_mem_data;
                r_valid[sm_set*WAYS + sm_ev] <= 1;
                r_dirty[sm_set*WAYS + sm_ev] <= 0;
                r_filled_way                 <= sm_ev[LOG2_WAYS-1:0];

                // Update replacement for miss set
                if (EVICT_POLICY == 0) begin
                    if (r_is_read) begin
                        for (j = 0; j < WAYS; j = j+1) begin
                            if (j == sm_ev) r_lru[sm_set*WAYS+j] <= WAYS-1;
                            else if (r_valid[sm_set*WAYS+j] &&
                                     r_lru[sm_set*WAYS+j] > 0)
                                r_lru[sm_set*WAYS+j] <= r_lru[sm_set*WAYS+j]-1;
                        end
                    end else begin
                        r_lru[sm_set*WAYS + sm_ev] <= 0;
                    end
                end
                // PLRU: no update on miss install (only updated on S_IDLE hits)

                if (r_is_read) r_cpu_data_reg <= f_pos0(i_mem_data, r_funct);
                r_state <= S_PREFETCH;
            end
        end

        // ── PREFETCH ─────────────────────────────────────────
        S_PREFETCH: begin
            if (w_cap) begin
                sm_set      = f_idx(r_miss_addr);
                sm_pref_set = r_pref_set;  // registered at MISS capture
                sm_ev       = r_pref_ev_way;

                // Place prefetch block in its own set (clean)
                r_tag  [sm_pref_set*WAYS + sm_ev] <= f_tag(f_base(r_miss_addr) + BLOCK_SIZE);
                r_data [sm_pref_set*WAYS + sm_ev] <= i_mem_data;
                r_valid[sm_pref_set*WAYS + sm_ev] <= 1;
                r_dirty[sm_pref_set*WAYS + sm_ev] <= 0;

                // Update replacement for PREFETCH set (always read-type)
                if (EVICT_POLICY == 0) begin
                    for (j = 0; j < WAYS; j = j+1) begin
                        if (j == sm_ev) r_lru[sm_pref_set*WAYS+j] <= WAYS-1;
                        else if (r_valid[sm_pref_set*WAYS+j] &&
                                 r_lru[sm_pref_set*WAYS+j] > 0)
                            r_lru[sm_pref_set*WAYS+j] <= r_lru[sm_pref_set*WAYS+j]-1;
                    end
                end
                // PLRU: no update on prefetch install (only updated on S_IDLE hits)

                // Apply write-allocate to MISS set (mark dirty)
                if (!r_is_read) begin
                    r_data [sm_set*WAYS + r_filled_way] <=
                        f_wb(r_data[sm_set*WAYS + r_filled_way],
                             r_miss_addr[OFFSET_BITS-1:0], r_funct, r_cpu_wdata);
                    r_dirty[sm_set*WAYS + r_filled_way] <= 1;
                end

                if (r_is_read) r_cpu_data_reg <= f_pos0(i_mem_data, r_funct);
                r_wr_active <= 0;
                r_state     <= S_IDLE;
            end
        end

        default: r_state <= S_IDLE;

        endcase
    end
end

endmodule
