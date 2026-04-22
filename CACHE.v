module CACHE #(
    parameter CACHE_SIZE  = 4096,
    parameter BLOCK_SIZE  = 64,
    parameter NUM_WAYS    = 4,
    parameter WAYS        = NUM_WAYS,
    parameter IS_INSTR    = 0,
    parameter EVICT_POLICY = 0,
    parameter WRITE_BACK   = 1,
    parameter PREFETCH     = 1,
    parameter MEM_CYCLES   = 100
)(
    input         i_clk,
    input         i_rstn,

    input  [31:0] i_addr,
    input  [31:0] i_cpu_data,
    input  [2:0]  i_funct,
    input         i_read,
    input         i_write,

    input                         i_mem_ready,
    input                         i_mem_valid,
    input  [BLOCK_SIZE*8-1:0]     i_mem_rd_data,

    output reg        o_hit,
    output reg        o_miss,
    output reg        o_stall,
    output reg [31:0] o_cpu_data,

    output reg        o_mem_rd,
    output reg        o_mem_wr,
    output reg [31:0] o_mem_rd_addr,
    output reg [31:0] o_mem_wr_addr,
    output reg [BLOCK_SIZE*8-1:0] o_mem_wr_data
);

    localparam SETS       = (CACHE_SIZE / (BLOCK_SIZE * WAYS)) < 1 ? 1
                                                                     : (CACHE_SIZE / (BLOCK_SIZE * WAYS));
    localparam BLOCK_BITS = $clog2(BLOCK_SIZE);
    // When SETS==1 (fully associative) use 0 set-index bits so the full
    // remaining address is available as tag.  Verilog doesn't allow 0-wide
    // vectors so we keep the wire at 1 bit but mask it to 0 in w_set.
    localparam SET_BITS   = (SETS <= 1) ? 1 : $clog2(SETS);
    localparam SET_SHIFT  = (SETS <= 1) ? 0 : SET_BITS;   // bits consumed by set index
    localparam TAG_BITS   = 32 - SET_SHIFT - BLOCK_BITS;
    localparam WAY_BITS   = (WAYS <= 1) ? 1 : $clog2(WAYS);

    reg [TAG_BITS-1:0]      tag   [0:SETS-1][0:WAYS-1];
    reg [BLOCK_SIZE*8-1:0]  data  [0:SETS-1][0:WAYS-1];
    reg                     valid [0:SETS-1][0:WAYS-1];
    reg                     dirty [0:SETS-1][0:WAYS-1];
    reg [WAY_BITS-1:0]      age   [0:SETS-1][0:WAYS-1];

    // PLRU tree bits: WAYS-1 bits per set
    /* verilator lint_off WIDTH */
    localparam [WAY_BITS-1:0] MRU_AGE  = WAYS - 1;
    /* verilator lint_on WIDTH */
    localparam                PLRU_BITS = (WAYS <= 1) ? 1 : WAYS - 1;
    reg [PLRU_BITS-1:0] plru_tree [0:SETS-1];

    wire [SET_BITS-1:0] w_set =
        (SETS <= 1) ? 1'b0 : i_addr[BLOCK_BITS + SET_BITS - 1 : BLOCK_BITS];

    wire [TAG_BITS-1:0] w_tag =
        i_addr[31 : BLOCK_BITS + SET_SHIFT];

    wire [BLOCK_BITS-1:0] byte_off =
        i_addr[BLOCK_BITS-1:0];

    // ---------------------------------------------------------------
    // Hit detection
    // ---------------------------------------------------------------
    integer w;
    reg hit;
    reg [WAY_BITS-1:0] hit_way;

    always @(*) begin
        hit = 0;
        hit_way = 0;
        for (w = 0; w < WAYS; w = w + 1) begin
            if (valid[w_set][w] && tag[w_set][w] == w_tag) begin
                hit = 1;
                hit_way = w[WAY_BITS-1:0];
            end
        end
    end

    // ---------------------------------------------------------------
    // LRU victim selection
    // Prefer invalid ways first; among valid ways pick lowest age (LRU)
    // ---------------------------------------------------------------
    reg [WAY_BITS-1:0] lru_way;
    integer lv;
    always @(*) begin
        // Default to way 0
        lru_way = 0;
        // First: pick any invalid way (free slot — no eviction needed)
        begin : lru_invalid_scan
            reg found_invalid;
            found_invalid = 1'b0;
            for (lv = 0; lv < WAYS; lv = lv + 1) begin
                if (!valid[w_set][lv] && !found_invalid) begin
                    lru_way = lv[WAY_BITS-1:0];
                    found_invalid = 1'b1;
                end
            end
            // If no invalid way found, fall back to true LRU (lowest age)
            if (!found_invalid) begin
                lru_way = 0;
                for (lv = 1; lv < WAYS; lv = lv + 1)
                    if (age[w_set][lv] < age[w_set][lru_way])
                        lru_way = lv[WAY_BITS-1:0];
            end
        end
    end

    // ---------------------------------------------------------------
    // PLRU victim selection (binary tree, WAYS must be power of 2)
    // ---------------------------------------------------------------
    reg [WAY_BITS-1:0] plru_way;
    always @(*) begin
        plru_way = 0;
        begin : plru_find
            integer node;
            integer level;
            node = 0;
            for (level = 0; level < WAY_BITS; level = level + 1) begin
                if (plru_tree[w_set][node] == 1'b0)
                    node = 2*node + 1;
                else
                    node = 2*node + 2;
            end
            plru_way = node[WAY_BITS-1:0] - WAY_BITS'(WAYS-1);
        end
    end

    // ---------------------------------------------------------------
    // Eviction way mux
    // ---------------------------------------------------------------
    wire [WAY_BITS-1:0] evict_way = (EVICT_POLICY == 0) ? lru_way : plru_way;

    // ---------------------------------------------------------------
    // extract_word: read a sub-word from a cache block
    // ---------------------------------------------------------------
    function [31:0] extract_word;
        input [BLOCK_SIZE*8-1:0] blk;
        input [BLOCK_BITS-1:0] off;
        input [2:0] fn3;
        reg [7:0] b0,b1,b2,b3;
        reg [31:0] off_w;
        begin
            off_w = {26'b0, off};
            b0 = blk[off_w*8 +:8];
            b1 = blk[(off_w+1)*8 +:8];
            b2 = blk[(off_w+2)*8 +:8];
            b3 = blk[(off_w+3)*8 +:8];
            case (fn3)
                3'h0: extract_word = {{24{b0[7]}}, b0};        // LB
                3'h1: extract_word = {{16{b1[7]}}, b1, b0};    // LH
                3'h4: extract_word = {24'b0, b0};               // LBU
                3'h5: extract_word = {16'b0, b1, b0};           // LHU
                default: extract_word = {b3, b2, b1, b0};       // LW
            endcase
        end
    endfunction

    // ---------------------------------------------------------------
    // insert_word: write a sub-word into a cache block
    // ---------------------------------------------------------------
    function [BLOCK_SIZE*8-1:0] insert_word;
        input [BLOCK_SIZE*8-1:0] blk;
        input [BLOCK_BITS-1:0] off;
        input [31:0] wdata;
        input [2:0] fn3;
        reg [BLOCK_SIZE*8-1:0] tmp;
        reg [31:0] off_w;
        begin
            tmp = blk;
            off_w = {26'b0, off};
            case (fn3)
                3'h0: begin // SB
                    tmp[off_w*8 +:8] = wdata[7:0];
                end
                3'h1: begin // SH
                    tmp[off_w*8     +:8] = wdata[7:0];
                    tmp[(off_w+1)*8 +:8] = wdata[15:8];
                end
                default: begin // SW (fn3==2)
                    tmp[off_w*8     +:8] = wdata[7:0];
                    tmp[(off_w+1)*8 +:8] = wdata[15:8];
                    tmp[(off_w+2)*8 +:8] = wdata[23:16];
                    tmp[(off_w+3)*8 +:8] = wdata[31:24];
                end
            endcase
            insert_word = tmp;
        end
    endfunction

    // ---------------------------------------------------------------
    // LRU update task
    // Promote accessed way to MRU (age = WAYS-1); demote all others
    // whose age was strictly greater than the accessed way's old age.
    // ---------------------------------------------------------------
    task update_lru;
        input [SET_BITS-1:0]  s;
        input [WAY_BITS-1:0] widx;
        integer i;
        reg [WAY_BITS-1:0] old_age;
        begin
            old_age = age[s][widx];
            for (i = 0; i < WAYS; i = i + 1) begin
                if (i[WAY_BITS-1:0] == widx) begin
                    age[s][i] <= MRU_AGE;
                end else if (age[s][i] > old_age) begin
                    age[s][i] <= age[s][i] - 1'b1;
                end
                // ways with age <= old_age (other than widx) keep their age
            end
        end
    endtask

    // ---------------------------------------------------------------
    // PLRU update task
    // ---------------------------------------------------------------
    task update_plru;
        input [SET_BITS-1:0]  s;
        input [WAY_BITS-1:0] widx;
        integer level;
        integer node;
        begin
            node = 0;
            for (level = 0; level < WAY_BITS; level = level + 1) begin
                if (widx[WAY_BITS-1-level] == 1'b0) begin
                    plru_tree[s][node] <= 1'b1;
                    node = 2*node + 1;
                end else begin
                    plru_tree[s][node] <= 1'b0;
                    node = 2*node + 2;
                end
            end
        end
    endtask

    // ---------------------------------------------------------------
    // State machine
    // ---------------------------------------------------------------
    reg [1:0] state;

    // Saved miss-time state
    reg [SET_BITS-1:0]     saved_set;
    reg [TAG_BITS-1:0]     saved_tag;
    reg [WAY_BITS-1:0]     saved_evict;
    reg                    saved_write;
    reg [31:0]             saved_cpu_data;
    reg [2:0]              saved_funct;
    reg [BLOCK_BITS-1:0]   saved_byte_off;
    reg [31:0]             saved_addr;

    // Prefetch saved state
    reg [WAY_BITS-1:0]     pf_evict;
    reg [TAG_BITS-1:0]     pf_tag;
    reg [SET_BITS-1:0]     pf_set;

    // S_IDLE  : waiting for request
    // S_FETCH : waiting for main memory to return the requested block
    // S_PFETCH: waiting for main memory to return the prefetch block
    localparam S_IDLE=0, S_FETCH=1, S_PFETCH=2;

    integer rs, rw;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            state   <= S_IDLE;
            o_stall <= 1'b0;
            for (rs = 0; rs < (SETS==0 ? 1 : SETS); rs = rs + 1) begin
                plru_tree[rs] <= 0;
                for (rw = 0; rw < WAYS; rw = rw + 1) begin
                    valid[rs][rw] <= 0;
                    dirty[rs][rw] <= 0;
                    age[rs][rw]   <= rw[WAY_BITS-1:0];
                end
            end
        end else begin

            o_hit    <= 0;
            o_miss   <= 0;
            o_stall  <= 0;
            o_mem_rd <= 0;
            o_mem_wr <= 0;

            case (state)

            // ----------------------------------------------------------
            S_IDLE: begin
                if (i_read || i_write) begin
                    if (hit) begin
                        o_hit <= 1;

                        if (i_read)
                            o_cpu_data <= extract_word(data[w_set][hit_way], byte_off, i_funct);

                        if (i_write) begin
                            data[w_set][hit_way] <=
                                insert_word(data[w_set][hit_way], byte_off, i_cpu_data, i_funct);

                            if (WRITE_BACK) begin
                                dirty[w_set][hit_way] <= 1;
                            end else begin
                                // Write-through hit: push word to memory immediately
                                o_mem_wr      <= 1;
                                o_mem_wr_addr <= {i_addr[31:BLOCK_BITS], {BLOCK_BITS{1'b0}}};
                                o_mem_wr_data <=
                                    insert_word(data[w_set][hit_way], byte_off, i_cpu_data, i_funct);
                            end
                        end

                        if (EVICT_POLICY == 0)
                            update_lru(w_set, hit_way);
                        else
                            update_plru(w_set, hit_way);

                    end else begin
                        // Miss: request block from memory
                        o_miss        <= 1;
                        o_stall       <= 1;
                        o_mem_rd      <= 1;
                        o_mem_rd_addr <= {i_addr[31:BLOCK_BITS], {BLOCK_BITS{1'b0}}};

                        // Save everything needed for fill
                        saved_set      <= w_set;
                        saved_tag      <= w_tag;
                        saved_evict    <= evict_way;
                        saved_write    <= i_write;
                        saved_cpu_data <= i_cpu_data;
                        saved_funct    <= i_funct;
                        saved_byte_off <= byte_off;
                        saved_addr     <= i_addr;
                        state          <= S_FETCH;
                    end
                end
            end

            // ----------------------------------------------------------
            // S_FETCH: wait for memory. When i_mem_ready fires, fill
            // the cache line immediately (no separate S_FILL state) so
            // the total miss penalty is exactly mem_cycles+1 cycles.
            // ----------------------------------------------------------
            S_FETCH: begin
                o_stall <= 1;
                if (i_mem_ready) begin

                    // ---- evict dirty line if write-back ----
                    if (WRITE_BACK && dirty[saved_set][saved_evict]) begin
                        o_mem_wr      <= 1;
                        /* verilator lint_off WIDTH */
                        o_mem_wr_addr <= (SETS <= 1)
                            ? {tag[saved_set][saved_evict], {BLOCK_BITS{1'b0}}}
                            : {tag[saved_set][saved_evict], saved_set[SET_BITS-1:0], {BLOCK_BITS{1'b0}}};
                        /* verilator lint_on WIDTH */
                        o_mem_wr_data <= data[saved_set][saved_evict];
                    end

                    // ---- fill: write-allocate for write-back, no-allocate otherwise ----
                    data[saved_set][saved_evict] <= (WRITE_BACK && saved_write)
                        ? insert_word(i_mem_rd_data, saved_byte_off, saved_cpu_data, saved_funct)
                        : i_mem_rd_data;

                    tag[saved_set][saved_evict]   <= saved_tag;
                    valid[saved_set][saved_evict] <= 1;

                    // ---- dirty bit ----
                    if (WRITE_BACK && saved_write)
                        dirty[saved_set][saved_evict] <= 1;
                    else
                        dirty[saved_set][saved_evict] <= 0;

                    // ---- return data to CPU on read miss ----
                    if (!saved_write) begin
                        o_cpu_data <= extract_word(i_mem_rd_data, saved_byte_off, saved_funct);
                        o_hit      <= 1;   // signal fill completion to pipeline
                    end else begin
                        o_hit      <= 1;   // write miss fill also completes
                    end
                    o_stall <= 0;

                    // ---- write-through miss: push word to memory ----
                    if (!WRITE_BACK && saved_write) begin
                        o_mem_wr      <= 1;
                        o_mem_wr_addr <= {saved_addr[31:BLOCK_BITS], {BLOCK_BITS{1'b0}}};
                        o_mem_wr_data <= i_mem_rd_data;
                    end

                    // ---- update replacement state ----
                    if (EVICT_POLICY == 0)
                        update_lru(saved_set, saved_evict);
                    else
                        update_plru(saved_set, saved_evict);

                    // ---- prefetch next line if enabled ----
                    if (PREFETCH) begin
                        // Compute next-line address and its cache index
                        begin : pf_calc
                            reg [31:0] pf_addr;
                            reg [SET_BITS-1:0]  pf_s;
                            reg [TAG_BITS-1:0]  pf_t;
                            reg [WAY_BITS-1:0]  pf_v;
                            reg                 pf_already_valid;
                            integer             pfw;

                            pf_addr = {saved_addr[31:BLOCK_BITS], {BLOCK_BITS{1'b0}}}
                                      + BLOCK_SIZE;
                            pf_s = (SETS <= 1) ? 1'b0
                                               : pf_addr[BLOCK_BITS + SET_BITS - 1 : BLOCK_BITS];
                            pf_t = pf_addr[31 : BLOCK_BITS + SET_SHIFT];

                            // Check if prefetch line already in cache
                            pf_already_valid = 0;
                            for (pfw = 0; pfw < WAYS; pfw = pfw + 1)
                                if (valid[pf_s][pfw] && tag[pf_s][pfw] == pf_t)
                                    pf_already_valid = 1;

                            if (!pf_already_valid) begin
                                // Select victim for prefetch line
                                pf_already_valid = 0; // reuse as found_invalid flag
                                pf_v = 0;
                                for (pfw = 0; pfw < WAYS; pfw = pfw + 1)
                                    if (!valid[pf_s][pfw] && !pf_already_valid) begin
                                        pf_v = pfw[WAY_BITS-1:0];
                                        pf_already_valid = 1;
                                    end
                                if (!pf_already_valid) begin
                                    // All ways valid - use LRU/PLRU victim
                                    pf_v = 0;
                                    for (pfw = 1; pfw < WAYS; pfw = pfw + 1)
                                        if (age[pf_s][pfw] < age[pf_s][pf_v])
                                            pf_v = pfw[WAY_BITS-1:0];
                                end

                                pf_evict <= pf_v;
                                pf_tag   <= pf_t;
                                pf_set   <= pf_s;

                                o_mem_rd      <= 1;
                                o_mem_rd_addr <= pf_addr;
                                o_stall       <= 0; // prefetch is background, don't stall
                                state         <= S_PFETCH;
                            end else begin
                                state <= S_IDLE;
                            end
                        end
                    end else begin
                        state <= S_IDLE;
                    end
                end
            end

            // ----------------------------------------------------------
            // S_PFETCH: silently fill the prefetched line; no CPU stall
            // ----------------------------------------------------------
            S_PFETCH: begin
                // Don't stall the pipeline during prefetch
                o_stall <= 0;
                if (i_mem_ready) begin
                    // Evict dirty prefetch victim if write-back
                    if (WRITE_BACK && dirty[pf_set][pf_evict]) begin
                        o_mem_wr      <= 1;
                        /* verilator lint_off WIDTH */
                        o_mem_wr_addr <= (SETS <= 1)
                            ? {tag[pf_set][pf_evict], {BLOCK_BITS{1'b0}}}
                            : {tag[pf_set][pf_evict], pf_set[SET_BITS-1:0], {BLOCK_BITS{1'b0}}};
                        /* verilator lint_on WIDTH */
                        o_mem_wr_data <= data[pf_set][pf_evict];
                    end

                    data[pf_set][pf_evict]  <= i_mem_rd_data;
                    tag[pf_set][pf_evict]   <= pf_tag;
                    valid[pf_set][pf_evict] <= 1;
                    dirty[pf_set][pf_evict] <= 0;

                    if (EVICT_POLICY == 0)
                        update_lru(pf_set, pf_evict);
                    else
                        update_plru(pf_set, pf_evict);

                    state <= S_IDLE;
                end else begin
                    // If a CPU request arrives while prefetching, we can
                    // still serve hits from cache (prefetch is background)
                    if ((i_read || i_write) && hit) begin
                        o_hit <= 1;
                        if (i_read)
                            o_cpu_data <= extract_word(data[w_set][hit_way], byte_off, i_funct);
                        if (i_write) begin
                            data[w_set][hit_way] <=
                                insert_word(data[w_set][hit_way], byte_off, i_cpu_data, i_funct);
                            if (WRITE_BACK)
                                dirty[w_set][hit_way] <= 1;
                        end
                        if (EVICT_POLICY == 0)
                            update_lru(w_set, hit_way);
                        else
                            update_plru(w_set, hit_way);
                    end
                end
            end

            endcase
        end
    end

endmodule
