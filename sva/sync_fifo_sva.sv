`timescale 1ns/1ps
// Concurrent assertions for sync_fifo, attached to every instance with `bind`.
// They watch internal state (pointers, accept strobes), so they catch
// violations even when the outputs happen to look right.
module sync_fifo_sva #(
    parameter int DATA_W = 8,
    parameter int DEPTH  = 16
) (
    input logic                       clk,
    input logic                       rst_n,
    input logic                       wr_en,
    input logic                       rd_en,
    input logic                       rd_valid,
    input logic [$clog2(DEPTH+1)-1:0] count,
    input logic                       full,
    input logic                       empty,
    input logic                       overflow,
    input logic                       underflow,
    input logic [$clog2(DEPTH)-1:0]   wr_ptr,
    input logic [$clog2(DEPTH)-1:0]   rd_ptr
);
    // ---------------- invariants ----------------
    a_count_range: assert property (@(posedge clk) disable iff (!rst_n)
        int'(count) <= DEPTH)
        else $error("count %0d exceeds DEPTH", count);

    a_flag_defs: assert property (@(posedge clk) disable iff (!rst_n)
        full == (int'(count) == DEPTH) && empty == (int'(count) == 0))
        else $error("full/empty do not match count");

    a_ptr_range: assert property (@(posedge clk) disable iff (!rst_n)
        int'(wr_ptr) < DEPTH && int'(rd_ptr) < DEPTH)
        else $error("pointer out of range");

    // the distance between the pointers is the occupancy (mod DEPTH)
    a_ptr_distance: assert property (@(posedge clk) disable iff (!rst_n)
        ((int'(wr_ptr) - int'(rd_ptr) + DEPTH) % DEPTH) == (int'(count) % DEPTH))
        else $error("pointer distance does not match count");

    // ---------------- occupancy updates ----------------
    a_count_inc: assert property (@(posedge clk) disable iff (!rst_n)
        (wr_en && !full && !(rd_en && !empty)) |=> count == $past(count) + 1)
        else $error("count did not increment on a write");

    a_count_dec: assert property (@(posedge clk) disable iff (!rst_n)
        (rd_en && !empty && !wr_en) |=> count == $past(count) - 1)
        else $error("count did not decrement on a read");

    a_count_hold: assert property (@(posedge clk) disable iff (!rst_n)
        (rd_en && wr_en && !empty) |=> count == $past(count))
        else $error("count changed on a simultaneous read and write");

    // ---------------- error and read strobes ----------------
    a_overflow: assert property (@(posedge clk) disable iff (!rst_n)
        overflow == $past(wr_en && full && !rd_en))
        else $error("overflow pulse wrong");

    a_underflow: assert property (@(posedge clk) disable iff (!rst_n)
        underflow == $past(rd_en && empty))
        else $error("underflow pulse wrong");

    a_rd_valid: assert property (@(posedge clk) disable iff (!rst_n)
        rd_valid == $past(rd_en && !empty))
        else $error("rd_valid wrong");
endmodule

bind sync_fifo sync_fifo_sva #(.DATA_W(DATA_W), .DEPTH(DEPTH)) u_sva (.*);
