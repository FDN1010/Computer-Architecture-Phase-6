module DATA_MEMORY (
    input i_clk,
    input i_rstn,
    input [31:0] iAddress,
    input [31:0] i_cpu_data,
    input [2:0] i_funct,
    input i_write,
    input i_read,
    output [31:0] o_cpu_data
);

    localparam B = 8;
    localparam K = 1024;
    
    reg [B-1:0] rDataMem [0:(K*4)-1]; // 4KB data memory, byte-addressable

    initial begin
        $readmemh("data.txt", rDataMem);
    end

    // Synchronous write
    always @(posedge i_clk) begin
        if (i_write) begin
            case (i_funct)
                3'b000: begin // SB - store byte
                    rDataMem[iAddress] <= i_cpu_data[7:0];
                end
                3'b001: begin // SH - store halfword
                    rDataMem[iAddress]     <= i_cpu_data[7:0];
                    rDataMem[iAddress + 1] <= i_cpu_data[15:8];
                end
                3'b010: begin // SW - store word
                    rDataMem[iAddress]     <= i_cpu_data[7:0];
                    rDataMem[iAddress + 1] <= i_cpu_data[15:8];
                    rDataMem[iAddress + 2] <= i_cpu_data[23:16];
                    rDataMem[iAddress + 3] <= i_cpu_data[31:24];
                end
                default: begin end
            endcase
        end
    end

    // Asynchronous (combinational) read
    reg [31:0] readData;
    always @(*) begin
        readData = 32'b0;
        if (i_read) begin
            case (i_funct)
                3'b000: // LB - load byte (sign-extended)
                    readData = {{24{rDataMem[iAddress][7]}}, rDataMem[iAddress]};
                3'b001: // LH - load halfword (sign-extended)
                    readData = {{16{rDataMem[iAddress+1][7]}},
                                rDataMem[iAddress+1], rDataMem[iAddress]};
                3'b010: // LW - load word
                    readData = {rDataMem[iAddress+3], rDataMem[iAddress+2],
                                rDataMem[iAddress+1], rDataMem[iAddress]};
                3'b100: // LBU - load byte unsigned
                    readData = {24'b0, rDataMem[iAddress]};
                3'b101: // LHU - load halfword unsigned
                    readData = {16'b0, rDataMem[iAddress+1], rDataMem[iAddress]};
                default: readData = 32'b0;
            endcase
        end
    end

    assign o_cpu_data = readData;

endmodule
