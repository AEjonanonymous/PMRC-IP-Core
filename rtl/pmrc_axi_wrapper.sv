/*
 * Copyright (c) 2026 Jonathan A
 * Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
 *
 * Module: pmrc_axi_wrapper.sv
 * Description: AXI4-Stream wrapper for the PMRC core, providing flow control and residency tracking.
 */

module pmrc_axi_wrapper #(
    parameter K = 128,
    parameter BW = 2560,
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
  localparam ACTUAL_BW = (BW == 2560) ? (K * BITS_PER_PRIME) : BW;
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