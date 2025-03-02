`default_nettype none

module registers (
    input wire clk,
    input wire rst,

    // Register select and control
    input wire write_en,
    input wire [3:0] reg_sel_a, // First read port select
    input wire [3:0] reg_sel_b, // Second read port select

    // Data ports
    input wire [15:0] write_data,
    output wire [15:0] read_data_a,
    output wire [15:0] read_data_b,
    output wire [15:0] databus,  // Databus output

    // Memory access registers
    output wire [15:0] mar,
    output wire [7:0] mpage,

    // Input/Output flags
    input wire [11:0] input_flags,
    output wire [19:0] output_flags,

    // I/O registers
    output wire [7:0] oreg,
    output wire [7:0] ireg,

    // ALU inputs and output
    output wire [15:0] a_alu_in,
    output wire [15:0] b_alu_in,
    input wire [15:0] aluout,

    // QSPI data input
    input wire [31:0] qspi_data,

    // External inputs
    input wire [7:0] ui_in
);

    // Extract individual input flags
    wire oi = input_flags[0];
    wire rami = input_flags[1];
    wire mari = input_flags[2];
    wire mpagei = input_flags[3];
    wire ai = input_flags[4];
    wire bi = input_flags[5];
    wire ci = input_flags[6];
    wire di = input_flags[7];
    wire ei = input_flags[8];
    wire fi = input_flags[9];
    wire gi = input_flags[10];
    wire hi = input_flags[11];

    // Register declarations
    reg [15:0] areg;
    reg [15:0] breg;
    reg [15:0] creg;
    reg [15:0] dreg;
    reg [15:0] ereg;
    reg [15:0] freg;
    reg [15:0] greg;
    reg [15:0] hreg;
    reg [15:0] mar_reg;
    reg [7:0] mpage_reg;
    reg [7:0] oreg_reg;
    reg [7:0] ireg_reg;

    // Register write logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            areg <= 0;
            breg <= 0;
            creg <= 0;
            dreg <= 0;
            ereg <= 0;
            freg <= 0;
            greg <= 0;
            hreg <= 0;
            mar_reg <= 0;
            mpage_reg <= 0;
            oreg_reg <= 0;
            ireg_reg <= 0;
        end else begin
            // Update input register on every clock cycle
            ireg_reg <= ui_in;

            if (write_en) begin
                // General purpose registers
                if (ai) areg <= write_data;
                if (bi) breg <= write_data;
                if (ci) creg <= write_data;
                if (di) dreg <= write_data;
                if (ei) ereg <= write_data;
                if (fi) freg <= write_data;
                if (gi) greg <= write_data;
                if (hi) hreg <= write_data;

                // Special registers
                if (mari) mar_reg <= write_data;
                if (mpagei) mpage_reg <= write_data[7:0];
                if (oi) oreg_reg <= write_data[7:0];
            end
        end
    end

    // Read port A output
    assign read_data_a = 
        (reg_sel_a == 4'h0) ? areg :
        (reg_sel_a == 4'h1) ? breg :
        (reg_sel_a == 4'h2) ? creg :
        (reg_sel_a == 4'h3) ? dreg :
        (reg_sel_a == 4'h4) ? ereg :
        (reg_sel_a == 4'h5) ? freg :
        (reg_sel_a == 4'h6) ? greg :
        (reg_sel_a == 4'h7) ? hreg : 16'h0;

    // Read port B output
    assign read_data_b = 
        (reg_sel_b == 4'h0) ? areg :
        (reg_sel_b == 4'h1) ? breg :
        (reg_sel_b == 4'h2) ? creg :
        (reg_sel_b == 4'h3) ? dreg :
        (reg_sel_b == 4'h4) ? ereg :
        (reg_sel_b == 4'h5) ? freg :
        (reg_sel_b == 4'h6) ? greg :
        (reg_sel_b == 4'h7) ? hreg : 16'h0;

    // Output assignments
    assign mar = mar_reg;
    assign mpage = mpage_reg;
    assign oreg = oreg_reg;
    assign ireg = ireg_reg;

    // Output flags assignments - these control which registers are selected for operations
    assign output_flags[0] = 1'b0;  // io
    assign output_flags[1] = 1'b0;  // ao
    assign output_flags[2] = 1'b0;  // bo
    assign output_flags[3] = 1'b0;  // co
    assign output_flags[4] = 1'b0;  // doo
    assign output_flags[5] = 1'b0;  // eo
    assign output_flags[6] = 1'b0;  // fo
    assign output_flags[7] = 1'b0;  // go
    assign output_flags[8] = 1'b0;  // ho
    assign output_flags[9] = 1'b0;  // ao2
    assign output_flags[10] = 1'b0; // bo2
    assign output_flags[11] = 1'b0; // co2
    assign output_flags[12] = 1'b0; // doo2
    assign output_flags[13] = 1'b0; // eo2
    assign output_flags[14] = 1'b0; // fo2
    assign output_flags[15] = 1'b0; // go2
    assign output_flags[16] = 1'b0; // ho2
    assign output_flags[17] = 1'b0; // romo
    assign output_flags[18] = 1'b0; // ramo
    assign output_flags[19] = 1'b0; // jmpo

    // Extract individual output flags for clarity
    wire io = output_flags[0];
    wire ao = output_flags[1];
    wire bo = output_flags[2];
    wire co = output_flags[3];
    wire doo = output_flags[4];
    wire eo = output_flags[5];
    wire fo = output_flags[6];
    wire go = output_flags[7];
    wire ho = output_flags[8];
    wire ao2 = output_flags[9];
    wire bo2 = output_flags[10];
    wire co2 = output_flags[11];
    wire doo2 = output_flags[12];
    wire eo2 = output_flags[13];
    wire fo2 = output_flags[14];
    wire go2 = output_flags[15];
    wire ho2 = output_flags[16];
    wire romo = output_flags[17];
    wire ramo = output_flags[18];
    wire jmpo = output_flags[19];

    // ALU input selection logic
    assign a_alu_in = ao ? areg :
                      bo ? breg :
                      co ? creg :
                      doo ? dreg :
                      eo ? ereg :
                      fo ? freg :
                      go ? greg :
                      ho ? hreg : 16'h0;

    assign b_alu_in = ao2 ? areg :
                      bo2 ? breg :
                      co2 ? creg :
                      doo2 ? dreg :
                      eo2 ? ereg :
                      fo2 ? freg :
                      go2 ? greg :
                      ho2 ? hreg : 16'h0;

    // Databus multiplexing logic
    wire aluo = ao | bo | co | doo | eo | fo | go | ho;

    assign databus = aluo ? aluout :
                    (romo || ramo) ? qspi_data[15:0] :
                    io ? {8'b0, ireg_reg} :
                    16'h0;

endmodule
