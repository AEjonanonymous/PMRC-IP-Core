/*
 * Copyright (c) 2026 Jonathan Alan Reed
 * Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
 *
 * Module: pmrc_test_bench.sv (Hardware Testbench)
 * Environment: Compile with pmrc_axi_core_parallel_tree.sv 
 * Include: vectors.txt
 * Description: Verification environment for the pmrc_axi_wrapper.
 * Reports reconstructed results and algorithmic layers (log2 k)
 * to maintain parity with the Parallel MRC manuscript.
 */

`timescale 1ns/1ns

`define auto -1

module pmrc_test_bench();
    parameter K  = 128; 
    parameter BW = `auto;
    parameter STAGES_PER_LEVEL = 3;

    localparam ACTUAL_BW = (BW == `auto) ? (K * 20) : BW;

    reg clk;
    reg rst_n;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg [(K*ACTUAL_BW)-1:0] flat_residues;
    reg [(K*ACTUAL_BW)-1:0] flat_moduli;
    reg [((K-1)*ACTUAL_BW)-1:0] flat_lut;
    
    wire [ACTUAL_BW-1:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg  m_axis_tready;

    reg [ACTUAL_BW-1:0] file_buffer [0:(3*K-1)-1];

    initial begin
        $dumpfile("dump.vcd");
      $dumpvars(0, pmrc_test_bench);
        $readmemh("vectors.txt", file_buffer);

        for (int i=0; i<K; i++) begin
            flat_moduli[i*ACTUAL_BW +: ACTUAL_BW]   = file_buffer[i];
            flat_residues[i*ACTUAL_BW +: ACTUAL_BW] = file_buffer[K+i];
        end
        for (int i=0; i<K-1; i++) begin
            flat_lut[i*ACTUAL_BW +: ACTUAL_BW]      = file_buffer[2*K+i];
        end
    end

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst_n = 0;
        s_axis_tvalid = 0;
        m_axis_tready = 1;
        #100;
        rst_n = 1;
        #20;
        
        wait(s_axis_tready);
        @(posedge clk);
        s_axis_tvalid = 1; 
        @(posedge clk);
        s_axis_tvalid = 0;
    end
    
    initial begin
        wait(m_axis_tvalid === 1'b1);
        @(posedge clk);
        $display("\n=========================================================");
      $display("      PARALLEL MRC HARDWARE VERIFICATION REPORT");
        $display("---------------------------------------------------------");
        $display("  SIMULATION SUCCESS: m_axis_tvalid detected");  
        $display("  RECONSTRUCTED X (Hex): %h", m_axis_tdata);
        $display("---------------------------------------------------------");
        $display("  ALGORITHM LAYERS (log2 k): %0d", $clog2(K));
        $display("  TOTAL PIPELINE STAGES:      %0d", STAGES_PER_LEVEL * $clog2(K));
        $display("=========================================================\n");
        #100;
        $finish;
    end

    pmrc_axi_wrapper #(
        .K(K), 
        .BW(BW), 
        .STAGES_PER_LEVEL(STAGES_PER_LEVEL)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata_residues(flat_residues),
        .s_axis_tdata_moduli(flat_moduli),
        .s_axis_tdata_lut(flat_lut),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );


endmodule
