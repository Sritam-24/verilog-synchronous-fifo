// =============================================================
// Testbench: tb_sync_fifo
// 12 structured test cases:
//   TC1  : Reset behavior
//   TC2  : Single write, then check not empty
//   TC3  : Single read after single write (data integrity)
//   TC4  : Back-to-back write sequencing (fill partially)
//   TC5  : Back-to-back read sequencing (drain partially)
//   TC6  : Fill FIFO completely -> full flag assertion
//   TC7  : Overflow handling -> write while full is ignored
//   TC8  : Drain FIFO completely -> empty flag assertion
//   TC9  : Underflow handling -> read while empty is ignored
//   TC10 : Wrap-around addressing (write/read past DEPTH boundary)
//   TC11 : Simultaneous read+write when neither full nor empty
//   TC12 : Simultaneous read+write when FIFO is full (full->full-1)
// =============================================================
`timescale 1ns/1ps

module tb_sync_fifo;

    localparam DATA_WIDTH = 8;
    localparam DEPTH      = 16;
    localparam ADDR_WIDTH = 4;

    reg                     clk;
    reg                     rst_n;
    reg                     wr_en;
    reg                     rd_en;
    reg  [DATA_WIDTH-1:0]   din;
    wire [DATA_WIDTH-1:0]   dout;
    wire                    full;
    wire                    empty;
    wire [ADDR_WIDTH:0]     fifo_count;

    integer errors;
    integer i;
    reg [DATA_WIDTH-1:0] expected_q [0:255];
    integer eq_head, eq_tail;

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) DUT (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .din(din), .full(full),
        .rd_en(rd_en), .dout(dout), .empty(empty),
        .fifo_count(fifo_count)
    );

    // 100 MHz clock
    always #5 clk = ~clk;

    task automatic do_write(input [DATA_WIDTH-1:0] data);
        begin
            @(negedge clk);
            wr_en = 1'b1; din = data; rd_en = 1'b0;
            @(negedge clk);
            wr_en = 1'b0;
        end
    endtask

    task automatic do_read;
        begin
            @(negedge clk);
            rd_en = 1'b1; wr_en = 1'b0;
            @(negedge clk);
            rd_en = 1'b0;
        end
    endtask

    task check(input cond, input [8*40:1] name);
        begin
            if (cond)
                $display("[PASS] %0s", name);
            else begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; wr_en = 0; rd_en = 0; din = 0;
        errors = 0;

        // ---------------- TC1: Reset behavior ----------------
        repeat (3) @(negedge clk);
        check(empty === 1'b1, "TC1a: empty asserted after reset");
        check(full  === 1'b0, "TC1b: full deasserted after reset");
        check(dout  === 8'h00, "TC1c: dout cleared after reset");
        rst_n = 1'b1;
        @(negedge clk);

        // ---------------- TC2: Single write --------------------
        do_write(8'hA5);
        check(empty === 1'b0, "TC2: empty deasserted after single write");

        // ---------------- TC3: Single read (data integrity) ---
        do_read();
        check(dout === 8'hA5, "TC3: read data matches written data");
        check(empty === 1'b1, "TC3b: empty reasserted after draining");

        // ---------------- TC4: Burst write (partial fill) -----
        for (i = 0; i < 5; i = i + 1)
            do_write(i[7:0] + 8'h10);
        check(fifo_count == 5, "TC4: fifo_count == 5 after 5 writes");
        check(full === 1'b0,   "TC4b: not full after partial fill");

        // ---------------- TC5: Burst read (partial drain) -----
        for (i = 0; i < 3; i = i + 1) begin
            do_read();
            check(dout === (i[7:0] + 8'h10), "TC5: sequential read data correct");
        end
        check(fifo_count == 2, "TC5b: fifo_count == 2 after draining 3 of 5");

        // drain remaining 2 to start clean
        do_read(); do_read();
        check(empty === 1'b1, "TC5c: empty after full drain");

        // ---------------- TC6: Fill completely -> full --------
        for (i = 0; i < DEPTH; i = i + 1)
            do_write(i[7:0]);
        check(full === 1'b1,       "TC6a: full asserted after 16 writes");
        check(fifo_count == DEPTH, "TC6b: fifo_count == DEPTH when full");

        // ---------------- TC7: Overflow handling ---------------
        do_write(8'hFF); // should be ignored, FIFO already full
        check(full === 1'b1,       "TC7a: still full after overflow write attempt");
        check(fifo_count == DEPTH, "TC7b: count unchanged after overflow write attempt");

        // ---------------- TC8: Drain completely -> empty -------
        for (i = 0; i < DEPTH; i = i + 1) begin
            do_read();
            check(dout === i[7:0], "TC8: FIFO order preserved (FIFO not LIFO)");
        end
        check(empty === 1'b1, "TC8b: empty asserted after full drain");

        // ---------------- TC9: Underflow handling --------------
        do_read(); // should be ignored, FIFO already empty
        check(empty === 1'b1, "TC9a: still empty after underflow read attempt");
        check(dout === (DEPTH-1), "TC9b: dout holds last valid value, unchanged on underflow");

        // ---------------- TC10: Wrap-around addressing ---------
        // FIFO pointers are already at DEPTH (wrapped once from TC6-TC8).
        // Write 10, read 6, write 10 more -> forces wr_ptr to wrap past
        // the physical end of the memory array again.
        for (i = 0; i < 10; i = i + 1)
            do_write(8'h50 + i[7:0]);
        for (i = 0; i < 6; i = i + 1) begin
            do_read();
            check(dout === (8'h50 + i[7:0]), "TC10a: correct data pre-wrap");
        end
        for (i = 0; i < 10; i = i + 1)
            do_write(8'h70 + i[7:0]);   // this batch wraps the write pointer
        check(fifo_count == 14, "TC10b: fifo_count correct after wrap writes");
        for (i = 0; i < 4; i = i + 1) begin
            do_read();
            check(dout === (8'h50 + 6 + i[7:0]), "TC10c: correct data spanning wrap boundary");
        end

        // drain remainder to reach a known (empty) state
        while (!empty) do_read();
        check(empty === 1'b1, "TC10d: empty after full drain post-wrap");

        // ---------------- TC11: Simultaneous R/W (mid-fill) ----
        for (i = 0; i < 4; i = i + 1)
            do_write(8'hC0 + i[7:0]); // count = 4
        @(negedge clk);
        wr_en = 1'b1; din = 8'hDD; rd_en = 1'b1; // simultaneous write+read
        @(negedge clk);
        wr_en = 1'b0; rd_en = 1'b0;
        check(dout === 8'hC0, "TC11a: read returns oldest data during simultaneous R/W");
        check(fifo_count == 4, "TC11b: count stays same during simultaneous R/W (not full/empty)");

        while (!empty) do_read(); // clean drain

        // ---------------- TC12: Simultaneous R/W while FULL ----
        for (i = 0; i < DEPTH; i = i + 1)
            do_write(8'hE0 + i[7:0]);
        check(full === 1'b1, "TC12a: full before simultaneous R/W test");
        @(negedge clk);
        wr_en = 1'b1; din = 8'hAA; rd_en = 1'b1; // read frees a slot, write fills it
        @(negedge clk);
        wr_en = 1'b0; rd_en = 1'b0;
        check(full === 1'b1,       "TC12b: FIFO remains full (one out, one in)");
        check(fifo_count == DEPTH, "TC12c: count stays at DEPTH during simultaneous R/W while full");
        check(dout === 8'hE0,      "TC12d: correct oldest data read out during full R/W");

        while (!empty) do_read(); // clean drain

        // ---------------- Summary ------------------------------
        if (errors == 0)
            $display("\n=========== ALL 12 TEST CASES PASSED ===========\n");
        else
            $display("\n=========== %0d CHECK(S) FAILED ===========\n", errors);

        $finish;
    end

    // Safety timeout
    initial begin
        #20000;
        $display("ERROR: Testbench timeout");
        $finish;
    end

endmodule
