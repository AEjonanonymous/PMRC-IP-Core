/*
 * Copyright (c) 2026 Jonathan Alan Reed
 * Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
 *
 * Module: pmrc_axi_core_parallel_tree.sv
 * Description: High-performance, pipelined hardware Parallel Mixed-Radix 
 * Conversion (PMRC) core. Implements a recursive tree-based 
 * reconstruction with configurable pipeline depth per level 
 * for high-frequency operation.
 */

`timescale 1ns/1ns

`define auto -1

module pmrc_axi_wrapper #(
    parameter K = 128,
    parameter BW = `auto,
    parameter BITS_PER_PRIME = 20,
    parameter FIFO_DEPTH = 128,
    parameter STAGES_PER_LEVEL = 3 
)(
    input  wire                     clk,
    input  wire                     rst_n,

  
   // AXI4-Stream Slave Interface
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire [(K*ACTUAL_BW)-1:0] s_axis_tdata_residues,
    input  wire [(K*ACTUAL_BW)-1:0] s_axis_tdata_moduli,
    input  wire [((K-1)*ACTUAL_BW)-1:0] s_axis_tdata_lut,

    // AXI4-Stream Master Interface
    output wire      
                m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire [ACTUAL_BW-1:0]     m_axis_tdata
);
 localparam ACTUAL_BW = (BW == `auto) ? (K * BITS_PER_PRIME) : BW;
    localparam LATENCY   = STAGES_PER_LEVEL * $clog2(K);

    wire core_out_valid;
    wire [ACTUAL_BW-1:0] core_result;
    reg [$clog2(FIFO_DEPTH+1)-1:0] flight_count;
 assign s_axis_tready = (flight_count + LATENCY < FIFO_DEPTH);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flight_count <= 0;
 end else begin
            case ({ (s_axis_tvalid && s_axis_tready), (m_axis_tvalid && m_axis_tready) })
                2'b10: flight_count <= flight_count + 1;
 2'b01: flight_count <= flight_count - 1;
                default: flight_count <= flight_count;
 endcase
        end
    end

    pmrc_core_top #(
        .K(K),
        .BW(BW),
        .BITS_PER_PRIME(BITS_PER_PRIME),
        .STAGES_PER_LEVEL(STAGES_PER_LEVEL) 
    ) dut_core (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(s_axis_tvalid && s_axis_tready),
        .flat_residues(s_axis_tdata_residues),
       
  .flat_moduli(s_axis_tdata_moduli),
        .flat_lut(s_axis_tdata_lut),
        .result_coeff(core_result),
        .out_valid(core_out_valid)
    );
 assign m_axis_tvalid = core_out_valid;
    assign m_axis_tdata  = core_result;

endmodule

module pmrc_core_top #(
    parameter K = 128,
    parameter BW = `auto,
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
 localparam ACTUAL_BW = (BW == `auto) ? (K * BITS_PER_PRIME) : BW;
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

