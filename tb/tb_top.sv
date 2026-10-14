`timescale 1ns/1ps
// Runs the FIFO test on three configurations in parallel:
//   8 x 16  (power-of-two depth)
//  16 x 7   (non-power-of-two depth: pointers must wrap at 6, not 7)
//  32 x 2   (smallest legal depth: full and empty are one write apart)
module tb_top;
    logic done_a, done_b, done_c;
    int   err_a, err_b, err_c;

    fifo_test #(.DATA_W(8),  .DEPTH(16), .SEED(32'h0000_1234)) cfg_a (.done(done_a), .errors(err_a));
    fifo_test #(.DATA_W(16), .DEPTH(7),  .SEED(32'h00C0_FFEE)) cfg_b (.done(done_b), .errors(err_b));
    fifo_test #(.DATA_W(32), .DEPTH(2),  .SEED(32'hDEAD_BEEF)) cfg_c (.done(done_c), .errors(err_c));

    initial begin
`ifdef DUMP
        $dumpfile("sync_fifo.vcd");
        $dumpvars(0, tb_top);
`endif
        wait (done_a && done_b && done_c);
        $display("--------------------------------------------------");
        if (err_a + err_b + err_c == 0) $display("ALL TESTS PASSED");
        else                            $display("TESTS FAILED (%0d errors)", err_a + err_b + err_c);
        $finish;
    end

    initial begin
        #10ms;
        $display("TIMEOUT");
        $display("TESTS FAILED");
        $finish;
    end
endmodule
