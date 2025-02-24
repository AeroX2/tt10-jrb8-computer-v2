`default_nettype none

module tt_um_aerox2_jrb8_computer (
    input  wire [7:0] ui_in,    // Dedicated inputs - connected to the input switches
    output wire [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
    input wire [7:0] uio_in,  // IOs: Bidirectional Input path
    output wire [7:0] uio_out,  // IOs: Bidirectional Output path
    output wire [7:0] uio_oe,   // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
    input wire ena,  // will go high when the design is enabled
    input wire clk,  // clock
    input wire rst_n  // reset_n - low to reset
);
  wire rst = !rst_n;

  wire _unused_ok = &{1'b0, ena, uio_in, 1'b0};

  reg [15:0] mar;
  reg [15:0] areg;
  reg [15:0] breg;
  reg [15:0] creg;
  reg [15:0] dreg;
  reg [15:0] ereg;
  reg [15:0] freg;
  reg [15:0] greg;
  reg [15:0] hreg;
  reg [7:0] oreg;
  reg [7:0] ireg;

  // Input/output pins
  assign uio_oe[0] = 1;  // cs0 flash
  assign uio_oe[1] = qspi_io_oe[0];  // sd0
  assign uio_oe[2] = qspi_io_oe[1];  // sd1
  assign uio_oe[3] = 1;  // sck
  assign uio_oe[4] = qspi_io_oe[2];  // sd2
  assign uio_oe[5] = qspi_io_oe[3];  // sd3
  assign uio_oe[6] = 1;  // cs1 ram
  assign uio_oe[7] = 0;  // unused
  
  wire [3:0] qspi_io_out;
  wire [3:0] qspi_io_in;
  wire [3:0] qspi_io_oe;
  
  assign uio_out[0] = cs_rom;
  assign qspi_io_in = {uio_in[5], uio_in[4], uio_in[2], uio_in[1]};
  assign {uio_out[5], uio_out[4], uio_out[2], uio_out[1]} = qspi_io_out;
  assign uio_out[3] = sclk;
  assign uio_out[6] = cs_ram;
  assign uio_out[7] = 0;
  
  assign uo_out = oreg;
  // Internal registers
  // A, B, C, D, O, I
  always @(posedge clk, posedge rst) begin
    if (rst) begin
      mar   <= 0;
      areg  <= 0;
      breg  <= 0;
      creg  <= 0;
      dreg  <= 0;
      ereg  <= 0;
      freg  <= 0;
      greg  <= 0;
      hreg  <= 0;
      oreg  <= 0;
      ireg  <= 0;
    end else if (clk) begin
      // TODO: Why does this work but clk && write_en does not?
      if (mari && write_en) mar <= databus;
      else if (ai && write_en) areg <= databus;
      else if (bi && write_en) breg <= databus;
      else if (ci && write_en) creg <= databus;
      else if (di && write_en) dreg <= databus;
      else if (ei && write_en) ereg <= databus;
      else if (fi && write_en) freg <= databus;
      else if (gi && write_en) greg <= databus;
      else if (hi && write_en) hreg <= databus;
      else if (oi && write_en) oreg <= databus;
      ireg <= ui_in;
    end
  end
  wire cs;
  wire cs_rom = ((romo || rami || ramo) ? cs : 1);
  wire cs_ram = (rami || ramo) ? cs : 1;
  
  wire sclk;
  
  wire [7:0] qspi_data;
  wire busy;
  // QSPI Ram for ROM memory
  qspi qspi_module (
      .clk(clk),
      .rst(rst),
      .databus(databus),
      .write(rami),
      .address(romo ? {8'b0, pc} : {8'b1, mar}),
      .data(qspi_data),
      .busy(busy),
      .sclk(sclk),
      .cs(cs),
      .io_out(qspi_io_out),
      .io_in(qspi_io_in)
  );

  // CU decoding the instruction
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
  wire ao2 = output_flags[5];
  wire bo2 = output_flags[6];
  wire co2 = output_flags[7];
  wire doo2 = output_flags[8];
  wire romo = output_flags[9];
  wire ramo = output_flags[10];
  wire jmpo = output_flags[11];

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
  // wire pcc = input_flags[8];
  // wire halt = input_flags[9];

  // Databus
  wire [15:0] aluout;
  wire aluo = ao | bo | co | doo | eo | fo | go | ho;
  logic [15:0] databus;

  always_comb begin
    databus = 0;
    if (aluo) databus = aluout;
    else if (romo || ramo) databus = spi_data;
    else if (io) databus = ireg;
  end

  wire highbits_we;
  wire pcinflag;
  wire [15:0] pc;
  wire [15:0] pcin;

  // CU
  wire [7:0] cins;
  wire [9:0] input_flags;
  wire [11:0] output_flags;
  wire write_en;
  cu cu_module (
      .clk(clk),
      .rst(rst),
      .highbits_we(highbits_we),
      .write_en(write_en),
      .alu_executing(alu_executing),
      .alu_done(alu_done),
      .irin(qspi_data),
      .pcinflag(pcinflag),
      .pcin(pcin),
      .pc(pc),
      .input_flags(input_flags),
      .output_flags(output_flags),
      .cuout(cins)
  );

  logic [15:0] a_alu_in;
  logic [15:0] b_alu_in;
  always_comb begin
    if (ao) a_alu_in = areg;
    else if (bo) a_alu_in = breg;
    else if (co) a_alu_in = creg;
    else if (doo) a_alu_in = dreg;
    else if (eo) a_alu_in = ereg;
    else if (fo) a_alu_in = freg;
    else if (go) a_alu_in = greg;
    else if (ho) a_alu_in = hreg;
    else a_alu_in = 0;

    if (ao2) b_alu_in = areg;
    else if (bo2) b_alu_in = breg;
    else if (co2) b_alu_in = creg;
    else if (doo2) b_alu_in = dreg;
    else if (eo2) b_alu_in = ereg;
    else if (fo2) b_alu_in = freg;
    else if (go2) b_alu_in = greg;
    else if (ho2) b_alu_in = hreg;
    else b_alu_in = 0;
  end

  // ALU
  wire overout;
  wire carryout;
  wire cmpo;
  wire alu_executing;
  wire alu_done;
  alu alu_module (
      .clk(clk),
      .rst(rst),
      .start(alu_executing),
      .done(alu_done),
      .a(a_alu_in),
      .b(b_alu_in),
      .carryin(cflag),
      .oe(aluo),
      .cins(cins),
      .aluout(aluout),
      .overout(overout),
      .carryout(carryout),
      .cmpo(cmpo)
  );

  // CMP
  wire zflag;
  wire oflag;
  wire cflag;
  wire sflag;
  cmp cmp_module (
      .cmpin(databus),
      .overflow(overout),
      .carry(carryout),
      .clk(clk),
      .rst(rst),
      .zflag(zflag),
      .oflag(oflag),
      .cflag(cflag),
      .sflag(sflag),
      .we(cmpo)
  );

  // JMP
  jmp jmp_module (
      .cins(cins),
      .pcin(pc),
      .databus(databus),
      .clk(clk),
      .rst(rst),
      .zflag(zflag),
      .oflag(oflag),
      .cflag(cflag),
      .sflag(sflag),
      .pcoe(pcinflag),
      .pcout(pcin),
      .oe(jmpo),
      .highbits_we(highbits_we)
  );
endmodule
