`timescale 1ns/1ps
// Parameterized synchronous FIFO.
//
//  * Circular read/write pointers that wrap explicitly at DEPTH - 1, so any
//    DEPTH >= 2 works (not only powers of two).
//  * An occupancy counter drives `count`, `full` and `empty`.
//  * Registered read port: when a read is accepted, rd_data updates on that
//    clock edge and rd_valid is high for the following cycle.
//
// Corner-case policy:
//  * write while full  -> dropped, one-cycle `overflow` pulse,
//                         unless a read is accepted in the same cycle (both proceed)
//  * read while empty  -> ignored, one-cycle `underflow` pulse
//                         (a simultaneous write is still accepted)
//  * read + write      -> both accepted, occupancy unchanged
module sync_fifo #(
    parameter int DATA_W = 8,
    parameter int DEPTH  = 16                       // >= 2
) (
    input  logic                       clk,
    input  logic                       rst_n,       // asynchronous, active low

    input  logic                       wr_en,
    input  logic [DATA_W-1:0]          wr_data,

    input  logic                       rd_en,
    output logic [DATA_W-1:0]          rd_data,
    output logic                       rd_valid,

    output logic [$clog2(DEPTH+1)-1:0] count,       // occupancy, 0 .. DEPTH
    output logic                       full,
    output logic                       empty,
    output logic                       overflow,
    output logic                       underflow
);
    localparam int PTR_W = $clog2(DEPTH);
    localparam int CNT_W = $clog2(DEPTH + 1);

    logic [DATA_W-1:0] mem [0:DEPTH-1];
    logic [PTR_W-1:0]  wr_ptr, rd_ptr;
    logic              wr_accept, rd_accept;

    assign full  = (count == CNT_W'(DEPTH));
    assign empty = (count == '0);

    assign rd_accept = rd_en && !empty;
    assign wr_accept = wr_en && (!full || rd_en);   // a read frees a slot this cycle

    function automatic logic [PTR_W-1:0] next_ptr(input logic [PTR_W-1:0] ptr);
        next_ptr = (ptr == PTR_W'(DEPTH - 1)) ? '0 : ptr + 1'b1;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr    <= '0;
            rd_ptr    <= '0;
            count     <= '0;
            rd_data   <= '0;
            rd_valid  <= 1'b0;
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end else begin
            if (wr_accept)
                wr_ptr <= next_ptr(wr_ptr);
            if (rd_accept) begin
                rd_ptr  <= next_ptr(rd_ptr);
                rd_data <= mem[rd_ptr];
            end
            rd_valid <= rd_accept;

            case ({wr_accept, rd_accept})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;            // both or neither
            endcase

            overflow  <= wr_en && full && !rd_en;
            underflow <= rd_en && empty;
        end
    end

    // storage array, not reset
    always_ff @(posedge clk) begin
        if (wr_accept)
            mem[wr_ptr] <= wr_data;
    end
endmodule
