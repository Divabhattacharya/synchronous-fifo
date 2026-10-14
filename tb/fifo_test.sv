`timescale 1ns/1ps
// Self-checking test of one sync_fifo configuration.
//
// Every cycle goes through `cycle()`, which drives the inputs, predicts the
// result with a reference queue (the scoreboard model), and checks every DUT
// output after the clock edge:
//   rd_valid / rd_data (and therefore ordering), count, full, empty,
//   overflow, underflow.
//
// Tests: reset, fill + overflow, drain + underflow, simultaneous read/write at
// empty / mid / full, pointer wraparound, randomized traffic in several
// phases, and an asynchronous reset with data inside. Coverage goals are
// checked at the end, so a test that never reaches a corner case fails.
module fifo_test #(
    parameter int          DATA_W = 8,
    parameter int          DEPTH  = 16,
    parameter logic [31:0] SEED   = 32'h1
) (
    output logic done,
    output int   errors
);
    localparam int CNT_W = $clog2(DEPTH + 1);

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    logic              clk     = 1'b0;
    logic              rst_n   = 1'b0;
    logic              wr_en   = 1'b0;
    logic              rd_en   = 1'b0;
    logic [DATA_W-1:0] wr_data = '0;
    logic [DATA_W-1:0] rd_data;
    logic              rd_valid, full, empty, overflow, underflow;
    logic [CNT_W-1:0]  count;

    sync_fifo #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (.*);

    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Deterministic PRNG (xorshift32), independent of the simulator
    // ------------------------------------------------------------------
    logic [31:0] rng = SEED;

    function automatic logic [31:0] rand32();
        rng ^= rng << 13;
        rng ^= rng >> 17;
        rng ^= rng << 5;
        return rng;
    endfunction

    function automatic bit chance(int percent);
        return (rand32() % 100) < percent;
    endfunction

    // ------------------------------------------------------------------
    // Scoreboard: reference queue + checker
    // ------------------------------------------------------------------
    logic [DATA_W-1:0] model[$];
    logic [DATA_W-1:0] exp_rd_data = '0;      // rd_data holds its last value
    int                n_checks = 0;

    task automatic check(bit ok, string what);
        n_checks++;
        if (!ok) begin
            errors++;
            if (errors <= 10)
                $display("[DATA_W=%0d DEPTH=%0d] %0t FAIL %s", DATA_W, DEPTH, $time, what);
        end
    endtask

    // coverage
    int n_cycles, n_writes, n_reads, n_overflow, n_underflow;
    int n_full_cycles, n_rw_empty, n_rw_mid, n_rw_full, n_wr_wraps, n_rd_wraps;

    // One clock cycle. Called on a falling edge, returns on the next one.
    task automatic cycle(bit wr, bit rd);
        logic [DATA_W-1:0] data = DATA_W'(rand32());
        int size;
        bit exp_wr, exp_rd, exp_ovf, exp_unf;

        wr_en   = wr;
        rd_en   = rd;
        wr_data = data;

        // predict from the model's state before the edge
        size    = model.size();
        exp_rd  = rd && size > 0;
        exp_wr  = wr && (size < DEPTH || rd);
        exp_ovf = wr && size == DEPTH && !rd;
        exp_unf = rd && size == 0;

        n_cycles++;
        n_writes      += int'(exp_wr);
        n_reads       += int'(exp_rd);
        n_overflow    += int'(exp_ovf);
        n_underflow   += int'(exp_unf);
        n_full_cycles += int'(size == DEPTH);
        if (wr && rd) begin
            if (size == 0)          n_rw_empty++;
            else if (size == DEPTH) n_rw_full++;
            else                    n_rw_mid++;
        end
        if (exp_wr && int'(dut.wr_ptr) == DEPTH - 1) n_wr_wraps++;
        if (exp_rd && int'(dut.rd_ptr) == DEPTH - 1) n_rd_wraps++;

        @(posedge clk);
        if (exp_rd) exp_rd_data = model.pop_front();
        if (exp_wr) model.push_back(data);
        #1;

        check(rd_valid  === exp_rd,                    "rd_valid");
        check(rd_data   === exp_rd_data,               "rd_data (ordering)");
        check(count     === CNT_W'(model.size()),      "count");
        check(full      === (model.size() == DEPTH),   "full");
        check(empty     === (model.size() == 0),       "empty");
        check(overflow  === exp_ovf,                   "overflow");
        check(underflow === exp_unf,                   "underflow");

        @(negedge clk);
        wr_en = 1'b0;
        rd_en = 1'b0;
    endtask

    // Asynchronous reset in the middle of a cycle. Called on a falling edge.
    task automatic async_reset();
        #2 rst_n = 1'b0;
        #1;
        check(count === '0 && empty && !full,             "reset clears occupancy");
        check(!rd_valid && !overflow && !underflow,       "reset clears strobes");
        check(rd_data === '0,                             "reset clears rd_data");
        model.delete();
        exp_rd_data = '0;
        @(negedge clk);
        rst_n = 1'b1;
    endtask

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------
    task automatic test_fill_and_overflow();
        for (int i = 0; i < DEPTH; i++) cycle(1, 0);     // full exactly at DEPTH
        repeat (3) cycle(1, 0);                          // dropped, overflow pulses
    endtask

    task automatic test_drain_and_underflow();
        for (int i = 0; i < DEPTH; i++) cycle(0, 1);     // data comes out in order
        repeat (3) cycle(0, 1);                          // ignored, underflow pulses
    endtask

    task automatic test_simultaneous();
        cycle(1, 1);                                     // at empty: underflow, write accepted
        cycle(1, 1);                                     // occupancy 1: both accepted
        while (model.size() < DEPTH) cycle(1, 0);
        repeat (3) cycle(1, 1);                          // at full: both accepted, no overflow
        while (model.size() > 0) cycle(0, 1);
    endtask

    task automatic test_wraparound();
        while (model.size() < DEPTH / 2) cycle(1, 0);
        repeat (8 * DEPTH) cycle(1, 1);                  // pointers wrap 8 times
        while (model.size() > 0) cycle(0, 1);
    endtask

    // traffic phases: {write %, read %, cycles}
    task automatic test_random();
        int phases[6][3] = '{'{90, 10, 3000}, '{10, 90, 3000}, '{50, 50, 4000},
                             '{80, 80, 4000}, '{30, 30, 3000}, '{60, 40, 3000}};
        foreach (phases[p])
            repeat (phases[p][2]) begin
                bit wr = chance(phases[p][0]);           // one draw per statement keeps
                bit rd = chance(phases[p][1]);           // the random stream reproducible
                cycle(wr, rd);
            end
        while (model.size() > 0) cycle(0, 1);
    endtask

    task automatic test_reset_with_data();
        for (int r = 0; r < 4; r++) begin
            repeat ((rand32() % DEPTH) + 1) cycle(1, chance(20));
            // make sure each strobe is active at the moment reset hits
            case (r)
                0: cycle(0, 1);                                                    // rd_valid
                1: begin while (model.size() < DEPTH) cycle(1, 0); cycle(1, 0); end  // overflow
                2: begin while (model.size() > 0) cycle(0, 1); cycle(0, 1); end       // underflow
                default: cycle(1, 1);
            endcase
            async_reset();
            // no stale data may come out after reset
            repeat (3) cycle(1, 0);
            repeat (4) cycle(0, 1);
        end
    endtask

    task automatic require(int value, string goal);
        check(value > 0, {"coverage goal not reached: ", goal});
    endtask

    initial begin
        done   = 1'b0;
        errors = 0;

        repeat (2) @(negedge clk);
        check(count === '0 && empty && !full && !rd_valid, "power-on reset values");
        rst_n = 1'b1;
        @(negedge clk);

        test_fill_and_overflow();
        test_drain_and_underflow();
        test_simultaneous();
        test_wraparound();
        test_random();
        test_reset_with_data();

        require(n_overflow,    "overflow");
        require(n_underflow,   "underflow");
        require(n_full_cycles, "full");
        require(n_rw_empty,    "read+write at empty");
        require(n_rw_mid,      "read+write at mid level");
        require(n_rw_full,     "read+write at full");
        require(n_wr_wraps,    "write pointer wrap");
        require(n_rd_wraps,    "read pointer wrap");

        $display("[DATA_W=%2d DEPTH=%2d] %6d cycles  %6d writes  %6d reads  %5d overflow  %5d underflow  %4d r+w@full  %4d r+w@empty  %5d wraps  %7d checks  %0d errors",
                 DATA_W, DEPTH, n_cycles, n_writes, n_reads, n_overflow, n_underflow,
                 n_rw_full, n_rw_empty, n_wr_wraps, n_checks, errors);
        done = 1'b1;
    end
endmodule
