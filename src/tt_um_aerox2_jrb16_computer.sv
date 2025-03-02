`default_nettype none

module tt_um_aerox2_jrb16_computer (
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

  // Pin definitions
  assign uio_oe[0] = 1;  // cs0 flash
  assign uio_oe[1] = qspi_io_oe[0];  // sd0
  assign uio_oe[2] = qspi_io_oe[1];  // sd1
  assign uio_oe[3] = 1;  // sck
  assign uio_oe[4] = qspi_io_oe[2];  // sd2
  assign uio_oe[5] = qspi_io_oe[3];  // sd3
  assign uio_oe[6] = 1;  // cs1 ram
  assign uio_oe[7] = 0;  // unused

  wire sclk;
  wire cs_rom;
  // wire cs_ram;

  wire [3:0] qspi_io_out;
  wire [3:0] qspi_io_in;
  wire [3:0] qspi_io_oe;

  assign uio_out[0] = cs_rom;
  assign qspi_io_in = {uio_in[5], uio_in[4], uio_in[2], uio_in[1]};
  assign {uio_out[5], uio_out[4], uio_out[2], uio_out[1]} = qspi_io_out;
  assign uio_out[3] = sclk;
  // assign uio_out[6] = cs_ram;
  assign uio_out[6] = 0;
  assign uio_out[7] = 0;

  wire [31:0] rom_data;
  wire [31:0] ram_data;

  wire busy_rom;
  wire busy_ram;

  // TODO: Buffer system
  // QSPI for ROM
  qspi qspi_rom_module (
      .clk(clk),
      .rst(rst),
      .start(1),
      .write(0),
      .address(pc),
      .data_in(23'b0),
      .data_out(rom_data),
      .busy(busy_rom),
      .sclk(sclk),
      .cs(cs_rom),
      .io_out(qspi_io_out),
      .io_in(qspi_io_in),
      .io_oe(qspi_io_oe)
  );

  // wire rami = flags[RAMI_BIT];
  // qspi qspi_ram_module (
  //     .clk(clk),
  //     .rst(rst),
  //     .write(rami),
  //     .address({mpage, mar}),
  //     .data_out(ram_data),
  //     .busy(busy_ram),
  //     .sclk(sclk),
  //     .cs(cs_ram),
  //     .io_out(qspi_io_out),
  //     .io_in(qspi_io_in)
  // );

  wire highbits_we;
  wire pcinflag;
  wire [22:0] pc;
  wire [22:0] pcin;

  // CU
  wire [FLAGS_LEN-1:0] flags;

  wire [9:0] ir;
  wire write_en;
  cu cu_module (
      .clk(clk),
      .rst(rst),
      .highbits_we(highbits_we),
      .write_en(write_en),
      .alu_executing(alu_executing),
      .alu_done(alu_done),
      .irin(rom_data[9:0]),
      .ir(ir),
      .pcinflag(pcinflag),
      .pcin(pcin),
      .pc(pc),
      .flags(flags)
  );

  wire [15:0] mar;
  wire [7:0] mpage;
  wire [7:0] oreg;
  wire [7:0] ireg;

  assign uo_out = oreg;

  // Databus
  wire [15:0] aluout;
  wire [15:0] databus;

  // Register file instantiation
  registers registers_module (
    .clk(clk),
    .rst(rst),
    .flags(flags),
    .ui_in(ui_in),
    .write_en(write_en),

    .rom(rom_data[25:10]),
    // .ram(ram_data[]),
    .ram(1),
    .aluout(aluout),
    .databus(databus),

    .alu_a(alu_a),
    .alu_b(alu_b),

    .mar(mar),
    .mpage(mpage),
    .oreg(oreg)
  );

  wire jmpo = flags[JMPO_BIT];
  wire aluo = flags[ALUO_BIT];

  // ALU
  wire overout;
  wire carryout;
  wire cmpo;
  wire alu_executing;
  wire alu_done;

  wire [15:0] alu_a;
  wire [15:0] alu_b;

  alu alu_module (
      .clk(clk),
      .rst(rst),
      .start(alu_executing),
      .done(alu_done),
      .a(alu_a),
      .b(alu_b),
      .carryin(cflag),
      .oe(aluo),
      .ir(ir),
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
      .ir(ir),
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
