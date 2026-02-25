/*
 * Copyright (c) 2026 Jonathan Alan Reed
 * Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
 *
 * Module: pmrc_core_top.sv
 * Description: Top-level hardware module for the Parallel Mixed-Radix 
 * Conversion (PMRC) core, implementing recursive tree-based 
 * reconstruction with a multi-stage pipeline.
 */

module pmrc_core_top #(
    parameter K = 128,
    parameter BW = 2560,
    parameter BITS_PER_PRIME = 20,
    parameter STAGES_PER_LEVEL = 3 
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire     
             in_valid,
    input  wire [(K*ACTUAL_BW)-1:0] flat_residues,
    input  wire [(K*ACTUAL_BW)-1:0] flat_moduli,
    input  wire [((K-1)*ACTUAL_BW)-1:0] flat_lut,
    output wire [ACTUAL_BW-1:0]     result_coeff,
    output wire                     out_valid
);
  localparam ACTUAL_BW = (BW == 2560) ? (K * BITS_PER_PRIME) : BW;
    localparam LATENCY = STAGES_PER_LEVEL * $clog2(K);

    reg [LATENCY:0] valid_pipe;
 always @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid_pipe <= 0;
 else        valid_pipe <= {valid_pipe[LATENCY-1:0], in_valid};
    end

    wire [ACTUAL_BW-1:0] tree_v, tree_p;
 pmrc_parallel_tree #(
        .K(K), 
        .BW(ACTUAL_BW), 
        .LUT_BASE(0), 
        .TOTAL_K(K),
        .STAGES_PER_LEVEL(STAGES_PER_LEVEL) 
    ) tree_inst (
        .clk(clk), .rst_n(rst_n),
        .flat_v_in(flat_residues), .flat_p_in(flat_moduli), .flat_lut(flat_lut),
        .v_final(tree_v), .p_final(tree_p)
    );
 assign result_coeff = tree_v;
    assign out_valid    = valid_pipe[LATENCY];
 endmodule