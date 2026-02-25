/*
 * Copyright (c) 2026 Jonathan Alan Reed
 * Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
 * Module: pmrc_parallel_tree.sv
 *
 * Description: Logic for the parallel binary merge tree. 
 * Implements pipelined modular arithmetic for reconstruction.
 */

module pmrc_parallel_tree #(
    parameter K = 128,
    parameter BW = 2560,
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