module pmrc_parallel_tree #(
    parameter K = 128,
    parameter BW = 1280,
    parameter LUT_BASE = 0,
    parameter TOTAL_K = 128,
    parameter STAGES_PER_LEVEL = 3 
)(
    input  wire                      clk,
    input  wire                      rst_n,
   
  input  wire [(K*BW)-1:0]         flat_v_in,
    input  wire [(K*BW)-1:0]         flat_p_in,
    input  wire [((TOTAL_K-1)*BW)-1:0] flat_lut,
    output wire [BW-1:0]             v_final,
    output wire [BW-1:0]             p_final
);
 // Calculate sub-stages per math step
    localparam S = STAGES_PER_LEVEL / 3;
 generate
        if (K == 1) begin : base_case
            assign v_final = flat_v_in[BW-1:0];
 assign p_final = flat_p_in[BW-1:0];
        end else begin : recursive_step
            localparam K_LEFT = K / 2;
 localparam K_RIGHT = K - K_LEFT;
            
            wire [BW-1:0] v_l, p_l, v_r, p_r;
 pmrc_parallel_tree #(
                .K(K_LEFT), .BW(BW), 
                .LUT_BASE(LUT_BASE), .TOTAL_K(TOTAL_K),
                .STAGES_PER_LEVEL(STAGES_PER_LEVEL)
            ) left (
                .clk(clk), .rst_n(rst_n),
                .flat_v_in(flat_v_in[(K_LEFT*BW)-1:0]),
 
                .flat_p_in(flat_p_in[(K_LEFT*BW)-1:0]),
                .flat_lut(flat_lut), .v_final(v_l), .p_final(p_l)
            );
 pmrc_parallel_tree #(
                .K(K_RIGHT), .BW(BW), 
                .LUT_BASE(LUT_BASE + (K_LEFT > 1 ? K_LEFT-1 : 0)), .TOTAL_K(TOTAL_K),
                .STAGES_PER_LEVEL(STAGES_PER_LEVEL)
            ) right (
                .clk(clk), .rst_n(rst_n),
         
        .flat_v_in(flat_v_in[(K*BW)-1:(K_LEFT*BW)]),
                .flat_p_in(flat_p_in[(K*BW)-1:(K_LEFT*BW)]),
                .flat_lut(flat_lut), .v_final(v_r), .p_final(p_r)
            );
 // Create Shift Register Arrays (Pipes) to keep data synchronized
            reg [BW-1:0] v_l_pipe1 [0:S-1], p_l_pipe1 [0:S-1], p_r_pipe1 [0:S-1], diff_pipe1 [0:S-1];
 reg [BW-1:0] v_l_pipe2 [0:S-1], p_l_pipe2 [0:S-1], p_r_pipe2 [0:S-1], k_val_pipe2 [0:S-1];
            reg [BW-1:0] v_out_pipe3 [0:S-1], p_out_pipe3 [0:S-1];
 wire [BW-1:0] inv = flat_lut[(LUT_BASE + K - 2)*BW +: BW];
 // --- Pipeline Stage 1: Modular Subtraction ---
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for(int i=0; i<S; i++) begin diff_pipe1[i] <= 0;
 v_l_pipe1[i] <= 0; p_l_pipe1[i] <= 0; p_r_pipe1[i] <= 0; end
                end else begin
                    // Math logic
                    if (v_r >= v_l) diff_pipe1[0] <= (v_r - v_l) % p_r;
 else            diff_pipe1[0] <= (p_r - ((v_l - v_r) % p_r)) % p_r;
 // Pipe entrance
                    v_l_pipe1[0] <= v_l;
 p_l_pipe1[0] <= p_l; p_r_pipe1[0] <= p_r;
                    // Move through pipe
                    for(int i=1; i<S; i++) begin
                        diff_pipe1[i] <= diff_pipe1[i-1];
 p_l_pipe1[i] <= p_l_pipe1[i-1]; p_r_pipe1[i] <= p_r_pipe1[i-1];
                    end
                end
            end

            // --- Pipeline Stage 2: Modular Multiplication ---
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
        
             for(int i=0; i<S; i++) begin k_val_pipe2[i] <= 0;
 v_l_pipe2[i] <= 0; p_l_pipe2[i] <= 0; p_r_pipe2[i] <= 0; end
                end else begin
                    // Math logic (takes input from end of pipe 1)
                    k_val_pipe2[0] <= (diff_pipe1[S-1] * inv) % p_r_pipe1[S-1];
 v_l_pipe2[0] <= v_l_pipe1[S-1]; p_l_pipe2[0] <= p_l_pipe1[S-1]; p_r_pipe2[0] <= p_r_pipe1[S-1];
                    // Move through pipe
                    for(int i=1; i<S; i++) begin
                        k_val_pipe2[i] <= k_val_pipe2[i-1];
 v_l_pipe2[i] <= v_l_pipe2[i-1]; p_l_pipe2[i] <= p_l_pipe2[i-1]; p_r_pipe2[i] <= p_r_pipe2[i-1];
                    end
                end
            end

            // --- Pipeline Stage 3: Final Accumulation ---
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
        
             for(int i=0; i<S; i++) begin v_out_pipe3[i] <= 0;
 p_out_pipe3[i] <= 0; end
                end else begin
                    // Math logic (takes input from end of pipe 2)
                    v_out_pipe3[0] <= v_l_pipe2[S-1] + (p_l_pipe2[S-1] * k_val_pipe2[S-1]);
 p_out_pipe3[0] <= p_l_pipe2[S-1] * p_r_pipe2[S-1];
                    // Move through pipe
                    for(int i=1; i<S; i++) begin
                        v_out_pipe3[i] <= v_out_pipe3[i-1];
 p_out_pipe3[i] <= p_out_pipe3[i-1];
                    end
                end
            end

            assign v_final = v_out_pipe3[S-1];
 assign p_final = p_out_pipe3[S-1];
        end
    endgenerate
endmodule