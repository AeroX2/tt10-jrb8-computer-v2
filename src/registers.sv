`default_nettype none

module registers (
    input wire clk,
    input wire rst,

    input wire [FLAGS_LEN-1:0] flags,
    input wire [7:0] ui_in,
    input wire write_en,

    input wire [15:0] rom,
    input wire [15:0] ram,
    input wire [15:0] aluout,
    output wire [15:0] databus,

    output [15:0] alu_a,
    output [15:0] alu_b,

    output [15:0] mar,
    output [7:0] mpage,
    output [7:0] oreg,
    output [7:0] ireg
);
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

    // Input flags
    wire ai = flags[0];
    wire bi = flags[1];
    wire ci = flags[2];
    wire di = flags[3];
    wire ei = flags[4];
    wire fi = flags[5];
    wire gi = flags[6];
    wire hi = flags[7];
    wire rami = flags[8];
    wire mari = flags[9];
    wire mpagei = flags[10];
    wire oi = flags[11];

    // Output flags
    wire ao = flags[12];
    wire bo = flags[13];
    wire co = flags[14];
    wire doo = flags[15];
    wire eo = flags[16];
    wire fo = flags[17];
    wire go = flags[18];
    wire ho = flags[19];
    wire aluo = flags[20];
    wire romo = flags[21];
    wire ramo = flags[22];
    wire jmpo = flags[23];
    wire io = flags[24];

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
            if (write_en) begin
                // General purpose registers
                if (ai) areg <= databus;
                if (bi) breg <= databus;
                if (ci) creg <= databus;
                if (di) dreg <= databus;
                if (ei) ereg <= databus;
                if (fi) freg <= databus;
                if (gi) greg <= databus;
                if (hi) hreg <= databus;

                // Special registers
                if (mari) mar_reg <= databus;
                if (mpagei) mpage_reg <= databus[7:0];
                if (oi) oreg_reg <= databus[7:0];
            end
        end
    end

    // Output assignments
    assign mar = mar_reg;
    assign mpage = mpage_reg;
    assign oreg = oreg_reg;
    assign ireg = ireg_reg;

    assign alu_a = ai ? areg :
                      bi ? breg :
                      ci ? creg :
                      di ? dreg :
                      ei ? ereg :
                      fi ? freg :
                      gi ? greg :
                      hi ? hreg : 16'h0;

    assign alu_b = ao ? areg :
                      bo ? breg :
                      co ? creg :
                      doo ? dreg :
                      eo ? ereg :
                      fo ? freg :
                      go ? greg :
                      ho ? hreg : 16'h0;

    assign databus = aluo ? aluout :
                     ao ? areg :
                     bo ? breg :
                     co ? creg :
                     doo ? dreg :
                     eo ? ereg :
                     fo ? freg :
                     go ? greg :
                     ho ? hreg :
                     romo ? rom :
                     ramo ? ram :
                     io ? {8'b0, ui_in} :
                     16'h0;

endmodule
