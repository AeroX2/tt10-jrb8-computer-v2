`default_nettype none

module cu (
    input clk,
    input rst,

    input alu_done,
    output logic alu_executing,

    input [9:0] irin,
    output logic [9:0] ir,

    input pcinflag,
    input [22:0] pcin,
    output logic [22:0] pc,
    output logic write_en,

    output logic [FLAGS_LEN-1:0] flags
);

  logic [26:0] cu_rom[1024];
  logic [26:0] cu_rom_2[1024];
  initial begin
    $readmemh("../rom/cu_rom.mem", cu_rom);
    $readmemh("../rom/cu_rom_2.mem", cu_rom_2);
    // $readmemh("../rom/cu_flag_conv.mem", cu_flag_conv);
  end

  // States
  typedef enum {
    UPDATE_IR,
    FLAGS_1,
    FLAGS_1_ALU,
    FLAGS_1_EVENTS,
    FLAGS_2,
    FLAGS_2_ALU,
    FLAGS_2_EVENTS
  } state_t;

  state_t cu_state, cu_next_state;

  logic alu_done_reg;

  logic [9:0] ir_reg;
  logic [22:0] pc_reg;
  logic [FLAGS_LEN-1:0] flags_reg;

  wire pcc = flags[PCC_BIT];
  wire aluo = flags[ALUO_BIT];
  wire halt = flags[HALT_BIT];
  wire another_cycle = flags[AC_BIT];

  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      pc_reg <= 0;
      ir_reg <= 0;
      cu_state <= UPDATE_IR;

      alu_done_reg <= 1;
    end else if (!halt) begin
      cu_state <= cu_next_state;

      alu_done_reg <= alu_done;

      case (cu_state)
        UPDATE_IR: begin
          ir_reg <= irin;
        end
        FLAGS_1, FLAGS_2: begin
          // If PCC is set, count the clock.
          if (pcc) pc_reg <= pc_reg + 1;
        end
        FLAGS_2_EVENTS: begin
          if (pcinflag) pc_reg <= pcin;
          else pc_reg <= pc_reg + 1;
        end
        default begin
          // No need to do anything here
        end
      endcase
    end
  end

  always_comb begin
    alu_executing = 0;
    cu_next_state = UPDATE_IR;

    unique case (cu_state)
      UPDATE_IR: begin
        cu_next_state = FLAGS_1;
      end
      FLAGS_1: begin
        if (aluo) cu_next_state = FLAGS_1_ALU;
        else cu_next_state = FLAGS_1_EVENTS;
      end
      FLAGS_1_ALU: begin
        alu_executing = alu_done_reg;
        if (alu_done && !alu_done_reg) begin
          cu_next_state = FLAGS_1_EVENTS;
        end else cu_next_state = FLAGS_1_ALU;
      end
      FLAGS_1_EVENTS: begin
        if (another_cycle) cu_next_state = UPDATE_IR;
        else cu_next_state = FLAGS_2;
      end
      FLAGS_2: begin
        if (aluo) cu_next_state = FLAGS_2_ALU;
        else cu_next_state = FLAGS_2_EVENTS;
      end
      FLAGS_2_ALU: begin
        alu_executing = alu_done_reg;
        if (alu_done && !alu_done_reg) begin
          cu_next_state = FLAGS_2_EVENTS;
        end else cu_next_state = FLAGS_2_ALU;
      end
      FLAGS_2_EVENTS: begin
        cu_next_state = UPDATE_IR;
      end
    endcase
  end

  always_comb begin
    unique case (cu_state)
      UPDATE_IR: begin
        // Turn on PCC and ROMO
        flags_reg = UPDATE_IR_FLAGS;
      end
      FLAGS_1, FLAGS_1_ALU, FLAGS_1_EVENTS: begin
        flags_reg = cu_rom[ir_reg];
      end
      FLAGS_2, FLAGS_2_ALU, FLAGS_2_EVENTS: begin
        flags_reg = cu_rom_2[ir_reg];
      end
    endcase
  end

  assign pc = pc_reg;
  assign flags = flags_reg;

  assign write_en = cu_state == FLAGS_1_EVENTS || cu_state == FLAGS_2_EVENTS;
  assign ir = ir_reg;
endmodule
