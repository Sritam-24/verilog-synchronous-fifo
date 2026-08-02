// =============================================================
// Module      : sync_fifo
// Description : Parameterized synchronous FIFO (single clock domain)
//               - Default: 8-bit wide, 16-deep
//               - Circular buffer with binary read/write pointers
//               - Extra MSB "wrap bit" on each pointer distinguishes
//                 full vs empty when address bits are equal
// =============================================================
module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16,                  // must be a power of 2
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                    clk,
    input  wire                    rst_n,        // active-low sync reset

    // write side
    input  wire                    wr_en,
    input  wire [DATA_WIDTH-1:0]   din,
    output wire                    full,

    // read side
    input  wire                    rd_en,
    output reg  [DATA_WIDTH-1:0]   dout,
    output wire                    empty,

    // status (bonus, handy for verification/debug)
    output wire [ADDR_WIDTH:0]     fifo_count
);

    // ---------------------------------------------------------
    // Memory array
    // ---------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // ---------------------------------------------------------
    // Pointers: width = ADDR_WIDTH+1
    //   - lower ADDR_WIDTH bits -> actual memory address
    //   - MSB (wrap bit)        -> toggles every time the pointer
    //                              wraps around the end of memory
    // ---------------------------------------------------------
    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;

    wire [ADDR_WIDTH-1:0] wr_addr = wr_ptr[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] rd_addr = rd_ptr[ADDR_WIDTH-1:0];

    // Effective (qualified) enables: block writes when full, reads when empty
    wire wr_valid = wr_en & ~full;
    wire rd_valid = rd_en & ~empty;

    // ---------------------------------------------------------
    // Write logic
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= {(ADDR_WIDTH+1){1'b0}};
        end else if (wr_valid) begin
            mem[wr_addr] <= din;
            wr_ptr       <= wr_ptr + 1'b1;
        end
    end

    // ---------------------------------------------------------
    // Read logic (synchronous read, registered dout)
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr <= {(ADDR_WIDTH+1){1'b0}};
            dout   <= {DATA_WIDTH{1'b0}};
        end else if (rd_valid) begin
            dout   <= mem[rd_addr];
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    // ---------------------------------------------------------
    // Full  : same address, but wrap (MSB) bits differ
    // Empty : pointers fully equal (address AND wrap bit)
    // ---------------------------------------------------------
    assign full  = (wr_addr == rd_addr) && (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]);
    assign empty = (wr_ptr == rd_ptr);

    assign fifo_count = wr_ptr - rd_ptr;

endmodule
