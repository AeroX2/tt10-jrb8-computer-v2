module alu (
    input clk,
    input rst,

    // Control
    input start,
    output logic done,

    // Inputs
    input [15:0] a,
    input [15:0] b,
    input [7:0] ir,
    input oe,
    input carryin,

    // Outputs
    output logic carryout,
    output [15:0] aluout,
    output overout,
    output cmpo,
    output enable_flags
);
  localparam CLR_CMP_INS = 'h50;
  // TODO(This needs to be filled in)
  localparam FLAGS_OFF_INS = 'h54;
  localparam FLAGS_ON_INS = 'h53;
  localparam CARRY_OFF_INS = 'h51;
  localparam CARRY_ON_INS = 'h52;
  localparam SIGN_OFF_INS = 'h53;
  localparam SIGN_ON_INS = 'h54;

  reg [10:0] alu_rom[0:255];
  initial begin
    $readmemh("../rom/alu_rom.mem", alu_rom);
  end

  logic done_reg;

  logic [10:0] val;
  wire za = val[0];
  wire ia = val[1];
  wire zb = val[2];
  wire ib = val[3];
  wire io = val[4];
  wire po = val[5];
  wire high = val[6];
  wire cmp = val[7];
  wire [2:0] cselect = val[10:8];

  logic [15:0] aandz;
  logic [15:0] bandz;

  logic [15:0] xora;
  logic [15:0] xorb;

  logic [16:0] full_sum;

  logic [16:0] mult;
  logic [15:0] partial_products [0:3];
  logic [31:0] shifted_products [0:3];

  logic [15:0] muxoutput;

  wire carried = carry_mode && carryin;

  typedef enum {
    IDLE,
    DECODE,
    ANDZ,
    XORZ,
    SUM,
    AND,
    LEFT_SHIFT,
    RIGHT_SHIFT,
    MULT,
    DIV,
    INVERT
  } State;

  State state, next_state;
  logic flags_mode, carry_mode, signed_mode;
  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      state <= IDLE;

      done_reg <= 1;
      flags_mode <= 1;
      carry_mode <= 0;
      signed_mode <= 0;

      val <= 0;

      aandz <= 0;
      bandz <= 0;

      xora <= 0;
      xorb <= 0;

      muxoutput <= 0;
    end else if (clk) begin
      state <= next_state;
      case (state)
        IDLE: begin
          if (ir == FLAGS_OFF_INS) begin
            done_reg <= ~done_reg;
            flags_mode <= 0;
          end else if (ir == FLAGS_ON_INS) begin
            done_reg <= ~done_reg;
            flags_mode <= 1;
          end else if (ir == CARRY_OFF_INS) begin
            done_reg <= ~done_reg;
            carry_mode <= 0;
          end else if (ir == CARRY_ON_INS) begin
            done_reg <= ~done_reg;
            carry_mode <= 1;
          end else if (ir == SIGN_OFF_INS) begin
            done_reg <= ~done_reg;
            signed_mode <= 0;
          end else if (ir == SIGN_ON_INS) begin
            done_reg <= ~done_reg;
            signed_mode <= 1;
          end else if (start) done_reg <= 0;
          else done_reg <= 1;
        end
        DECODE: begin
          val <= alu_rom[ir];
        end
        ANDZ: begin
          aandz <= za ? 0 : a;
          bandz <= zb ? 0 : b;
        end
        XORZ: begin
          xora <= aandz ^ {16{ia}};
          xorb <= bandz ^ {16{ib}};
        end
        SUM: begin
          muxoutput <= full_sum[15:0];
        end
        AND: begin
          muxoutput <= xora & xorb;
        end
        LEFT_SHIFT: begin
          muxoutput <= xora << xorb;
        end
        RIGHT_SHIFT: begin
          muxoutput <= xora >> xorb;
        end
        MULT: begin
          // TODO: Multiplication
          // mult <= shifted_products[0] + shifted_products[1] + shifted_products[2] + shifted_products[3];
          next_state = INVERT;
        end
        DIV: begin
          // TODO: Division
          next_state = INVERT;
        end
        INVERT: begin
          next_state = IDLE;
        end
    endcase
    end
  end

  always_comb begin
    done = done_reg;
    next_state = IDLE;

    // for (int i = 0; i < 4; i++) begin
    //   partial_products[i] = mult_b[i*4 +: 4] ? mult_a << (i*4) : 16'h0;
    //   shifted_products[i] = {16'h0, partial_products[i]} << (i*4);
    // end

    full_sum = xora + xorb + {15'b0, po} + {15'b0, (carry_mode && cmp) ? carried : 1'b0};

    case (state)
      IDLE: begin
        if (start) next_state = DECODE;
        else next_state = IDLE;
      end
      DECODE: begin
        next_state = ANDZ;
      end
      ANDZ: begin
        next_state = XORZ;
      end
      XORZ: begin
        case (cselect)
          0: next_state = SUM;
          1: next_state = AND;
          2: next_state = LEFT_SHIFT;
          3: next_state = RIGHT_SHIFT;
          4: next_state = MULT;
          5: next_state = DIV;
        endcase
      end
      SUM: begin
        next_state = INVERT;
      end
      AND: begin
        next_state = INVERT;
      end
      MULT: begin
        next_state = INVERT;
      end
      DIV: begin
        next_state = INVERT;
      end
      INVERT: begin
        next_state = IDLE;
      end
    endcase
  end

  assign aluout = oe ? muxoutput : 0;
  assign cmpo = (cmp || ir == CLR_CMP_INS) && state == INVERT;
  assign enable_flags = flags_mode;

  assign carryout = cselect == 0 ? (((ia | ib) & po) ? !full_sum[16] : full_sum[16]) : 0;
  assign overout = ((~muxoutput[15]) & xora[15] & xorb[15]) | (muxoutput[15] & ~xora[15] & ~xorb[15]);
endmodule
